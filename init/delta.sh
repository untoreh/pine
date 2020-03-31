#!/bin/bash
. ./functions.sh
name=pine

## confirm we made a new tree
if [ ! "`find ${name}_tree/* -maxdepth 0 | wc -l`" -gt 0 ] ; then
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
    -t )
    trap cleanup SIGINT SIGTERM EXIT ;;
    -c )
    cleanup ; losetup -D ; exit ;;
    * ) ;;
esac


cat <<EOF > /etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/latest-stable/main
http://dl-cdn.alpinelinux.org/alpine/latest-stable/community
http://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF

tools="ostree util-linux wget"
setup=false
for t in $tools ; do
    if [ -z "`apk info -e $t`" ] ; then
        setup=true
    toinst="$toinst $t"
    fi
done
$setup && apk add --no-cache $toinst

img_url=`wget -qO- https://api.github.com/repos/untoreh/pine/releases | grep browser_download_url | grep image.pine | head -n 1 | cut -d '"' -f 4`
echo $img_url

h=$PWD
mkdir -p imgtmp
cd imgtmp
if [ ! -f image.pine ] ; then
    wget -qO- $img_url | tar xzf - image.pine
fi

lon=0
while [ -z "`losetup -P /dev/loop$lon $PWD/image.pine && echo true`" ] ; do
    lon=$((lon+1))
    sleep 1
done

## p3 is the root partition
mkdir -p loroot
mount -o nouuid /dev/loop${lon}p3 loroot

## init a tz2 repo
mkdir -p prepine
ostree --repo=prepine init --mode=archive-z2

## parse the bare repo into the tz2 repo
ostree --repo=prepine pull-local loroot/ostree/repo trunk

## now commit the new tree to the old repo
rev=$(ostree --repo=prepine commit -s $(date)'-build' -b trunk --tree=dir=${h}/${name}_tree)

## then generate the delta and archive it
ostree --repo=prepine static-delta generate trunk --inline --min-fallback-size 0 --filename=${h}/${rev}
cd ${h}
tar cf delta.tar $rev
