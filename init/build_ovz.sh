#!/bin/bash
. ./functions.sh

[ ! -e make_ovz_success ] && { err "make_ovz script failed aborting"; exit 1; }
set -e

cd /srv
rootfs=rootfs
sysroot=rootfs
delta="delta_ovz"
os_name=pine_ovz
artifact=rootfs
ref=trunk

rm -rf $sysroot &>/dev/null
mkdir -p $sysroot

ostree admin init-fs $sysroot
ostree admin os-init --sysroot=$sysroot $os_name
ostree --repo=${sysroot}/ostree/repo pull-local /srv/$os_name $ref
ostree admin deploy --sysroot=$sysroot --os=$os_name $ref

ostree fsck --repo=${sysroot}/ostree/repo

## squash image (defaults gzip 128k bs)
squashed_file=${artifact}.${os_name}.sq
rm -f $squashed_file
mksquashfs $sysroot $squashed_file
archive_abs=$(realpath $squashed_file)
archive_bytes=$(stat -c "%s" $archive_abs 2>/dev/null)
archive_size=$(numfmt --to=iec-i --suffix=B --format="%.3f" $archive_bytes 2>/dev/null)
printc "squashed ovz file $squashed_file of size $archive_size"

## since building from scratch does not have a delta, we create a dumb delta.tar to make travis happy
# echo 1>dummy && tar cvf ${delta}.tar dummy && rm dummy
rev=$(ostree --repo=$rootfs/ostree/repo rev-parse $ref)
ostree --repo=$rootfs/ostree/repo static-delta generate $ref --empty --inline --min-fallback-size 0 --filename=${rev} | grep -vE "^\.\/"
tar cf ${delta}_base.tar $rev
printc "ovz build finished"
