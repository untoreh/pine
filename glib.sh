#!/bin/sh

mount -o remount,ro /proc &>/dev/null
## GLIB
GLIB_VERSION=$(last_version sgerrand/alpine-pkg-glibc)
wget -q -O $1/etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
wget -q https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$GLIB_VERSION/glibc-$GLIB_VERSION.apk
wget -q https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$GLIB_VERSION/glibc-bin-$GLIB_VERSION.apk
if [ -n "$1" ] ; then
	apk --root $1 add --force-non-repository glibc-$GLIB_VERSION.apk glibc-bin-$GLIB_VERSION.apk
else
	apk add --force-non-repository glibc-$GLIB_VERSION.apk glibc-bin-$GLIB_VERSION.apk
fi
rm glibc-$GLIB_VERSION.apk glibc-bin-$GLIB_VERSION.apk
mount -o remount,rw /proc &>/dev/null
