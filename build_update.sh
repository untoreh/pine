#!/bin/bash
. ./functions.sh
. ./build_common.sh

[ ! -e make_success ] && { err "make script failed aborting"; exit 1; }
set -e

repo=untoreh/pine
os_name=pine
config_env

# download image
cd $image_dir
fetch_pine "${repo}" "$image_dir"

# mount on loop device
LOOPDEV=$(loop_image "${image_dir}/image.pine")

ref_deploy=ostree
ref_name=trunk
boot_part=${LOOPDEV}p1
root_part=${LOOPDEV}p3
sysroot=/upos

mount_parts

## delete deployments before commit
ostree_rm_deploys

## now commit the new tree to the old repo
## the image has to have enough space for commits...
ostree_no_minspace
ostree_commit "${h}/${os_name}_tree"

## compare checksums
ostree_fsck
compare_pine_csums /pine.sum

## then generate the delta and archive it
## NOTE: deltas have to be generated before mangling with deployments as it has
## to fetch the correct refs
gen_delta "${h}/${rev_number}"
arc_delta $h delta.tar $rev_number
gen_delta "${h}/${rev_number}" empty
arc_delta $h delta_base.tar $rev_number

## redeploy
ostree_deploy

## recreate boot files
fake_deploy

install_grub update

## wrap up
ostree_prune
unmount_sysroot $LOOPDEV $sysroot
repair_xfs $boot_part $root_part
losetup -d ${LOOPDEV} &>/dev/null
mv $image_dir/image.pine ./

## checksum and compress
csum_arc_image image.pine ${image_dir}/../../
echo $new_csum >pine.sum
