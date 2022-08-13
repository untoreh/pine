# The boot partition is too small
Upgrades may fail because the boot partition is too small. Indeed the partition layout used is quite stingy. 
If the overflow is not much, you can re-create the boot partition in-place using smaller inode size like:

``` shell
mkfs.ext2 -L /boot -I 128 /dev/vda1
```

Which will use inodes of 128 bytes.
