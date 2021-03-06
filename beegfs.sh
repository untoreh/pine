#!/bin/sh

if [ ! -d /host -o $(cat /etc/os-release | grep alpine) ]; then
    echo "probably not in a ubuntu container..."
    exit 1
fi
mkdir -p work && cd work

## get beegfs packages
apt update -y -q && apt install wget -y -q
wget -q http://www.beegfs.com/release/latest-stable/gpg/DEB-GPG-KEY-beegfs -O- | apt-key add -
wget -qP /etc/apt/sources.list.d http://www.beegfs.com/release/latest-stable/dists/beegfs-deb8.list
apt update -y -q && apt install -y -q beegfs-client

## get kernel packages names
FLAVOR="virthardened"
REPO="http://dl-cdn.alpinelinux.org/alpine/v3.6/main/x86_64/"
PKGS=$(wget $REPO -qO- | grep -oE "\"linux-${FLAVOR}.*.apk\"" | sed 's/"//g')
IMG_PKG=$(echo "$PKGS" | grep -v dev | head -1)
DEV_PKG=$(echo "$PKGS" | grep dev | head -1)

## download packages
mkdir -p /pkgs && cd /pkgs
wget -q ${REPO}/$IMG_PKG ${REPO}/$DEV_PKG
tar xf $IMG_PKG 2>/dev/null
tar xf $DEV_PKG 2>/dev/null

## use kernel.release instead of generating from pkg name
## KVER=$(echo "$IMG_PKG" | sed -r 's/linux-virtgrsec-([^-]*)-r([0-9]+).*/\1-\2-virtgrsec/')
KVER=$(cat usr/share/kernel/${FLAVOR}/kernel.release)

## specify kernel version in makefile and arch
sed 's#$(shell uname -r)#'"$KVER"'#g' -i /opt/beegfs/src/client/*/build/Makefile
sed 's#$(shell uname -r)#'"$KVER"'#g' -i /opt/beegfs/src/client/*/source/Makefile
sed -r 's/^(buildArgs.*)/\1 ARCH=x86_64/' -i /etc/beegfs/beegfs-client-autobuild.conf

## move kernel files over standard paths
mv lib/modules/* /lib/modules/
mv usr/src/* /usr/src/

## make scripts
apt install libelf-dev gcc-5-plugin-dev -y -q
cd /usr/src/linux-headers-${KVER}/
make scripts 2>/dev/null ## ignore failed sortexec needing 
make tools/objtool
cd -
## build client
/etc/init.d/beegfs-client rebuild

## copy module over /host
cp -a /lib/modules/4.4.59-0-virtgrsec/updates/fs/beegfs_autobuild/* /host
