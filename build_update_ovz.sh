#!/bin/bash
. ./functions.sh

[ ! -e make_ovz_success ] && { err "make_ovz script failed aborting"; exit 1; }
set -e

name=pine_ovz
artifact_repo="untoreh/pine"
delta="delta_ovz"
rootfs=rootfs
artifact="${rootfs}.${name}.sq"
ref="trunk"

## confirm we made a new tree
set +e
if [ ! "$(find ${name}_tree/* -maxdepth 0 | wc -l)" -gt 0 ]; then
	echo "newer tree not grown. (tree folder is empty)"
	exit 1
fi
set -e

## deps
install_tools ostree util-linux wget
cp -p $PWD/utils/*squashfs /usr/bin

## prev image
if [ ! -e "$artifact " ]; then
    fetch_artifact $artifact_repo $artifact - >$artifact
    if [ "$?" = 1 ]; then
	      echo "no previous build found, creating new rootfs"
	      init/build_ovz.sh
	      exit
    fi
else
    rm -rf $rootfs
fi
unsquashfs -d $rootfs $artifact

## delete deployments and prune before commit
deployments=$(ostree --repo=$rootfs/ostree/repo refs ostree)
for d in $deployments; do
	ostree --repo=$rootfs/ostree/repo refs --delete $d
done
cmts=$(ostree --repo=$rootfs/ostree/repo log trunk | grep "^commit " | cut -d' ' -f2 | tail +2)
for c in $cmts; do
	ostree prune --repo=$rootfs/ostree/repo --delete-commit=$c
done
ostree admin cleanup --sysroot=$rootfs

## now commit the new tree to the previous repo in the rootfs
rev=$(ostree --repo=$rootfs/ostree/repo commit --skip-if-unchanged -s $(date)'-build' -b $ref --tree=dir=${name}_tree)

## check repo
ostree fsck --repo=$rootfs/ostree/repo || (err "ostree repo check failed" && exit 1)

## compare checksums
old_csum=$(fetch_artifact $artifact_repo /${name}.sum -)
new_csum=$(ostree --repo=$rootfs/ostree/repo ls $ref -Cd | awk '{print $5}')
compare_csums

## redeploy
## remote boot files to avoid failing the upgrade (because it triggers ostree grub
## hooks which don't work in the build environment
rm -rf $rootfs/boot/grub*
ostree admin deploy --sysroot=$rootfs --os=$name trunk

## prune older commits
ostree prune --repo=$rootfs/ostree/repo --refs-only --keep-younger-than="3 months ago"
## then generate the delta and archive it
ostree --repo=$rootfs/ostree/repo static-delta generate $ref --inline --min-fallback-size 0 --filename=${rev} | grep -vE "^\.\/"
tar cf ${delta}.tar $rev
ostree --repo=$rootfs/ostree/repo static-delta generate $ref --empty --inline --min-fallback-size 0 --filename=${rev} | grep -vE "^\.\/"
tar cf ${delta}_base.tar $rev

## squash image (defaults gzip 128k bs)
rm -f $artifact
mksquashfs $rootfs $artifact -noappend
archive_abs=$(realpath $artifact)
archive_bytes=$(stat -c "%s" $archive_abs 2>/dev/null)
archive_size=$(numfmt --to=iec-i --suffix=B --format="%.3f" $archive_bytes 2>/dev/null)
princ "squashed ovz file $archive_abs of size $archive_size"
