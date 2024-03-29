#!/bin/bash

rm -f make_ovz_success
set -e

. ./functions.sh
name=pine_ovz
ref=trunk
dist_dir=../dist

## get release tag
# newV=`wget -qO- https://api.github.com/repos/untoreh/pine/releases/latest | \
#  awk '/tag_name/ { print $2 }' | head -1 | sed -r 's/",?//g'`
## newV=`pine_version` ## this does not account for gh releases same as "git tag"
## local tag checks
newV=`git tag --sort=committerdate | tail -1`

printc "$newV is the new version"

## tree init
mkdir -p /srv/${name}_tree
cd /srv/${name}_tree

while `mountpoint -q ./proc`; do
    umount proc
done
while `mountpoint -q ./dev`; do
    umount dev
done
while `mountpoint -q ./sys`; do
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
cat << 'EOF' >etc/init.d/vardirs
#!/sbin/openrc-run

description="Create targets for ostree deployments"

depend()
{
        need localmount
}

start() {
        ebegin "Setting dirs"
        mkdir -m 0755 -p /var/cache/rc /var/cache/apk /var/tmp /var/mnt /var/opt /var/srv /var/roothome /sysroot/ostree /sysroot/tmp
        ln -srnf /sysroot/home /var/home &>/dev/null
        eend $?
}

stop() {
        return
}
EOF
chmod +x etc/init.d/vardirs

cat << 'EOF' >etc/init.d/ostree-booted
#!/sbin/openrc-run

description="Mount ostree booted flag"

depend()
{
        need bootmisc
}

start() {
        ebegin "creating flag"
        touch /run/ostree-booted
        chmod 640 /run/ostree-booted
        mount -o bind,private,ro /run/ostree-booted /run/ostree-booted
        eend $?
}

stop() {
        return
}
EOF
chmod +x etc/init.d/ostree-booted

mkdir -p etc/local.d
cat << EOF >etc/local.d/00-devs.start
rm /dev/console
rm /dev/full
rm /dev/null
rm /dev/zero
rm /dev/ptmx
rm /dev/tty
rm /dev/random
rm /dev/urandom

mknod -m 622 /dev/console c 5 1
mknod -m 666 /dev/full c 1 7
mknod -m 666 /dev/null c 1 3
mknod -m 666 /dev/zero c 1 5
mknod -m 666 /dev/ptmx c 5 2
mknod -m 666 /dev/tty c 5 0
mknod -m 444 /dev/random c 1 8
mknod -m 444 /dev/urandom c 1 9
chown -v root:tty /dev/{console,ptmx,tty}
EOF

cat << 'EOF' >etc/init.d/knobs
#!/sbin/openrc-run

description="Knobs customizations"

depend()
{
        need vardirs
}

start() {
        ebegin "Applying tweaks"

        ## misc
        knobs="madvise,/sys/kernel/mm/transparent_hugepage/enabled
madvise,/sys/kernel/mm/transparent_hugepage/defrag"

        for i in $knobs; do
                BIFS=$IFS; IFS=','
                set -- $i
                val=$1
                path=$2
                echo $val | tee $path &>/dev/null
                IFS=$BIFS
        done

        ## disks
        knobs="256,/queue/nr_requests
0,/queue/rotational
0,/queue/add_random
deadline,/queue/scheduler
4,/queue/iosched/writes_starved
8,/queue/iosched/fifo_batch
200,/queue/iosched/read_expire
4000,/queue/iosched/write_expire
4096,/queue/read_ahead_kb
4096,/queue/max_sectors_kb"

        BIFS=$IFS
        IFS=$'\n'
        eindent
        for b in `find /sys/block/ | grep -E "/vd.*|/sd.*"` ; do
                for i in $knobs; do
                        BIFS=$IFS; IFS=','
                        set -- $i
                        val=$1
                        path=$2
                        path=${b}${2}
                        eindent
                        if [ -f $path ] ; then
                                if ! $(echo $val > $path 2>/dev/null) ; then
                                        ewarn "${2} can't be applied"
                                fi
                        else
                                ewarn "${2} not available"
                        fi
                        eoutdent
                        IFS=$BIFS
                done
        done
        IFS=$BIFS

        ## net
        for i in `ifconfig | grep -Eo "^enp[0-9]*s[0-9]*|^eth[0-9]*"` ; do
                inff=$(ethtool -K $i tx on rx on tso on gro on lro on 2>&1)
                for l in $inff ; do
                        einfo "$l"
                done
                $(ip link set $i mtu 1500)
        done
        eoutdent
        eend $?
}

stop() {
        return
}
EOF
chmod +x etc/init.d/knobs

## mount-ro env var
mkdir -p etc/conf.d
echo "RC_NO_UMOUNTS=/usr" >etc/conf.d/mount-ro

## fstab
cat << EOF >etc/fstab
proc                        /proc     proc    defaults               0  0
none                        /dev/pts  devpts  rw,gid=5,mode=620      0  0
none                        /dev/shm  tmpfs   defaults               0  0
tmpfs                       /tmp      tmpfs   defaults,nosuid,nodev  0  0
/ostree/deploy/${name}/var  /var      none    bind                   0  0
/sysroot/boot               /boot     none    bind                   0  0
EOF

## repositories
mkdir -p etc/apk
cat /etc/apk/repositories >etc/apk/repositories

## nameservers
cat << EOF >etc/resolv.conf
nameserver 8.8.8.8
nameserver 2001:4860:4860:0:0:0:0:8888
EOF

## net
mkdir -p etc/network
cat << EOF >etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    pre-up ip link set eth0 up
    hostname pine
EOF

## tunings
mkdir -p etc/sysctl.d
cat << EOF >etc/sysctl.d/02-tweaks.conf
## ovz specific (some are not allowed anyway like swappiness)
vm.swappiness=100
vm.vfs_cache_pressure=0
vm.min_free_kbytes=0
vm.dirty_background_ratio=66
vm.dirty_ratio=99

## mem
vm.overcommit_memory=1
vm.overcommit_ratio=100
kernel.pid_max=4194303
fs.file-max=6544018
fs.nr_open=6544018

## disk
fs.suid_dumpable=0

## net
net.core.rmem_max=1677721600
net.core.rmem_default=167772160
net.core.wmem_max=1677721600
net.core.wmem_default=167772160
net.core.netdev_max_backlog=65536
net.core.somaxconn=16384
net.core.optmem_max=2048000

net.ipv4.tcp_mem=1024000 8738000 1677721600
net.ipv4.tcp_rmem=1024000 8738000 1677721600
net.ipv4.tcp_wmem=1024000 8738000 1677721600
net.ipv4.udp_mem=1024000 8738000 1677721600

net.ipv4.tcp_congestion_control=htcp
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1
net.ipv4.tcp_fack=1

net.ipv4.tcp_timestamps=0
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_early_retrans=1
net.ipv4.tcp_app_win=40
net.ipv4.tcp_syncookies=1

net.ipv4.ip_local_port_range=1025 65535
net.ipv4.tcp_max_syn_backlog=65536
net.ipv4.tcp_synack_retries=3
net.ipv4.tcp_retries2=6
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=30
net.ipv4.tcp_keepalive_probes=4
net.ipv4.tcp_keepalive_intvl=20
net.ipv4.tcp_tw_reuse=1

kernel.msgmni=2878
kernel.msgmnb=65536
kernel.msgmax=65536
kernel.sem=256 32000 100 142
kernel.shmmni=4096
EOF
mkdir -p etc/security/limits.d
cat << EOF >etc/security/limits.d/files.conf
*     hard  nofile  917504
*     soft  nofile  917504
root  hard  nofile  917504
root  soft  nofile  917504
EOF
cat << EOF >etc/security/limits.d/core.conf
*     hard  core    0
root  hard  core    0
EOF

## sudo
mkdir -p etc/sudoers.d
cat << EOF >etc/sudoers.d/pine
pine ALL=(ALL) NOPASSWD: ALL
EOF

mount --bind /sys sys
mount --bind /proc proc
mount --bind /dev dev

apkc() {
    apk --arch x86_64 --allow-untrusted --root $PWD $@
}


apkc add --initdb --update-cache alpine-base sudo tzdata  \
 binutils coreutils procps util-linux \
 ca-certificates wget ethtool iptables  \
 ostree git  \
 htop iftop bash sysstat tmux mosh-server \
 dropbear-ssh dropbear-scp openssh-sftp-server \



## SETUP
chpwd() {
    chroot $PWD $@
}

hostname=pine
{
    chpwd echo "root:rootppp" | chpwd chpasswd
    chpwd adduser pine -D
    chpwd echo "pine:pineppp" | chpwd chpasswd
    echo '' >etc/motd
    chpwd setup-hostname $hostname
    chpwd setup-timezone -z CET
    chpwd setup-sshd -c dropbear
} || true

## SERVICES
for r in `cat ../runlevels_ovz.sh`; do
    mkdir -p `dirname $r`
    ln -srf etc/init.d/`basename $r` `echo "$r" | sed 's#^/##'`
done

## UPDATES/REBOOTS
cp ${dist_dir}/scripts/system-upgrade_ovz etc/periodic/daily/system-upgrade
chmod +x etc/periodic/daily/system-upgrade

## GLIB
printc "installing glib..."
. ../glib.sh $PWD
printc "installing extras ovz..."
. ../extras_ovz.sh
printc "installing extras common..."
. ../extras_common.sh

## FIXES
sed -r 's/(\ssysctl\s.*-p.*)/\1 >\/dev\/null/' -i etc/init.d/sysctl ## sysctl shutup on ovz
sed 's/$retval/0/' -i etc/init.d/sysctl ## sysctl shutup on ovz
rm -rf lib/rc/cache
ln -s /var/cache/rc lib/rc/cache
touch boot/vmlinuz-0000000000000000000000000000000000000000000000000000000000000000
sed -r 's/^(tty|1|2)/#tty/' -i etc/inittab ## no ttys inside containers

## CLEANUP
while `mountpoint -q ./proc`; do
    umount proc
done
while `mountpoint -q ./dev`; do
    umount dev
done
while `mountpoint -q ./sys`; do
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

## WORKAROUNDS
## coreutils support for bin -> usr/bin
cd bin
ls -l | grep \/coreutils | awk '{print $9}' | xargs -I{} ln -sf coreutils {}
cd -

## OSTREE
cd /srv
ostree --repo=${name} commit -s $(date)'-build' -b ${ref} --tree=dir=${name}_tree
ostree summary -u --repo=${name}
ostree --repo=${name} ls ${ref} -Cd | awk '{print $5}' > ${name}.sum
#pgrep -f trivial-httpd &>/dev/null || ostree trivial-httpd -P 39767 /srv/pine -d
touch make_ovz_success
