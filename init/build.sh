#!/bin/bash
. ./functions.sh
. ./build_common.sh

rootfs=rootfs
sysroot=/os

config_env
cd $repodir
clear_sysroot

image_name="image.pine"
dd if=/dev/zero of=$image_name bs=512 count=1048576 conv=fsync

LOOPDEV=$(loop_image "${image_name}")

root_part=${LOOPDEV}p3
swap_part=${LOOPDEV}p2
boot_part=${LOOPDEV}p1
make_fs

# set vars, mount the partitions
os_name=pine
repo_name=pine
ref_name=trunk

mount_parts

# First create the main directories in the ROOT,
# then setup an OS repository in the new ROOT
# then pull the data of the prebuilt tree in the OS repo
ostree admin init-fs $sysroot
ostree admin os-init --sysroot=$sysroot $os_name
ostree --repo=$sysroot/ostree/repo pull-local /srv/$repo_name $ref_name
# then deploy a REF, which will setup the config used by grub to boot
# the correct REF
ostree_deploy

fake_deploy

install_grub

# wrap up
ostree_fsck
rev_number=$(ostree --repo=$sysroot/ostree/repo rev-parse $ref_name)
gen_delta $rev_number empty
arc_delta $PWD delta_base.tar $rev_number

unmount_sysroot $LOOPDEV $sysroot
repair_xfs $boot_part $root_part
losetup -d $LOOPDEV &>/dev/null

## checksum and compress
csum_arc_image image.pine
