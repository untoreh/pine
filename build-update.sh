#!/bin/bash
. ./functions.sh
name=pine

## confirm we made a new tree
if [ ! "$(find ${name}_tree/* -maxdepth 0 | wc -l)" -gt 0 ]; then
	echo "newer tree not grown. (tree folder is empty)"
	exit 1
fi

cleanup() {
	{
		umount loroot
		cd -
		losetup -d /dev/loop$lon
	} &>/dev/null
}

case $1 in
	-t)
		trap cleanup SIGINT SIGTERM EXIT
		;;
	-c)
		cleanup
		losetup -D
		exit
		;;
	*) ;;
esac

cp -a ./dist/cfg/repositories /etc/apk/repositories

install_tools ostree util-linux wget

h=$PWD
mkdir -p imgtmp
cd imgtmp
fetch_artifact untoreh/pine image.pine.tgz $PWD

if [ ! -f $PWD/image.pine -o "$?" != 0 ]; then
    printc "no latest image found, trying last image available."
    ## try the last if there is no latest
    fetch_artifact untoreh/pine:last image.pine.tgz $PWD
    if [ ! -f $PWD/image.pine -o "$?" != 0 ]; then
	      err "failed downloading previous image, terminating."
	      exit 1
    fi
fi

lon=0
while [ -z "$(losetup -P /dev/loop$lon $PWD/image.pine && echo true)" ]; do
	lon=$((lon + 1))
	sleep 1
done

## https://github.com/moby/moby/issues/27886#issuecomment-417074845
LOOPDEV=$(losetup --find --show --partscan "${PWD}/image.pine")

# drop the first line, as this is our LOOPDEV itself, but we only what the child partitions
PARTITIONS=$(lsblk --raw --output "MAJ:MIN" --noheadings ${LOOPDEV} | tail -n +2)
COUNTER=1
for i in $PARTITIONS; do
    MAJ=$(echo $i | cut -d: -f1)
    MIN=$(echo $i | cut -d: -f2)
    if [ ! -e "${LOOPDEV}p${COUNTER}" ]; then mknod ${LOOPDEV}p${COUNTER} b $MAJ $MIN; fi
    COUNTER=$((COUNTER + 1))
done

## p3 is the root partition
mkdir -p /upos
# use nouuid for xfs
mount -o nouuid ${LOOPDEV}p3 /upos
## p1 is the boot partition
mkdir -p /upos/boot
# don't use nouuid for ext2
mount ${LOOPDEV}p1 /upos/boot

## delete deployments and prune before commit
deployments=$(ostree --repo=/upos/ostree/repo refs ostree)
if [ $(wc -l <<< "$deployments") -gt 1 ]; then
    for d in $deployments; do
        ostree --sysroot=/upos admin undeploy ${d/*\/}
    done
    ostree admin cleanup --sysroot=/upos
fi
# cmts=$(ostree log --repo=/upos/ostree/repo trunk | grep "^commit " | cut -d' ' -f2 | tail +1)
# for c in $cmts; do
# 	ostree prune --repo=/upos/ostree/repo --delete-commit=$c
# done

## now commit the new tree to the old repo
## the image has to have enough space for commits...
ostree config --repo=/upos/ostree/repo set core.min-free-space-percent 0
rev=$(ostree --repo=/upos/ostree/repo commit --skip-if-unchanged -s $(date)'-build' -b trunk --tree=dir=${h}/${name}_tree)
if [ "$?" != 0 ]; then
    rev=$(ostree --repo=${h}/${name} commit --skip-if-unchanged -s $(date)'-build' -b trunk --tree=dir=${h}/${name}_tree)
fi

## check repo
ostree fsck --repo=/upos/ostree/repo || (err "ostree repo check failed" && exit 1)

## compare checksums
old_csum=$(fetch_artifact untoreh/pine /pine.sum -)
[ -z "$old_csum" ] && err old_csum empty
new_csum=$(ostree --repo=/upos/ostree/repo ls trunk -Cd | awk '{print $5}')
[ -z "$new_csum" ] && err new_csum empty
printc "comparing checksums $old_csum $new_csum..."
compare_csums

## redeploy
## remove boot files to avoid failing the upgrade (because it triggers ostree grub
## hooks which doesn't work in the build environment
rm -rf /upos/boot/*
ostree admin deploy --sysroot=/upos --os=pine trunk \
	--karg=root=UUID=$(blkid -s UUID -o value /dev/loop${lon}p3) \
	--karg=rootfstype=xfs \
	--karg=rootflags=rw,noatime,nodiratime,largeio,inode64



## recreate boot files
dpl=$(ls -dt /upos/ostree/deploy/pine/deploy/* | grep -E "\.[0-9]$" | head -1)
mount --bind $dpl $dpl
mount --bind /upos $dpl/sysroot
mount --move $dpl /upos
mount ${LOOPDEV}p1 /upos/boot
mount ${LOOPDEV}p1 /upos/sysroot/boot

mount --bind /dev/ /upos/dev
mount --bind /sys /upos/sys
mount --bind /proc /upos/proc

## apparently we use i386 grub
grub_modules=/upos/usr/lib/grub/i386-pc/
grub-install -d $grub_modules ${LOOPDEV} --root-directory=/upos
ln -sr /upos/boot/{grub,grub2}
loader=$(ls -t /upos/boot/ | grep -E "loader\.[0-9]$" | head -1)
chroot /upos grub-mkconfig -o /boot/${loader}/grub.cfg
cd /upos/boot/grub && ln -s ../loader/grub.cfg grub.cfg && cd -

## then generate the delta and archive it
ostree --repo=/upos/ostree/repo static-delta generate trunk --inline --min-fallback-size 0 --filename=${h}/${rev} | grep -vE "^\.\/"
cd ${h}
tar cf delta.tar $rev
rm $rev
cd -
ostree --repo=/upos/ostree/repo static-delta generate trunk --empty --inline --min-fallback-size 0 --filename=${h}/${rev} | grep -vE "^\.\/"
cd ${h}
tar cf delta_base.tar $rev
rm $rev

## prune older commits after delta have been generated
ostree prune --repo=/upos/ostree/repo --refs-only --keep-younger-than="1 seconds ago"

## wrap up image
sync
loop_name=$(basename ${LOOPDEV})
while $(mountpoint -q /upos || cat /proc/mounts | grep ${loop_name}); do
	findmnt /upos -Rrno TARGET | sort -r | xargs -I {} umount {} &>/dev/null
	cat /proc/mounts | grep ${loop_name} | sort -r | cut -d ' ' -f 2 | xargs -I {} umount {} &>/dev/null
	sleep 1
done
# don't repair if boot is ext2
# xfs_repair /dev/loop${lon}p1
xfs_repair ${LOOPDEV}p3
losetup -d ${LOOPDEV} &>/dev/null
mv imgtmp/image.pine ./

## checksum and compress
sha256sum image.pine >image.pine.sum
tar czf image.pine.tgz image.pine image.pine.sum
echo $new_csum >pine.sum
