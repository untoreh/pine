#!/bin/sh
. ./functions.sh

## ostree workaround
ln -s /usr/sbin/grub-mkconfig /usr/sbin/grub2-mkconfig

apk --update-cache upgrade

apk add \
	bash \
	wget \
	curl \
	git \
	patch \
	unzip \
	xz \
	coreutils \
	blkid \
	binutils \
	findutils \
	multipath-tools \
	ca-certificates \
	util-linux \
	sfdisk \
	ostree \
	grub-bios \
	xfsprogs \
	e2fsprogs \
	squashfs-tools \
	go musl-dev make linux-headers

. ./functions.sh
. ./glib.sh

git config --global --add safe.directory /srv
