#Inode File Type Values
EXT2_FT_UNKNOWN 	= 0x00
EXT2_FT_REG_FILE 	= 0x01
EXT2_FT_DIR 		= 0x02
EXT2_FT_CHRDEV 		= 0x03
EXT2_FT_BLKDEV 		= 0x04
EXT2_FT_FIFO 		= 0x05
EXT2_FT_SOCK 		= 0x06
EXT2_FT_SYMLINK 	= 0x07

#Inode Mode Values http://www.nongnu.org/ext2-doc/ext2.html#I-MODE
EXT2_S_IFSOCK 		= 0xC000	#Socket
EXT2_S_IFLNK 		= 0xA000	#Symbolic Link
EXT2_S_IFREG 		= 0x8000	#Regular File
EXT2_S_IFBLK 		= 0x6000	#Block Device
EXT2_S_IFDIR 		= 0x4000	#Directory
EXT2_S_IFCHR 		= 0x2000	#Character Device
EXT2_S_IFIFO 		= 0x1000	#Fifo