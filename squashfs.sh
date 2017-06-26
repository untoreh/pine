#!/bin/sh

repo_squashfs="https://github.com/plougher/squashfs-tools"
patch_1="https://raw.githubusercontent.com/alpinelinux/aports/8b7e48dcaf6a2049edeffaa957db618e923b78ab/main/squashfs-tools/CVE-2015-4645.patch"
patch_2="static.patch"

rm -rf squashfs-tools
git clone $repo_squashfs 
cd squashfs-tools

## patches
wget $patch_1
git apply $(basename $patch_1)
cat <<EOF >$patch_2
diff --git a/squashfs-tools/mksquashfs.c b/squashfs-tools/mksquashfs.c
index 82fcbbf..e525f97 100644
--- a/squashfs-tools/mksquashfs.c
+++ b/squashfs-tools/mksquashfs.c
@@ -830,17 +830,15 @@ char *subpathname(struct dir_ent *dir_ent)
 }
 
 
-inline unsigned int get_inode_no(struct inode_info *inode)
+static inline unsigned int get_inode_no(struct inode_info *inode)
 {
 	return inode->inode_number;
 }
 
-
-inline unsigned int get_parent_no(struct dir_info *dir)
+static inline unsigned int get_parent_no(struct dir_info *dir)
 {
 	return dir->depth ? get_inode_no(dir->dir_ent->inode) : inode_no;
 }
-
 	
 int create_inode(squashfs_inode *i_no, struct dir_info *dir_info,
 	struct dir_ent *dir_ent, int type, long long byte_size,
@@ -2029,7 +2027,7 @@ struct file_info *duplicate(long long file_size, long long bytes,
 }
 
 
-inline int is_fragment(struct inode_info *inode)
+static inline int is_fragment(struct inode_info *inode)
 {
 	off_t file_size = inode->buf.st_size;
 
@@ -2044,7 +2042,6 @@ inline int is_fragment(struct inode_info *inode)
 		(inode->always_use_fragments && file_size & (block_size - 1)));
 }
 
-
 void put_file_buffer(struct file_buffer *file_buffer)
 {
 	/*
@@ -2998,13 +2995,12 @@ struct inode_info *lookup_inode2(struct stat *buf, int pseudo, int id)
 }
 
 
-inline struct inode_info *lookup_inode(struct stat *buf)
+static inline struct inode_info *lookup_inode(struct stat *buf)
 {
 	return lookup_inode2(buf, 0, 0);
 }
 
-
-inline void alloc_inode_no(struct inode_info *inode, unsigned int use_this)
+static inline void alloc_inode_no(struct inode_info *inode, unsigned int use_this)
 {
 	if (inode->inode_number == 0) {
 		inode->inode_number = use_this ? : inode_no ++;
@@ -3014,8 +3010,7 @@ inline void alloc_inode_no(struct inode_info *inode, unsigned int use_this)
 	}
 }
 
-
-inline struct dir_ent *create_dir_entry(char *name, char *source_name,
+static inline struct dir_ent *create_dir_entry(char *name, char *source_name,
 	char *nonstandard_pathname, struct dir_info *dir)
 {
 	struct dir_ent *dir_ent = malloc(sizeof(struct dir_ent));
@@ -3032,8 +3027,7 @@ inline struct dir_ent *create_dir_entry(char *name, char *source_name,
 	return dir_ent;
 }
 
-
-inline void add_dir_entry(struct dir_ent *dir_ent, struct dir_info *sub_dir,
+static inline void add_dir_entry(struct dir_ent *dir_ent, struct dir_info *sub_dir,
 	struct inode_info *inode_info)
 {
 	struct dir_info *dir = dir_ent->our_dir;
@@ -3048,8 +3042,7 @@ inline void add_dir_entry(struct dir_ent *dir_ent, struct dir_info *sub_dir,
 	dir->count++;
 }
 
-
-inline void add_dir_entry2(char *name, char *source_name,
+static inline void add_dir_entry2(char *name, char *source_name,
 	char *nonstandard_pathname, struct dir_info *sub_dir,
 	struct inode_info *inode_info, struct dir_info *dir)
 {
@@ -3060,8 +3053,7 @@ inline void add_dir_entry2(char *name, char *source_name,
 	add_dir_entry(dir_ent, sub_dir, inode_info);
 }
 
-
-inline void free_dir_entry(struct dir_ent *dir_ent)
+static inline void free_dir_entry(struct dir_ent *dir_ent)
 {
 	if(dir_ent->name)
 		free(dir_ent->name);
@@ -3081,13 +3073,11 @@ inline void free_dir_entry(struct dir_ent *dir_ent)
 	free(dir_ent);
 }
 
-
-inline void add_excluded(struct dir_info *dir)
+static inline void add_excluded(struct dir_info *dir)
 {
 	dir->excluded ++;
 }
 
-
 void dir_scan(squashfs_inode *inode, char *pathname,
 	struct dir_ent *(_readdir)(struct dir_info *), int progress)
 {

EOF
git apply $(basename $patch_2)

## deps (additional to prepare pkgs)
apk add zlib-dev

cd squashfs-tools
LDFLAGS="-static" CFLAGS="-static" make && make install