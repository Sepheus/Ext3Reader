require 'date'
require_relative "constants."

module Ext3

SUPERBLOCK_SIZE = 1024
SUPERBLOCK_OFFSET = 1024
EXT2_ROOT_INO = 2

class SuperBlock
	S_LOG_BLOCK_SIZE = 6
	S_LOG_FRAG_SIZE = 7

	def initialize(diskName)
		@diskName = diskName
		getInfo()
	end

	public
	[:inodes,:blocks,:reservedBlocks,:freeBlocks,:freeInodes,:firstBlock,:blockSize,:fragSize,:blocksPerGroup,:fragsPerGroup,
	 :inodesPerGroup,:mountTime,:writeTime,:mountCount,:maxMountCount,:magic,:state,:errorHandling,:minorVersion,:lastCheck,
	 :checkInterval,:creatorOS,:majorVersion,:uidReservedBlocks,:gidReservedBlocks,:firstInode,:inodeSize,:superBlockGroupID,
	 :compatibleFeatures,:incompatibleFeatures,:readOnlyFeatures,:fileSystemID,:volumeName,:lastMount,:compressionAlgo,:preallocFileBlocks,
	 :preallocDirBlocks,:journalID,:journalInode,:journalDevice,:lastOrphan,:hashSeed,:hashVersion,:mountOptions,:firstMetaBlockGroup].each_with_index { |method,i|
	 	define_method method do @superBlock[i] end
	 }

	private
	def getInfo
		@superBlock = IO.binread(@diskName,SUPERBLOCK_SIZE,SUPERBLOCK_OFFSET)
		#Refer to http://www.nongnu.org/ext2-doc/ext2.html#SUPERBLOCK to understand unpack string.
		#http://ruby-doc.org/core-2.0.0/String.html#method-i-unpack
		@superBlock = @superBlock.unpack("V7l<V5vs<v4V4v2Vv2V3H32H32A64VC2x2H32V3H32Cx3V2")
		#Determine block size.
		@superBlock[S_LOG_BLOCK_SIZE] = SUPERBLOCK_SIZE << @superBlock[S_LOG_BLOCK_SIZE]
		#Determine fragment size.  Negative values are legacy support.
		@superBlock[S_LOG_FRAG_SIZE] = @superBlock[S_LOG_FRAG_SIZE]>=0 ? SUPERBLOCK_SIZE << @superBlock[S_LOG_FRAG_SIZE] : SUPERBLOCK_SIZE >> @superBlock[S_LOG_FRAG_SIZE]
	end
end

class GroupDescriptorEntry
	def initialize(entry)
		@entry = entry
	end

	public
	[:blockBitmapID,:inodeBitmapID,:inodeTableID,:freeBlocks,:freeInodes,:directoriesUsed].each_with_index { |method,i|
	 	define_method method do @entry[i] end
	 }
end

class GroupDescriptorTable
	def initialize(diskName,superBlock)
		@diskName = diskName
		@superBlock = superBlock
		getGDT
	end

	def entries
		@entries
	end

	private
	def getGDT
		@gdt = IO.binread(@diskName,@superBlock.blockSize,(@superBlock.firstBlock+1)*SUPERBLOCK_SIZE)
		@blockGroups = (@superBlock.blocks/@superBlock.blocksPerGroup.to_f).ceil
		@gdt = @gdt.unpack("V3v3x14"*@blockGroups)
		@entries = @gdt.each_slice(6).map { |entry| GroupDescriptorEntry.new(entry) }
	end
end

class Inode
	def initialize(diskName,superBlock,inodeLocation)
		@superBlock = superBlock
		@diskName = diskName
		@inodeLocation = inodeLocation
		@gdt = GroupDescriptorTable.new(diskName,@superBlock)
		getInode
	end

	public
	[:mode,:uid,:size,:accessTime,:changeTime,:modTime,:delTime,:groupID,:linkCount,:sectorCount,:flags,
	 :osd1,:directBlockPtr,:singleIndirectBlockPtr,:doubleIndirectBlockPtr,:tripleIndirectBlockPtr,:genID,
	 :fileACL,:dirACL,:fragAddress,:osd2].each_with_index { |method,i|
	 	define_method method do @inode[i] end
	}

	def isDirectory?
		self.mode & EXT2_S_IFDIR > 0
	end

	def isFile?
		self.mode & EXT2_S_IFREG > 0
	end

	private
	def getInode
		groupNumber = (@inodeLocation-1)/@superBlock.inodesPerGroup
		gde = @gdt.entries[groupNumber]
		#How many inodes per block?
		inodesPerBlock = (@superBlock.blockSize/@superBlock.inodeSize)
		#Which block is the inode in?
		inodeBlock = gde.inodeTableID + (((@inodeLocation-1) % @superBlock.inodesPerGroup) / inodesPerBlock)
		imageSeek = inodeBlock*@superBlock.blockSize
		indexOfInodeInTable = (((@inodeLocation-1) % @superBlock.inodesPerGroup) % inodesPerBlock)
		offsetIntoBlock = indexOfInodeInTable * @superBlock.inodeSize
		imageSeek += offsetIntoBlock
		@inode = IO.binread(@diskName,@superBlock.inodeSize,imageSeek).unpack("v2V5v2V2a4a48V3V4a12")
		@inode[12] = @inode[12].unpack("V*")
	end
end

class DirectoryEntry
	def initialize(block)
		@block = block
		getDirectory
	end

	public
	[:inode,:length,:nameLength,:fileType,:name].each_with_index { |method,i|
	 	define_method method do @directory[i] end
	}

	def getDirectory
		name = @block.unpack("@6C")[0]
		@directory = @block.unpack("VvCCa#{name}")
	end
end

class Directories
	include Enumerable
	def initialize(diskName,superBlock,inode)
		@inode = inode
		@superBlock = superBlock
		@diskName = diskName
		@directories = []
		getDirectories
	end

	def each(&block)
		@directories.each { |directory| if block_given? then block.call directory else yield directory end }
	end

	private

	def getDirectories
		block = IO.binread(@diskName,@superBlock.blockSize,@superBlock.blockSize * @inode.directBlockPtr.first)
		if @inode.isDirectory?
			offset = 0
			until offset.eql? @superBlock.blockSize
				@directories << DirectoryEntry.new(block[offset..-1])
				offset += @directories.last.length
			end
		end
		if @inode.isFile?
			#block.unpack("a#{@inode.size}")
			inodes = @inode.directBlockPtr.take_while { |n| n > 0 }
			inodes += IO.binread(@diskName,@superBlock.blockSize,@superBlock.blockSize * @inode.singleIndirectBlockPtr).unpack("V*").take_while { |n| n > 0 }
			fileSize = @inode.size
			buffSize = @inode.size < @superBlock.blockSize ? @inode.size : @superBlock.blockSize
			p @inode
			inodes.inject(0) { |offset,id|
				buff = IO.binread(@diskName,buffSize,@superBlock.blockSize * id)
				IO.binwrite("Anime3.jpg",buff,offset)
				offset+=@superBlock.blockSize
			}
		end
	end
end


#Ext3 file system reader
class Ext3Reader
	def initialize(diskName)
		@diskName = diskName
		@superBlock = SuperBlock.new(diskName)
		root = Inode.new(diskName,@superBlock,EXT2_ROOT_INO)
		Directories.new(diskName,@superBlock,root).each { |directory| puts "#{directory.inode}: #{directory.name}" }
		n = Inode.new(diskName,@superBlock,1726)
		Directories.new(diskName,@superBlock,n).each { |directory| puts "#{directory.inode}: #{directory.name}" }
		#n = Inode.new(diskName,@superBlock,1727)
		#Directories.new(diskName,@superBlock,n).each { |directory| puts "#{directory.inode}: #{directory.name}" }
	end
	def superBlock
		@superBlock
	end
	def displayInfo
		puts "Filesystem volume name:\t#{@superBlock.volumeName}"
		puts "Last mounted on:\t#{@superBlock.lastMount}"
		puts "Filesystem UUID:\t#{@superBlock.fileSystemID}"
		printf "Filesystem magic number:\t0x%X\n",@superBlock.magic
		puts "Filesystem revision:\t#{@superBlock.majorVersion}"
		puts "Block count:\t#{@superBlock.blocks}"
		puts "Inode count:\t#{@superBlock.inodes}"
		puts "Reserved blocks:\t#{@superBlock.reservedBlocks}"
		puts "Free blocks:\t#{@superBlock.freeBlocks}"
		puts "Free inodes:\t#{@superBlock.freeInodes}"
		puts "First block:\t#{@superBlock.firstBlock}"
		puts "Block size:\t#{@superBlock.blockSize}"
		puts "Fragment size:\t#{@superBlock.fragSize}"
		puts "Blocks per group:\t#{@superBlock.blocksPerGroup}"
		puts "Fragments per group:\t#{@superBlock.fragsPerGroup}"
		puts "Inodes per group:\t#{@superBlock.inodesPerGroup}"
		puts "Last mount time:\t#{Time.at(@superBlock.mountTime).asctime}"
		puts "Last write time:\t#{Time.at(@superBlock.writeTime).asctime}"
		puts "Mount count:\t#{@superBlock.mountCount}"
		puts "Maximum mount count:\t#{@superBlock.maxMountCount}"
		puts "Last checked:\t#{Time.at(@superBlock.lastCheck).asctime}"
	end
end
end


myDisk = Ext3::Ext3Reader.new("Disk2")
#myDisk.displayInfo

Ext3::Directories.new("Disk2",myDisk.superBlock,Ext3::Inode.new("Disk2",myDisk.superBlock,1727))