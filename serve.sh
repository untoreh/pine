#!/bin/sh

cat <<EOF > /etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/latest-stable/main
http://dl-cdn.alpinelinux.org/alpine/latest-stable/community
http://dl-cdn.alpinelinux.org/alpine/edge/community
http://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF

tools="ostree util-linux wget caddy"
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

mkdir -p imgtmp
cd imgtmp
if [ ! -f image.pine ] ; then
	wget -qO- $img_url | tar xz -O | dd of=$PWD/image.pine
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
mkdir -p /srv/repo
ostree --repo=/srv/repo init --mode=archive-z2

## parse the bare repo into the tz2 repo
ostree --repo=/srv/repo pull-local loroot/ostree/repo trunk

## start the server
ulimit -n 65535
caddy -root /srv/repo -port 30303
