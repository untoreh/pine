#!/bin/sh

export alpV="v3.15"

case "$1" in
    -a)
        export DEVICE=`find /dev 2>/dev/null -maxdepth 1 |  \
 grep -E "/vd.*|/sd.*|/hd.*" |  \
 sort | head -n1` ;;
    '')
        echo "-a uses the first device found, or specify a device path.
Network config is copied over if found, or it is generated from the current
session, or it is possble to use environment variables to specify
network configuration, example:
INTERFACE=eth0
ADDRESS=192.168.1.100
NETMASK=255.255.255.0
GATEWAY=192.168.1.1"
        exit ;;
    *)
        export DEVICE=$1 ;;
esac

if [ -z "$NODE" ] ; then
    echo "specify node ID (16bit number, eg NODE=1)"
    exit 1
fi

modprobe loop xfs || { echo "kernel modules unavailable (ensure xfs version is recent enough)"; exit 1; }

## mount tmpfs
mkdir -p pivot && mount -t tmpfs -o exec,size=768M tmpfs pivot
cd pivot

type apk && apk add --no-cache openssl libressl ca-certificates
type apt && { apt update ; apt install openssl ca-certificates -yq; }
if type systemctl; then
    systemctl stop systemd-timesyncd.service
    systemctl stop systemd-logind.service
    systemctl stop dbus.service
    systemctl stop snapd.service
    systemctl stop polkitd.service
    systemctl stop lvm2-lvmetad.service
    systemctl stop mdadm.service
    systemctl stop atd.service
    systemctl stop acpid.service
    systemctl stop cron.service
    systemctl stop iscsid.service
    systemctl stop systemd-user-sessions.service
    systemctl stop user@0.service
    systemctl stop accounts-daemon.service
    systemctl stop lxcfs.service
    systemctl stop vmware-tools.service
    systemctl stop systemd-journald.service
    systemctl stop systemd-udevd.service
    systemctl stop rsyslog.service
fi
type yum && yum install ca-certificates wget losetup

## get busybox for rebooting (not needed when we create a chroot to customize the system)
/usr/bin/wget https://github.com/untoreh/pine/raw/master/utils/busybox -O busybox
if type sha256sum; then
    if [ "$(sha256sum  busybox | cut -d ' '  -f 1)" -neq \
        "adc719974134562effee93f714a10acb7738803879c6c0ba8cb41d4b6453971e" ]; then
        echo "busybox did not match checksum "
        exit 1
    fi
elif type md5sum; then

    if [ "$(md5sum  busybox | cut -d ' '  -f 1)" -neq \
        "194f00b06f94fd3ece9a3a22268af2d3" ]; then
        { echo "busybox did not match checksum "; exit 1; }
    fi
else
    echo "WARNING: Couldn't verify busybox checksum. (sha256sum or md5sum not found)"
fi
chmod +x busybox
[ ! -e busybox -o ! -x busybox ] && exit 1
mkdir bbin
cp -a busybox bbin/
$PWD/bbin/busybox --install -s $PWD/bbin
export PATH=$PWD/bbin:$PATH WORK=$PWD

## generate /etc/network-environment
IPv6=$(ip -6 addr | awk 'tolower($0) ~ /global/{gsub(/\/64/, ""); print $2; exit}')
IPv4=$(ip -4 -o add | awk 'match($0, /(enp[0-9]*s[0-9]*)|(eth[0-9]*)|(ens[0-9]*)/){gsub(/\/[0-9]{1,2}/,"",$4);print $4; exit}')
echo "NODE=$NODE" > ./network-environment
[ -n "$IPv4" ] && echo "IPv4=$IPv4" >> ./network-environment
[ -n "$IPv6" ] && echo "IPv6=$IPv6" >> ./network-environment

## give chroot capabilities
if type sysctl; then
    sysctl -w  \
    kernel.grsecurity.chroot_deny_fchdir=0  \
    kernel.grsecurity.chroot_deny_shmat=0  \
    kernel.grsecurity.chroot_deny_sysctl=0  \
    kernel.grsecurity.chroot_deny_unix=0  \
    kernel.grsecurity.chroot_enforce_chdir=0  \
    kernel.grsecurity.chroot_findtask=0  \
    kernel.grsecurity.chroot_caps=0  \
    kernel.grsecurity.chroot_deny_chmod=0  \
    kernel.grsecurity.chroot_deny_chroot=0  \
    kernel.grsecurity.chroot_deny_mknod=0  \
    kernel.grsecurity.chroot_deny_mount=0  \
    kernel.grsecurity.chroot_deny_pivot=0  \
    kernel.grsecurity.chroot_restrict_nice=0 &>/dev/null
fi

## copy network interfaces
if [ "$(cat /etc/network/interfaces | grep -v lo | grep inet | wc -l)" -gt 0 ]; then
    cp /etc/network/interfaces ./
fi

## setup alp-base to get tools to mount the image to customize it before flashing
mkdir -p proc sys dev tmp run mnt etc
apkt=`/usr/bin/wget --no-check-certificate -cT 3 https://dl-cdn.alpinelinux.org/alpine/${alpV}/main/x86_64/ -qO- |  \
 /bin/grep -oE '"apk-tools-static.*.apk"' | sed 's/"//g'`
/usr/bin/wget --no-check-certificate -cT 3 "https://dl-cdn.alpinelinux.org/alpine/${alpV}/main/x86_64/$apkt" || exit 1
sync
tar xzf $apkt
ln -s sbin/apk.static sbin/apk
sbin/apk.static -X http://dl-cdn.alpinelinux.org/alpine/${alpV}/main -U  \
 --allow-untrusted --root ./ --initdb add alpine-base xfsprogs util-linux wget  \
 ca-certificates coreutils
cp /etc/resolv.conf etc/

## tree must be binded and not moved to allow the kernel to update partition tables
mount --bind /dev dev
mount --bind /sys sys
mount --bind /proc proc
cat << 'CEOF' >customize.sh
#!/bin/sh
## pass device name
DEVICE=$1
. ./network-environment

## get image url
img_url=`/usr/bin/wget -qO- https://api.github.com/repos/untoreh/pine/releases/latest | /bin/grep browser_download_url | grep image.pine | head -n 1 | cut -d '"' -f 4`
## get the last if the latest is not available somehow
if [ -z "$img_url" ]; then
   img_url=`/usr/bin/wget -qO- https://api.github.com/repos/untoreh/pine/releases | /bin/grep browser_download_url | grep image.pine | head -n 1 | cut -d '"' -f 4`
fi
echo $img_url

## direct piping allows for fast flashing on low ram but can't verify checksum and
## setup networking devices and drives
#/usr/bin/wget -qO- $img_url | tar xzf -O image.pine | dd of=$DEVICE bs=512 conv=fsync

## download and extract the image
/usr/bin/wget -q $img_url -O- | tar xz image.pine -O | dd if=/dev/stdin of=$DEVICE bs=4M conv=fsync
## verify checksum (included with the image archive)
## mount the image on loop device
## wait for partitions to be created

## mount the partition of interest (3)
lon=0
while ! /sbin/losetup -P /dev/loop${lon} $DEVICE; do
    lon=$((lon+1))
    sleep 1
done
sync
mkdir rootfs
mount -t xfs -o nouuid /dev/loop${lon}p3 rootfs/ || exit 1

dpl=`ls -dt rootfs/ostree/deploy/pine/deploy/* | grep -E "\.[0-9]$" | head -1`
## setup network
if [ -f "./interfaces" -a -z "$IFACE" ]; then
    awk '!seen[$0]++' ./interfaces > interfaces.cleaned
    mv interfaces.cleaned ${dpl}/etc/network/interfaces
else
    if [ -z "$IFACE" ]; then
        IFACE=$(ip -4 add | grep -Eo "enp[0-9]*s[0-9]*|eth[0-9]*|ens[0-9]*" | head -1)
        [ -z "$IFACE" ] && exit 1
        ADDRESS=$(ip -4 addr | grep $IFACE | grep inet | sed -r 's~.*inet\s*([^ ]*).*~\1~' | head -1)
        NETMASK=$(busybox ipcalc $ADDRESS -m | cut -d= -f2) ## used from the busybox applet
        GATEWAY=$(ip -4 route | grep $IFACE | head -1 | sed -r 's/(default (via|dev) )?([^\s ]*) .*/\3/')
    fi

    cat << EOF >${dpl}/etc/network/interfaces
auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
    address $ADDRESS
    netmask $NETMASK
    gateway $GATEWAY
    hostname pine
EOF
fi
## setup network environment
mv ./network-environment ${dpl}/etc/network-environment
echo -e "set -a\n. /etc/network-environment\nset +a" > ${dpl}/etc/profile.d/network-environment.sh
## add node engine label to docker daemon
if [ -f ${dpl}/etc/conf.d/docker ]; then
    sed -r 's~(DOCKER_OPTS=".*)"~\1 --label NODE='$NODE' "~' -i ${dpl}/etc/conf.d/docker
fi

## fix drive names and add new partitions
## if using default partitions ("/var" and "/share") replace the /var mount (5) while
## the "/share" device is mounted by the sharing service (docker or the chosen DFS)
sed -r 's#(/dev/)bd([0-9]*)#\1'$(basename $DEVICE)'\2#' -i ${dpl}/etc/fstab
# PARTS=1G,128M,128M,128M,
# DP_F=true
if [ -z "$PARTS" ] ; then
    export PARTS=5G,128M,128M, DP_F=true
    ## note the number 5, the partition number, extended is 4, var is 5
    var_line="${DEVICE}5    /var    xfs rw,noatime,nodiratime,largeio,inode64,logdev=${DEVICE}6,logbufs=8,logbsize=256k 0   0"
    sed -r 's~/ostree.*/var.*/var.*~'"${var_line}"'~' -i ${dpl}/etc/fstab
    ## tabulate fstab
    cat ${dpl}/etc/fstab | sed -r 's/\s+/ /g' | column -t -s' ' >tmpfstab
    mv tmpfstab ${dpl}/etc/fstab
fi

## unmount the image and flash
umount rootfs/
sync
# xfs_repair /dev/loop${lon}p1 || exit
xfs_repair /dev/loop${lon}p3 || exit

sync
/sbin/losetup -D
sync

## setup additional partitions, (4) is extended partition so it is skipped
## init extended partition
part_str='n\ne\n\n\n'
## add logical partitions
IFS=,
for p in ${PARTS} ; do
    part_str="${part_str}n\n\n+${p}\n"
done
unset IFS
## append last partition
if [ -n "$DP_F" ] ; then
    part_str="${part_str}n\n\n\n"
fi
## write statement
part_str="${part_str}w\n"
## execute fdisk
/bin/echo -e "$part_str" | fdisk "$DEVICE" || exit
sleep 1
sync
## loop the target device to make sure partition tables are updated
lon=0
while ! losetup -P /dev/loop${lon} $DEVICE; do
    lon=$((lon+1))
    sleep 1
done
## LODEV is the loop device prefix to which the partition number will be appended
LODEV=/dev/loop${lon}p
## add extra partitions
if [ "$DP_F" ] ; then
    mkfs.xfs -f -L /var -d agsize=16m -l logdev=${LODEV}6 -i size=512 ${LODEV}5
    mkfs.xfs -f -L /share -d agsize=16m -l logdev=${LODEV}7 -i size=512 ${LODEV}8
fi
## copy content of os var folder over the partition created, if using defaults
## otherwise `ostree admin unlock` does not work ("mkdirat: no such file or directory")
mkdir -p varostree
mkdir -p varpart
mount -o nouuid ${LODEV}3 varostree
mount -o nouuid,logdev=${LODEV}6 ${LODEV}5 varpart
cp -a varostree/ostree/deploy/pine/var/* varpart/
umount varpart varostree
## detach loop devices
/sbin/losetup -D
# exit
## reboot
sync
echo -n "rebooting in 3..."; sleep 1; echo -n "2..."; sleep 1; echo "1..."; sleep 1;
reboot -f
CEOF
chmod +x customize.sh

chroot . /bin/sh -x customize.sh $DEVICE
