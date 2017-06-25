#!/bin/sh

repo_squashfs="https://github.com/plougher/squashfs-tools"
patch_1="https://raw.githubusercontent.com/alpinelinux/aports/8b7e48dcaf6a2049edeffaa957db618e923b78ab/main/squashfs-tools/CVE-2015-4645.patch"
patch_2="https://raw.githubusercontent.com/alpinelinux/aports/8b7e48dcaf6a2049edeffaa957db618e923b78ab/main/squashfs-tools/vla-overlow.patch"

rm -rf squashfs-tools
git clone $repo_squashfs 
cd squashfs-tools

## patches
wget $patch_1
git apply $(basename $patch_1)
wget $patch_2
git apply $(basename $patch_2)
## deps (additional to prepare pkgs)
apk add zlib-dev

cd squashfs-tools
make && make install