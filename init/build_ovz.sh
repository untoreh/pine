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
rm -f ${artifact}.${os_name}.sq
mksquashfs $sysroot ${artifact}.${os_name}.sq

## since building from scratch does not have a delta, we create a dumb delta.tar to make travis happy
# echo 1>dummy && tar cvf ${delta}.tar dummy && rm dummy
rev=$(ostree --repo=$rootfs/ostree/repo rev-parse $ref)
ostree --repo=$rootfs/ostree/repo static-delta generate $ref --empty --inline --min-fallback-size 0 --filename=${rev} | grep -vE "^\.\/"
tar cf ${delta}_base.tar $rev
