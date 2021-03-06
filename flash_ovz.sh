#!/bin/sh

case "$1" in
    '-h|')
        echo "Network config is copied over if found, or it is generated from the current
session, or it is possble to use environment variables to specify
network configuration, example:
INTERFACE=eth0
ADDRESS=192.168.1.100
NETMASK=255.255.255.0
GATEWAY=192.168.1.1"
        exit
        ;;
    *)
        export DEVICE=$1
        ;;
esac

if [ -z "$NODE" ]; then
    echo "specify node ID (16bit number, eg NODE=1)"
    exit 1
fi

## vars
bburl=https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-x86_64
wget=/usr/bin/wget

## mount tmpfs
mkdir -p /flash && cd /flash

## get busybox for rebooting (not needed when we create a chroot to customize the system)
which apk && apk add --no-cache openssl ca-certificates
which apt && apt update && apt install -yq openssl ca-certificates
$wget --no-check-certificate $bburl -O busybox
chmod +x busybox
[ ! -e busybox -o ! -x busybox ] && exit 1
mkdir bin
$PWD/busybox --install -s $PWD/bin
export PATH=$PWD/bin:$PATH

## generate /etc/network-environment
IPv6=$(ip -6 addr | awk 'tolower($0) ~ /global/{gsub(/\/64/, ""); print $2; exit}')
IPv4=$(ip -4 -o add | awk 'match($0, /(enp[0-9]*s[0-9]*)|(eth[0-9]*)|(venet[0-9]*).*global/){gsub(/\/[0-9]{1,2}/,"",$4);print $4; exit}')
echo "NODE=$NODE" >./network-environment
[ -n "$IPv4" ] && echo "IPv4=$IPv4" >>./network-environment
[ -n "$IPv6" ] && echo "IPv6=$IPv6" >>./network-environment

## give chroot capabilities
sysctl -w \
    kernel.grsecurity.chroot_deny_fchdir=0 \
    kernel.grsecurity.chroot_deny_shmat=0 \
    kernel.grsecurity.chroot_deny_sysctl=0 \
    kernel.grsecurity.chroot_deny_unix=0 \
    kernel.grsecurity.chroot_enforce_chdir=0 \
    kernel.grsecurity.chroot_findtask=0 \
    kernel.grsecurity.chroot_caps=0 \
    kernel.grsecurity.chroot_deny_chmod=0 \
    kernel.grsecurity.chroot_deny_chroot=0 \
    kernel.grsecurity.chroot_deny_mknod=0 \
    kernel.grsecurity.chroot_deny_mount=0 \
    kernel.grsecurity.chroot_deny_pivot=0 \
    kernel.grsecurity.chroot_restrict_nice=0 &>/dev/null

## copy network interfaces
if [ "$(cat /etc/network/interfaces | grep -v lo | grep inet | wc -l)" -gt 0 ]; then
    cp /etc/network/interfaces ./
fi

rem_repo="untoreh/pine"
artifact="rootfs.pine_ovz.sq"

## get image url if not specified
if [ -z "$img_url" ]; then
    img_url=$($wget -qO- https://api.github.com/repos/${rem_repo}/releases/latest | grep browser_download_url | grep $artifact | head -n 1 | cut -d '"' -f 4)
fi
## fall back to last if the latest is not available somehow
if [ -z "$img_url" ]; then
    img_url=$($wget -qO- https://api.github.com/repos/${rem_repo}/releases | grep browser_download_url | grep $artifact | head -n 1 | cut -d '"' -f 4)
fi
echo $img_url
## get unsquashfs
echo "downloading $img_url"
$wget https://cdn.jsdelivr.net/gh/${rem_repo}/utils/unsquashfs -qO /usr/bin/unsquashfs
chmod +x /usr/bin/unsquashfs

## direct piping allows for fast flashing on low ram but can't verify checksum and
## setup networking devices and drives
#wget -qO- $img_url | tar xzf -O image.pine | dd of=$DEVICE bs=512 conv=notrunc,fsync

## download and extract the image to rootfs folder for customizations
pwd=$PWD
$wget $img_url -qO $artifact
## for lowmem
memsize=$(grep MemTotal <  /proc/meminfo | awk '{$1=$2/1024; print $1}')
if [ "$memsize" -lt 256 ]; then
    da="-da 16"
fi
unsquashfs $da -d $pwd/rootfs $artifact

dpl=$(ls -dt $pwd/rootfs/ostree/deploy/pine*/deploy/* | grep -E "\.[0-9]$" | head -1)
## setup network
if [ -f "./interfaces" -a -z "$IFACE" ]; then
    # awk '!seen[$0]++' ./interfaces >interfaces.cleaned
    # mv interfaces.cleaned ${dpl}/etc/network/interfaces
    mv interfaces ${dpl}/etc/network/interfaces
else
    if [ -z "$IFACE" ]; then
        IFACE=$(ip -4 add | grep -Eo "enp[0-9]*s[0-9]*|eth[0-9]*|venet[0-9]*" | head -1)
        ADDRESS=$(ip -4 addr | grep $IFACE | grep inet | grep global | sed -r 's~.*inet\s*([^ ]*).*~\1~' | head -1)
        NETMASK=$(ipcalc $ADDRESS -m | cut -d= -f2) ## used from the busybox applet
        GATEWAY=$(ip -4 route | grep $IFACE | head -1 | sed -r 's/(default (via|dev) )?([^\s ]*) .*/\3/')
    fi

    cat <<EOF >${dpl}/etc/network/interfaces
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
cat <<EOF >${dpl}/etc/profile.d/network-environment.sh
set -a
. /etc/network-environment
set +a
EOF
## overwrite the fs
umount /etc/hostname /etc/hosts /etc/resolv.conf &>/dev/null
for p in $(find /* -maxdepth 0 -type d | grep -vE "flash$|dev$|sys$|proc$|run$|tmp$|boot$"); do
    grep ${p} /proc/mounts | cut -f2 -d" " | sort -r | xargs -I{} umount {}
    rm -rf ${p}
done

mv -f $pwd/rootfs/* /
## make sure boot files are copied for since ostree reads deployments from them
mv -f $pwd/rootfs/boot/* /boot
dpl=$(ls -t /ostree/deploy/*/deploy | grep "\.0$" | head -1)
dpl_path=$(find /ostree/deploy/*/deploy/$dpl -maxdepth 0)

## busybox installation for init
mkdir -p /bin
cp ./busybox /bin/
/bin/busybox --install -s /bin
export PATH=/bin:$PATH

## pre init setup
rm -f /bin/init
cat <<'EOF' >/bin/init
#!/bin/busybox sh

## for serial console
mount -t devpts -o rw,gid=5,mode=620 none /dev/pts

/bin/busybox --install -s /bin ; PATH=/bin:/sbin:$PATH
dpl=$(ls -t /ostree/deploy/*/deploy | grep "\.[0-9]$" | head -1)
echo -n ostree= >/tmp/.cmdline
ostree=$(find /ostree/deploy/*/deploy/$dpl -maxdepth 0 | tee -a /tmp/.cmdline)

mount -o bind,private,rw $ostree $ostree
mount -o bind,private,rw / $ostree/sysroot
mount -o bind,private,ro $ostree/usr $ostree/usr
mount -o rbind,rshared /dev $ostree/dev
mount -o rbind,rshared /proc $ostree/proc
mount -o bind,private,ro /tmp/.cmdline $ostree/proc/cmdline
mount -o rbind,rshared /sys $ostree/sys
mount -t tmpfs -o rw cgroup_root $ostree/sys/fs/cgroup
sync

exec chroot $ostree /sbin/init ostree=$ostree
EOF
chmod +x /bin/init

## fixes for openvz7
cat <<'EOF' >/bin/bash
#!/bin/busybox sh

exec /bin/busybox sh $@
EOF
chmod +x /bin/bash
mkdir -p /etc/network
touch /etc/network/interfaces

## cleanup
cd /
rm -rf /flash

## reboot
sync
echo -n "rebooting in 3..."
sleep 1
echo -n "2..."
sleep 1
echo "1..."
sleep 1
reboot -f
