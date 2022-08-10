# ensures some things are setup
config_env(){
    set +e
    check_vars os_name
    ## confirm we made a new tree
    if [ ! "$(find ${os_name}_tree/* -maxdepth 0 | wc -l)" -gt 0 ]; then
	      echo "${FUNCNAME[0]}: newer tree not grown. (tree folder is empty)"
	      exit 1
    fi
    cp -a ./dist/cfg/repositories /etc/apk/repositories || {
        echo "${FUNCNAME[0]} not in main repo directory"
        exit 1
    }
    install_tools ostree util-linux wget
    h=$PWD
    repodir="/srv"
    image_dir="imgtmp"
    mkdir -p $image_dir
    set -e
}

clear_sysroot(){
    check_vars sysroot
    rm -rf $sysroot &>/dev/null
    mkdir -p $sysroot
}

## check that vars are set
## $@ vars names
check_vars(){
    [ -z "$*" ] && return
    local is_set=0
    for v in $@; do
        eval "d=\$$v"
        [ -z "$d" ] && {
            echo "${FUNCNAME[1]:-main}: $v ${message:-not set}"
            is_set=1
        }
    done
    return $is_set
}

## create filesystems on root and boot partitions
make_fs(){
    check_vars LOOPDEV boot_part root_part swap_part
    [ ! -e layout.cfg ] && {
        echo "${FUNCNAME[0]}: layout.cfg not found"
        exit 1
    }
    sfdisk $LOOPDEV < layout.cfg
    mkfs.ext2 -L /boot -I 1024 $boot_part
    mkfs.xfs -f -L /sysroot -d agsize=16m -i size=1024 $root_part
    mkswap -L swap $swap_part
}

# mount root and boot partitions
mount_parts(){
    check_vars sysroot root_part boot_part
    printc "mounting $boot_part and $root_part"
    mkdir -p $sysroot
    if blkid -t TYPE=xfs $root_part; then
        nouuid="-o nouuid"
    else
        nouuid=
    fi
    printc "command $nouuid $root_part $sysroot"
    mount $nouuid $root_part $sysroot
    mkdir -p $sysroot/boot
    if blkid -t TYPE=xfs $boot_part; then
        nouuid="-o nouuid"
    else
        nouuid=
    fi
    printc "command $nouuid $boot_part $sysroot/boot"
    mount $nouuid $boot_part $sysroot/boot
}

# fake the deployment to install grub using OSTree deployment files
fake_deploy(){
    check_vars sysroot os_name boot_part
    printc "setting up fake deploy"
    # get the REV number of the REF scraping the deployment link farm checkout
    printc "listing deployments paths..."
    find $sysroot/ostree/deploy/$os_name/deploy/ -maxdepth 1
    dpl=$(find $sysroot/ostree/deploy/$os_name/deploy/ -maxdepth 1 | grep -E "\.[0-9]$")
    check_vars dpl || \
        {
        echo "${FUNCNAME[0]}: no deployment to fake"
        exit 1
    }
    mount --bind $dpl $dpl
    mount --bind $sysroot $dpl/sysroot
    mount --move $dpl $sysroot
    mount $boot_part $sysroot/boot
    mount $boot_part $sysroot/sysroot/boot
    mount --bind /dev/ $sysroot/dev
    mount --bind /sys  $sysroot/sys
    mount --bind /proc $sysroot/proc
}

# install grub on boot partition
# $1 update
install_grub(){
    local update=$1
    check_vars sysroot boot_part
    printc "installing grub on $sysroot"
    # install the grub modules
    if [ -n "$update" ]; then
        check_vars LOOPDEV
        ## apparently we use i386 grub
        grub_modules=$sysroot/usr/lib/grub/i386-pc/
        grub-install -d $grub_modules ${LOOPDEV} --root-directory=$sysroot
    else
        grub-install $boot_part --root-directory=$sysroot
    fi
    # a fix for missing links
    ln -sr $sysroot/boot/{grub,grub2}
    # use the OSTree grub scripts to generate the boot config
    loader=$(ls -t $sysroot/boot/ | grep -E "loader\.[0-9]$" | head -1)
    chroot $sysroot grub-mkconfig -o /boot/${loader}/grub.cfg
    # the OSTree script doesn't touch the main grub config path, so have to link it
    cd $sysroot/boot/grub && ln -s ../loader/grub.cfg grub.cfg && cd -
}

# remove loop device
# $1 device
# $2 sysroot
unmount_sysroot() {
    set +e
    sync
    local LOOPDEV=$1
    local sysroot=$2
    [ -z "$1" -o -z "$2" ] && {
        echo "${FUNCNAME[0]}: provide loop device and sysroot"
        exit 1
    }
    printc "unmounting sysroot $sysroot"
    loop_name=$(basename ${LOOPDEV})
    while $(mountpoint -q $sysroot || cat /proc/mounts | grep ${loop_name}); do
	      findmnt $sysroot -Rrno TARGET | sort -r | xargs -I {} umount {} &>/dev/null
	      cat /proc/mounts | grep ${loop_name} | sort -r | cut -d ' ' -f 2 | xargs -I {} umount {} &>/dev/null
	      sleep 1
    done
    set -e
}

ostree_rm_deploys(){
    check_vars sysroot
    printc "clearing ostree deployments"
    local ref_deploy=ostree
    deployments=$(ostree --repo=$sysroot/ostree/repo refs $ref_deploy)
    if [ $(wc -l <<< "$deployments") -gt 1 ]; then
        for d in $deployments; do
            ostree --sysroot=$sysroot admin undeploy ${d/*\/}
        done
        ostree admin cleanup --sysroot=$sysroot
    fi
}

ostree_no_minspace(){
    check_vars sysroot
    printc "setting ostree min space"
    ostree config --repo=$sysroot/ostree/repo \
           set core.min-free-space-percent 0
}

# commit a tree
# $1 tree path
ostree_commit(){
    local tree=$1
    check_vars tree sysroot ref_name os_name ref_name
    printc "committing to ostree repo"
    local date=$(date +%Y-%m-%d)
    rev_number=$(ostree --repo=$sysroot/ostree/repo commit \
                        --skip-if-unchanged -s "$date" \
                        -b $ref_name \
                        --tree=dir=$tree)
    if [ "$?" != 0 ]; then
        local ostree_repo="$(dirname $tree)/${os_name}"
        rev_number=$(ostree --repo=$ostree_repo commit \
                            --skip-if-unchanged -s "$date" \
                            -b $ref_name \
                            --tree=dir=$tree)
    fi
}

ostree_fsck(){
    check_vars sysroot
    printc "checking ostree repo consistency"
    ostree fsck --repo=$sysroot/ostree/repo || \
        { err "${FUNCNAME[0]}: ostree repo check failed"; exit 1; }
    sync
}

ostree_prune(){
    check_vars sysroot
    printc "pruning ostree"
    local keep=${1:-"1 day ago"}
    ostree prune --repo=$sysroot/ostree/repo \
           --refs-only --keep-younger-than=$keep
}

ostree_deploy(){
    check_vars sysroot os_name ref_name root_part
    ## remove boot files to avoid failing the upgrade (because it triggers ostree grub
    ## hooks which doesn't work in the build environment
    rm -rf $sysroot/boot/*
    ostree admin deploy --sysroot=$sysroot --os=$os_name $ref_name \
	         --karg=root=UUID=$(blkid -s UUID -o value $root_part) \
	         --karg=rootfstype=xfs \
	         --karg=rootflags=rw,noatime,nodiratime,largeio,inode64
}

# creata a delta archive
# $1 delta name
# $2 empty flag
gen_delta(){
    check_vars ref_name sysroot
    local delta_name=$1
    [ -n "$2" ] && local empty="--empty"
    [ -z "$sysroot" ] || \
        [ -z "$ref_name" ] && {
            echo "gen_delta: empty vars."
            return 1
        }
    ostree --repo=$sysroot/ostree/repo static-delta \
           generate $ref_name $empty \
           --inline --min-fallback-size 0 \
           --filename=$delta_name | grep -vE "^\.\/"
}
# archive delta
# $1 work dir
# $2 archive name
# $3 delta name
arc_delta(){
    local workdir=$1
    local arc_name=$2
    local delta_name=$3
    cd $workdir
    [ ! -e $delta_name ] && {
        echo "file $delta_name not found in $workdir"
        return 1
    }
    tar cf $arc_name $delta_name
    printc "saved delta at $arg_name (cwd: $PWD)"
    rm $delta_name
    cd -
}

# checksum and archive image
# $1 image_name
csum_arc_image(){
    local image_name=$1
    local target_dir=$2
    local archive_path="${target_dir}/${image_name}.tgz"
    printc "archiving image $image_name"
    check_vars image_name target_dir
    sha256sum $image_name > ${image_name}.sum
    tar cvzf $archive_path ${image_name} ${image_name}.sum
    local archive_abs=$(realpath $archive_path)
    local archive_bytes=$(stat -c "%s" $archive_abs 2>/dev/null)
    local archive_size=$(numfmt --to=iec-i --suffix=B --format="%.3f" $archive_bytes 2>/dev/null)
    printc "archive saved at $archive_abs, with size $archive_size."
}

# maybe fix xfs partitions
# $@ partitions
repair_xfs(){
    for p in $@; do
        if blkid -t TYPE=xfs $p; then
            xfs_repair $p
        fi
    done
}
# match a remote checksum against the ostree repo checksum
# $1 remote file
compare_pine_csums() {
    check_vars sysroot ref_name repo
    printc "comparing checksums"
    rem_file=$1
    [ -z "$repo" ] || [ -z "$sysroot" ] || [ -z "$ref_name" ] && \
        {
            echo "\$repo or \$sysroot  or \$ref_name not set"
            return 1
        }
    # the last version is the one being built
    csum_V=$(last_release ${repo:-untoreh/pine} offset 2)
    old_csum=$(fetch_artifact ${repo}:$csum_V $rem_file -)
    [ -z "$old_csum" ] && err old_csum empty
    new_csum=$(ostree --repo=$sysroot/ostree/repo ls $ref_name -Cd | awk '{print $5}')
    [ -z "$new_csum" ] && err new_csum empty
    printc "comparing checksums $old_csum $new_csum..."
    if [ "$new_csum" = "$old_csum" ]; then
        printc "already up to update."
        touch file.up
        exit
    fi
    printc "csums different."
}
