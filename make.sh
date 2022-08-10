#!/bin/bash

. ./functions.sh
name=pine
ref=trunk
dist_dir=../dist

## get release tag
# newV=`wget -qO- https://api.github.com/repos/untoreh/pine/releases/latest | \
#  awk '/tag_name/ { print $2 }' | head -1 | sed -r 's/",?//g'`
## newV=`pine_version` ## this does not account for gh releases same as "git tag"
# make sure tags are available
git fetch --depth=100 --tags
## local tag checks
newV=$(git tag --sort=committerdate | tail -1)

printc "$newV is the new version"

## tree init
mkdir -p /srv/${name}_tree
cd /srv/${name}_tree

while $(mountpoint -q ./proc); do
	umount proc
done
while $(mountpoint -q ./dev); do
	umount dev
done
while $(mountpoint -q ./sys); do
	umount sys
done

rm -rf ./*

mkdir -p dev sys proc run boot var/home var/mnt var/opt var/srv var/roothome sysroot/ostree sysroot/tmp usr/bin usr/sbin usr/lib usr/lib64 usr/etc

## links
ln -s usr/etc etc
ln -s var/home home
ln -s var/roothome root
ln -s var/mnt mnt
ln -s var/opt opt
ln -s var/srv srv
ln -s sysroot/ostree ostree
ln -s sysroot/tmp tmp

## save the new version number
echo -n "$newV" >etc/pine
# chmod 644 etc/pine ## ? readonly does not seem to work

mkdir -p etc/init.d

cp -a ${dist_dir}/scripts/init.d/vardirs etc/init.d/vardirs
chmod +x etc/init.d/vardirs

cp -a ${dist_dir}/scripts/init.d/knobs etc/init.d/knobs
chmod +x etc/init.d/knobs

cp -a ${dist_dir}/scripts/init.d/ostree-booted etc/init.d/ostree-booted
chmod +x etc/init.d/ostree-booted

# zram
cp -a ${dist_dir}/scripts/init.d/zram etc/init.d/zram
cp -a ${dist_dir}/scripts/zram etc/zram
chmod +x etc/init.d/zram etc/zram

## mount-ro env var
mkdir -p etc/conf.d
echo "RC_NO_UMOUNTS=/usr" >etc/conf.d/mount-ro

## fstab
cp -a ${dist_dir}/cfg/fstab etc/fstab

## repositories
mkdir -p etc/apk
cat /etc/apk/repositories >etc/apk/repositories

## nameservers
cp -a ${dist_dir}/cfg/resolv.conf etc/resolv.conf

## net
mkdir -p etc/network
cp -a ${dist_dir}/cfg/interfaces etc/network/interfaces

## tunings
mkdir -p etc/sysctl.d
cp -a ${dist_dir}/cfg/02-tweaks.conf etc/sysctl.d/02-tweaks.conf

mkdir -p etc/security/limits.d
cp -a ${dist_dir}/cfg/limits/files.conf etc/security/limits.d/files.conf
cp -a ${dist_dir}/cfg/limits/core.conf etc/security/limits.d/core.conf

## sudo
mkdir -p etc/sudoers.d
cp -a ${dist_dir}/cfg/sudoers etc/sudoers.d/pine

# mount here as packages setup scripts might require mounts
mount --bind /sys sys
mount --bind /proc proc
mount --bind /dev dev

# packages
apkc() {
	apk --arch x86_64 --allow-untrusted --root $PWD $@
}

apkc add --initdb --update-cache alpine-base sudo tzdata \
	mkinitfs xfsprogs e2fsprogs grub-bios \
	util-linux binutils coreutils blkid multipath-tools \
	ca-certificates wget ethtool iptables \
	ostree git \
	htop iftop bash sysstat tmux mosh-server \
	dropbear-ssh dropbear-scp openssh-sftp-server

## fix for grub without syslinux
rm etc/grub.d/10_linux
## grub2 link for ostree compatibility
ln -sr usr/sbin/{grub-mkconfig,grub2-mkconfig}

# initial setup
chpwd() {
	chroot $PWD $@
}

hostname=pine
chpwd echo "root:rootppp" | chpwd chpasswd
chpwd adduser pine -D
chpwd echo "pine:pineppp" | chpwd chpasswd
echo '' >etc/motd
chpwd setup-hostname $hostname
chpwd setup-timezone -z CET
chpwd setup-sshd -c dropbear
chpwd setup-ntp -c busybox

## services
for r in $(cat ../runlevels.sh); do
	mkdir -p $(dirname $r)
	ln -srf etc/init.d/$(basename $r) $(echo "$r" | sed 's#^/##')
done

## updates/reboots
cp ${dist_dir}/scripts/system-upgrade etc/periodic/daily
chmod +x etc/periodic/daily/system-upgrade

## glib
. ../glib.sh $PWD
. ../extras.sh
. ../extras_common.sh

## boot
flavor="virt"
apkc add --no-scripts linux-$flavor || {
	err "couldn't install kernel"
	exit 1
}
patch usr/share/mkinitfs/initramfs-init ../initramfs-ostree.patch
chroot $PWD mkinitfs \
	-F "ata base cdrom ext2 ext3 ext4 xfs keymap kms mmc raid scsi usb virtio" \
	$(basename $(ls -d lib/modules/*))
mv boot tmpboot && mkdir boot
cp -a tmpboot/vmlinuz-$flavor boot/
cp -a tmpboot/initramfs-$flavor boot/
cksum=$(cat boot/vmlinuz-$flavor boot/initramfs-$flavor | sha256sum | cut -f 1 -d ' ')
mv boot/vmlinuz-$flavor boot/vmlinuz-$flavor-${cksum}
mv boot/initramfs-$flavor boot/initramfs-$flavor-${cksum}
rm tmpboot -rf

## kernel modules
KVER=$(cat usr/share/kernel/$flavor/kernel.release)
mkdir -p lib/modules/${KVER}/kernel/fs/beegfs
if [ -e ../beegfs.ko ]; then
	cp -a ../beegfs.ko lib/modules/${KVER}/kernel/fs/beegfs/
fi
chpwd depmod $KVER

# cleanup and fixes
rm -rf lib/rc/cache
ln -s /var/cache/rc lib/rc/cache

while $(mountpoint -q ./proc); do
	umount proc
done
while $(mountpoint -q ./dev); do
	umount dev
done
while $(mountpoint -q ./sys); do
	umount sys
done
rm dev var run etc -rf
mkdir -p dev var run usr/lib usr/bin usr/sbin
cp -a --remove-destination lib/* usr/lib
rm lib -rf && ln -s usr/lib lib
cp -a --remove-destination lib64/* usr/lib
rm lib64 -rf && ln -s usr/lib lib64
cp -a --remove-destination bin/* usr/bin
rm bin -rf && ln -s usr/bin bin
cp -a --remove-destination sbin/* usr/sbin
rm sbin -rf && ln -s usr/sbin sbin

# coreutils support for bin -> usr/bin
cd bin
ls -l | grep \/coreutils | awk '{print $9}' | xargs -I{} ln -sf coreutils {}
cd -

# commit the rootfs to ostree
cd /srv
ostree --repo=pine commit -s "$(date)-build" -b ${ref} --tree=dir="${name}_tree"
ostree summary -u --repo=pine
ostree --repo=pine ls ${ref} -Cd | awk '{print $5}' >pine.sum
## pgrep -f trivial-httpd &>/dev/null || ostree trivial-httpd -P 39767 /srv/pine -d
