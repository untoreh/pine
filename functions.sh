#!/bin/bash

shopt -s expand_aliases &>/dev/null
[ ${GIT_TOKEN:-} ] && gh_token="?access_token=${GIT_TOKEN}"
cn="\033[1;32;40m"
cf="\033[0m"
printc() {
    echo -e "${cn}${@}${cf}"
}
printdb() {
    [ -n "$PRINT_DEBUG" ] && echo -e "${cn}${@}${cf}"
}
err() {
    echo $@ 1>&2
}
rse()
{
    ((eval $(for phrase in "$@"; do echo -n "'$phrase' "; done)) 3>&1 1>&2 2>&3 | sed -e "s/^\(.*\)$/$(echo -en \\033)[31;1m\1$(echo -en \\033)[0m/") 3>&1 1>&2 2>&3
}

git_versions() {
    local remote tags
    if [ "$2" = c ]; then
        remote="$1"
    else
        remote="git://github.com/$1.git"
    fi
    tags=$(git ls-remote -t "$remote")
    tags=$(echo "$tags" | awk '{print $2}')
    tags=$(echo "$tags" | cut -d '/' -f 3)
    tags=$(echo "$tags" | grep -v "\-rc")
    tags=$(echo "$tags" | cut -d '^' -f 1)
    echo "$tags" | sed 's/^v//'
}

pine_version() {
    git_versions untoreh/pine | sort -bt- -k1nr -k2nr | head -1
}

last_version() {
    git_versions $1 | sort -bt. -k1nr -k2nr -k3r -k4r -k5r | head -1
}

last_version_g(){
    git_versions $1 | grep "[0-9]" | sort -Vr | head -1
}

## $1 repo $2 type
last_release() {
    if [ -n "$2" ]; then
        latest=
        release_type="$2"
    else
        latest="/latest"
    fi
    wget -qO- https://api.github.com/repos/${1}/releases$latest \
        | awk '/tag_name/ { print $2 }' | grep "$release_type" | head -1 | sed -r 's/",?//g'
}

## $1 repo $2 tag name
tag_id() {
    [ -n "$2" ] && tag_name="tags/${2}" || tag_name=latest
    wget -qO- https://api.github.com/repos/${1}/releases/${tag_name} | grep '"id"' | head -1 | grep -o "[0-9]*"
}
## $1 repo $2 old tag $3 new tag
switch_release_tag(){
    tid=$(tag_id ${1} ${2})
    new_tid=$(tag_id ${1} ${3})
    curl -X DELETE -u $GIT_USER:$GIT_TOKEN https://api.github.com/repos/${1}/releases/${new_tid}
    ## also specify master otherwise tag sha is not updated despite it being master anyway
    curl -X PATCH -u $GIT_USER:$GIT_TOKEN \
    -d '{"tag_name": "'${3}'", "name": "'${3}'", "target_commitish": "master"}' \
    https://api.github.com/repos/${1}/releases/${tid}
}

## $1 repo $2 currentTag(YY.MM-X)
next_release() {
    if [ -n "$2" ]; then
        cur_tag="$2"
    else
        return
    fi
    cur_D=$(echo $cur_tag | cut -d- -f1)
    ## get this month tags
    near_tags=$(git ls-remote -t https://github.com/${1} --match "$cur_D*" | awk '{print $2}' \
        | cut -d '/' -f 3 | cut -d '^' -f 1 | sed 's/^v//' | sort -bt- -k2n)
    ## loop until we find a valid release
    while
        cur_tag=$(echo "$near_tags" | awk '/'$cur_tag'/{getline; print $0}')
        echo "looking for releases tagged $cur_tag" 1>&2
        next_release=$(wget -qO- https://api.github.com/repos/${1}/releases/tags/${cur_tag}${gh_token})
        [ -z "$next_release" -a -n "$cur_tag" ]
    do :
    done
    echo $cur_tag
}

## get a valid next tag for the current git repo format: YY.MM-X
md() {
    giturl=$(git remote show origin | grep -i fetch | awk '{print $3}')
    [ -z "$(echo $giturl | grep github)" ] && echo "'md' tagging method currently works only with github repos, terminating." && exit 1
    prevV=$(git ls-remote -t $giturl | awk '{print $2}' | cut -d '/' -f 3 | grep -v "\-rc" | cut -d '^' -f 1 | sed 's/^v//')
    if [ -n "$tag_prefix" ]; then
        prevV=$(echo "$prevV" | grep $tag_prefix | sed 's/'$tag_prefix'-//' | sort -bt- -k1nr -k2nr | head -1)
    else
        echo "no \$tag_prefix specified, using to prefix." 1>&2
        prevV=$(echo "$prevV" | sort -bt- -k1nr -k2nr | head -1)
    fi
    ## prev date
    prevD=$(echo $prevV | cut -d- -f1)
    ## prev build number
    prevN=$(echo $prevV | cut -d- -f2)
    ## gen new release number
    newD=$(date +%y.%m)
    if [[ $prevD == $newD ]]; then
        newN=$((prevN + 1))
    else
        newN=0
    fi
    newV=$newD-$newN
    echo "$newV"
}

## $1 repo
## $2 tag
last_release_date() {
    if [ -n "$2" ]; then
        tag="tags/$2"
    else
        tag="latest"
    fi
    local date=$(wget -qO- https://api.github.com/repos/${1}/releases/${tag} | grep created_at | head -n 1 | cut -d '"' -f 4)
    [ -z "$date" ] && echo 0 && return
    date -d "$date" +%Y%m%d%H%M%S
}

## $1 release date
## $2 time span eg "7 days ago"
release_older_than() {
    if [ $(echo -n $1 | wc -c) != 14 -a "$1" != 0 ]; then
        err  "wrong date to compare"
    fi
    release_d=$1
    span_d=$(date --date="$2" +%Y%m%d%H%M%S)
    if [ $span_d -ge $release_d ]; then
        return 0
    else
        return 1
    fi
}

## get mostly local vars
diff_env(){
    bash -cl 'set -o posix && set >/tmp/clean.env'
    set -o posix && set >/tmp/local.env && set +o posix
    diff /tmp/clean.env \
        /tmp/local.env | \
        grep -E "^>|^\+" | \
        grep -Ev "^(>|\+|\+\+) ?(BASH|COLUMNS|LINES|HIST|PPID|SHLVL|PS(1|2)|SHELL|FUNC)" | \
        sed -r 's/^> ?|^\+ ?//'
}

## $1 repo:tag
## $2 artifact name
## $3 dest dir
## $4 extra wget options
fetch_artifact() {
    if [ "${1:0:4}" = "http" ]; then
        art_url="$1"
        artf=$(basename $art_url)
        dest="$2"
        shift 2
    else
        local repo_fetch=${1/:*} repo_tag=${1/*:} draft= opts=
        [ -z "$repo_tag" -o "$repo_tag" = "$1" ] && repo_tag=releases/latest || repo_tag=releases/tags/${repo_tag}
        [ "$repo_tag" = "releases/tags/last" ] && repo_tag=releases
        [ "$repo_tag" = "releases/tags/draft" ] && repo_tag=releases/$gh_token && draft=true
        artf="$2"
        if [ -n "$draft" ]; then
            local data=
            while [ -z "$data" ]; do
                data=$(wget -qO- https://api.github.com/repos/${repo_fetch}/${repo_tag})
                sleep 3
            done
            art_url=$(echo "$data" | grep "${artf}" -B 3 | grep '"url"' | head -n 1 | cut -d '"' -f 4)${gh_token}
            trap "unset -f wget" SIGINT SIGTERM SIGKILL SIGHUP RETURN EXIT
            wget(){ /usr/bin/wget --header "Accept: application/octet-stream" $@; }
        else
            local data=
            while [ -z "$data" ]; do
                data=$(wget -qO- https://api.github.com/repos/${repo_fetch}/${repo_tag})
                sleep 3
            done
            art_url=$(echo "$data"| grep browser_download_url | grep ${artf} | head -n 1 | cut -d '"' -f 4)
        fi
        dest="$3"
        shift 3
    fi
    echo "$art_url" | grep "://" || { err "no url found for ${artf} at ${repo_fetch}:${repo_tag}"; return 1; }
    ## if no destination dir stream to stdo
    case "$dest" in
        "-")
        wget $@ $art_url -qO-
        ;;
        "-q")
        return 0
        ;;
        *)
        mkdir -p $dest
        if echo "$artf" | grep -E "(gz|tgz|xz|7z)$"; then
            wget $@ $opts $art_url -qO- | tar xzf - -C $dest
        else
            if echo "$artf" | grep -E "zip$"; then
                wget $@ $hader $art_url -qO artifact.zip && unzip artifact.zip -d $dest
                rm artifact.zip
            else
                if echo "$artf" | grep -E "bz2$"; then
                    wget $@ $opts $art_url -qO- | tar xjf - -C $dest
                else
                    wget $@ $opts $art_url -qO- | tar xf - -C $dest
                fi
            fi
        fi
    esac
}

## $@ files/folders
export_stage(){
    [ -z "$pkg" -o -z "$STAGE" ] && err "pkg or STAGE undefined, terminating" && exit 1
    which hub &>/dev/null || get_hub
    diff_env >stage.env
    tar czf ${pkg}_stage_${STAGE}.tgz stage.env $@

    hub release edit -d -a ${pkg}_stage_${STAGE}.tgz -m "${pkg}_stage" ${pkg}_stage || \
    hub release create -d -a ${pkg}_stage_${STAGE}.tgz -m "${pkg}_stage" ${pkg}_stage
}

## $1 repo 
import_stage(){
    [ -z "$pkg" -o -z "$STAGE" -o -z "$1" ] && err "pkg, STAGE, or repo undefined, terminating" && exit 1
    PREV_STAGE=$((STAGE - 1))
    fetch_artifact ${1}:draft ${pkg}_stage_${PREV_STAGE}.tgz $PWD
    . ./stage.env || cat stage.env | tail +2 > stage1.env && . ./stage1.env
}

## $1 repo
check_skip_stage(){
    [ -n "$PKG" ] && pkg=$PKG
    [ -z "$pkg" -o -z "$STAGE" -o -z "$1" ] && err "pkg, STAGE, or repo undefined, terminating" && exit 1
    fetch_artifact ${1}:draft ${pkg}_stage_$STAGE.tgz -q && return 0 || return 1
}

## $1 repo
cleanup_stage(){
    [ -z "$pkg" ] && pkg=$PKG
    [ -z "$pkg" ] && err "pkg undefined, terminating" && exit 1
    which github-release &>/dev/null || get_ghr
    local u=${1/\/*} r=${1/*\/}
    err "cleaning up drafts..."
    github-release delete -u $u -r $r -t ${pkg}_stage
}
## $1 image file path
## $2 mount target
## mount image, ${lon} populated with loop device number
mount_image() {
    umount -Rfd $2 2>/dev/null
    rm -rf $2 && mkdir $2
    lon=0
    while [ -z "$(losetup -P /dev/loop${lon} $(realpath ${1}) 2>/dev/null && echo true)" ]; do
        lon=$((lon + 1))
        [ $lon -gt 10 ] && (err "failed mounting image $1" && return 1)
        sleep 1
    done
    ldev=/dev/loop${lon}
    tgt=$(realpath $2)
    mkdir -p $tgt
    for p in $(find /dev/loop${lon}p*); do
        mp=$(echo "$p" | sed 's~'$ldev'~~')
        mkdir -p $tgt/$mp
        mount -o nouuid $p $tgt/$mp 2>/dev/null
    done
}

## $1 overdir
## $2 lowerdir
mount_over(){
    local pkg=$1 lodir=$2
    [ -z "$pkg" ] && return 1
    [ -z "$lodir" ] && lodir="${pkg}-lo"
    mkdir -p ${pkg} $lodir ${pkg}-wo ${pkg}-up
    mount -t overlay \
        -o lowerdir=$lodir,workdir=${pkg}-wo,upperdir=${pkg}-up \
        none ${pkg} || ( err "overlay failed for $pkg" && exit 1 )
}

## $1 rootfs
mount_hw() {
    rootfs=$1
    mkdir -p $rootfs
    cd $rootfs
    mkdir -p dev proc sys
    mount --bind /dev dev
    mount --bind /proc proc
    mount --bind /sys sys
    cd -
}

## $1 rootfs
umount_hw() {
    rootfs=$1
    cd $rootfs || return 1
    umount dev
    umount proc
    umount sys
    cd -
}

## $@ apk args
## install alpine packages
apkc() {
    initdb=""
    root_path=$(realpath ${1})
    apkrepos=${root_path}/etc/apk
    shift
    mkdir -p ${apkrepos}
    if [ ! -f "${apkrepos}/repositories" ]; then
        cp /etc/apk/repositories ${apkrepos}
        initdb="--initdb --no-cache"
    fi
    /usr/sbin/apk --arch x86_64 --allow-untrusted --root ${root_path} $initdb $@
}

## $1 ref
## routine pre-modification actions for ostree checkouts
prepare_rootfs() {
    rm -rf ${1}
    mkdir ${1}
    cd $1
    mkdir -p var var/cache/apk usr/lib usr/bin usr/sbin usr/etc
    mkdir -p etc lib lib64 bin sbin
    cd -
}

## $1 $pkg
copy_image_cfg() {
    local pkg=$1
    if [ ! -d "${pkg}" ]; then
        err "package root not found, terminating."
        exit 1
    fi
    cp $PWD/templates/${pkg}/{image.conf,image.env} ${pkg}/
}

# download latest pine image or last image
# $1 repo
# $2 dest
fetch_pine() {
    check_vars repo
    repo=$1
    dest=$2
    fetch_artifact ${repo} image.pine.tgz $dest
    if [ ! -f $dest/image.pine -o "$?" != 0 ]; then
        printc "no latest image found, trying last image available."
        ## try the last if there is no latest
        lasV=$(last_release ${repo})
        fetch_artifact ${repo}:${lasV} image.pine.tgz $dest
        if [ ! -f $dest/image.pine -o "$?" != 0 ]; then
	          err "failed downloading previous image, terminating."
	          exit 1
        fi
    fi
}

# mount a image on a loop device
# $1 : image path
loop_image() {
    losetup -D "$1"
    find /dev/loop*p* -exec rm {} \; 2>/dev/null
    lon=0
    while
        losetup -P /dev/loop$lon $PWD/image.pine
        echo $?
        sleep 1
        ## https://github.com/moby/moby/issues/27886#issuecomment-417074845
        LOOPDEV=$(losetup --find --show --partscan "${PWD}/image.pine" 2>/dev/null)
        [ -n "$LOOPDEV" ] && break
        parts=$(find /dev/loop*p*)
        [ -n "$parts" ] && break
        losetup -D "${PWD}/image.pine"
	      lon=$((lon + 1)); do :
    done

    # drop the first line, as this is our LOOPDEV itself, but we only what the child partitions
    parts=$(find /dev/loop*p* 2>/dev/null)
    if [ -z "$parts" ]; then
        PARTITIONS=$(lsblk --raw --output "MAJ:MIN" --noheadings ${LOOPDEV} | tail -n +2)
        COUNTER=1
        for i in $PARTITIONS; do
            MAJ=$(echo $i | cut -d: -f1)
            MIN=$(echo $i | cut -d: -f2)
            if [ ! -e "${LOOPDEV}p${COUNTER}" ]; then mknod ${LOOPDEV}p${COUNTER} b $MAJ $MIN; fi
            COUNTER=$((COUNTER + 1))
        done
    fi
    echo $LOOPDEV
}

## $1 ref
## $2 skip links
## routing after-modification actions for ostree checkouts
wrap_rootfs() {
    [ -z "$1" ] && (
        err "no target directory provided to wrap_rootfs"
        exit 1
    )
    cd ${1}
    if [ "$2" != "-s" ]; then
        for l in usr/etc,etc usr/lib,lib usr/lib,lib64 usr/bin,bin usr/sbin,sbin; do
            IFS=','
            set -- $l
            cp -a --remove-destination ${2}/* ${1} &>/dev/null
            rm -rf $2
            ln -sr $1 $2
            unset IFS
        done
    fi
    rm -rf var/cache/apk/*
    umount -Rf dev proc sys run &>/dev/null
    rm -rf dev proc sys run
    mkdir dev proc sys run
    cd -
}

## mounts the base tree for the pkg
base_tree(){
    if [ -z "$pkg" ]; then
        err "variables not defined."
        exit 1
    fi
    repo_path=$(./fetch-alp-tree.sh | tail -1)
    repo_local="${PWD}/lrepo"
    rm -rf ${pkg}
    ostree checkout --repo=${repo_path} --union ${ref} ${pkg}-lo
    mount_over $pkg
    mount_hw $pkg
    ln -sr ${pkg}/usr/etc ${pkg}/etc
    mkdir -p ${pkg}/var/cache/apk
    alias crc="chroot $pkg"
}

## create tar archives for bare and ovz from the raw files tree
package_tree(){
    if [ -z "$pkg" -o \
        -z "$repo_local" -o \
        -z "$rem_repo" ]; then
        err "variables not defined."
        exit 1
    fi
    mount_over $repo_local $repo_path
    ## commit tree to app branch
    rev=$(ostree --repo=${repo_local} commit -s "$(date)-${pkg}-build" \
        --skip-if-unchanged --link-checkout-speedup -b ${pkg} ${pkg})

    ## get the last app checksum from remote
    old_csum=$(fetch_artifact ${rem_repo}:${pkg} ${pkg}.sum -)
    ## get checksum of committed branch
    new_csum=$(ostree --repo=${repo_local} ls ${pkg} -Cd | awk '{print $5}')
    ## end if unchanged
    compare_csums

    ## create delta of app branch
    ostree --repo=${repo_local} static-delta generate --from=${ref} ${pkg} \
        --inline --min-fallback-size 0 --filename=${rev}

    ## checksum and compress
    echo $new_csum >${pkg}.sum
    tar cvf ${pkg}.tar ${rev}

    ## -- ovz --
    repo_local=$(./fetch-alp_ovz-tree.sh | tail -1)
    ## commit tree to app branch
    rev=$(ostree --repo=${repo_local} commit -s "$(date)-${pkg}-build" \
        --skip-if-unchanged --link-checkout-speedup -b ${pkg} ${pkg})
    ## skip csum comparison, if bare image is different so is ovz
    ## create delta of app branch
    ostree --repo=${repo_local} static-delta generate --from=${ref} ${pkg} \
        --inline --min-fallback-size 0 --filename=${rev}

    ## compress
    tar cvf ${pkg}_ovz.tar ${rev}
}

## $@ packages to install
install_tools() {
    setup=false
    tools="$@"
    for t in $tools; do
        if [ -z "$(apk info -e $t)" ]; then
            setup=true
            toinst="$toinst $t"
        fi
    done
    $setup && apk add --no-cache $toinst
}

## $1 path to search
## return the name of the first file named with 64numchars
b64name() {
    echo $(basename $(find $1 | grep -E [a-z0-9]{64}))
}

# ensures some things are setup
config_env(){
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
    image_path="imgtmp"
    mkdir -p $image_path
}

clear_sysroot(){
    check_vars sysroot
    rm -rf $sysroot &>/dev/null
    mkdir -p $sysroot
}

## check that vars are set
## $@ vars names
check_vars(){
    [ -z "$@" ] && return
    for v in $@; do
        eval "d=\$$v"
        [ -z "$d" ] && echo "${FUNCNAME[1]:-main}: $v ${message:-not set}"
        return 1
    done
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
    mkdir -p $sysroot
    if blkid -t TYPE=xfs $root_part; then
        nouuid="-o nouuid"
    else
        nouuid=
    fi
    mount $nouuid $root_part $sysroot
    mkdir -p $sysroot/boot
    if blkid -t TYPE=xfs $boot_part; then
        nouuid="-o nouuid"
    else
        nouuid=
    fi
    mount $nouuid $boot_part $sysroot/boot
}

# fake the deployment to install grub using OSTree deployment files
fake_deploy(){
    check_vars sysroot os_name boot_part
    # get the REV number of the REF scraping the deployment link farm checkout
    dpl=$(find $sysroot/ostree/deploy/$os_name/deploy/ -maxdepth 1 | grep "\.0$")
    check_vars dpl || \
        {
        echo "${FUNCNAME[0]}: no deployment to fake"
        return 1
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
    check_vars sysroot LOOPDEV boot_part
    # install the grub modules
    if [ -n "$update" ]; then
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
    sync
    local LOOPDEV=$1
    local sysroot=$2
    [ -z "$1" -o -z "$2" ] && {
        echo "${FUNCNAME[0]}: provide loop device and sysroot"
        exit 1
    }
    loop_name=$(basename ${LOOPDEV})
    while $(mountpoint -q $sysroot || cat /proc/mounts | grep ${loop_name}); do
	      findmnt $sysroot -Rrno TARGET | sort -r | xargs -I {} umount {} &>/dev/null
	      cat /proc/mounts | grep ${loop_name} | sort -r | cut -d ' ' -f 2 | xargs -I {} umount {} &>/dev/null
	      sleep 1
    done
}

ostree_rm_deploys(){
    check_vars sysroot
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
    ostree config --repo=$sysroot/ostree/repo \
           set core.min-free-space-percent 0
}

# commit a tree
# $1 tree path
ostree_commit(){
    local tree=$1
    check_vars tree sysroot ref_name os_name ref_name
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
    ostree fsck --repo=$sysroot/ostree/repo || \
        { err "${FUNCNAME[0]}: ostree repo check failed"; exit 1; }
    sync
}

ostree_prune(){
    check_vars sysroot
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
    rm $delta_name
    cd -
}

# checksum and archive image
# $1 image_name
csum_arc_image(){
    local image_name=$1
    check_vars image_name
    sha256sum $image_name > ${image_name}.sum
    tar cvzf ${image_name}.tgz ${image_name} ${image_name}.sum
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
    rem_file=$1
    [ -z "$repo" ] || [ -z "$sysroot" ] || [ -z "$ref_name" ] && \
        {
            echo "\$repo or \$sysroot  or \$ref_name not set"
            return 1
        }
    old_csum=$(fetch_artifact ${repo} $rem_file -)
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

## fetch github hub bin
get_hub() {
    mkdir -p /opt/bin
    fetch_artifact github/hub:v2.3.0-pre9 "linux-amd64.*.tgz" $PWD
    mv $(find -name hub -print -quit) /opt/bin
    export GITHUB_TOKEN=$GIT_TOKEN PATH=/opt/bin:$PATH
}

## fetch github-release
get_ghr() {
    mkdir -p /opt/bin
    fetch_artifact aktau/github-release ".*linux-amd64.*.bz2" $PWD
    mv $(find -name github-release -print -quit 2>/dev/null) /opt/bin
    export GITHUB_TOKEN=$GIT_TOKEN PATH=/opt/bin:$PATH
}

install_glib() {
    mount -o remount,ro /proc &>/dev/null
    ## GLIB
    GLIB_VERSION=$(last_version sgerrand/alpine-pkg-glibc)
    wget -q -O $1/etc/apk/keys/sgerrand.rsa.pub https://raw.githubusercontent.com/sgerrand/alpine-pkg-glibc/master/sgerrand.rsa.pub
    wget -q https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$GLIB_VERSION/glibc-$GLIB_VERSION.apk
    if [ -n "$1" ]; then
        apk --root $1 add glibc-$GLIB_VERSION.apk
    else
        apk add glibc-$GLIB_VERSION.apk
    fi
    rm glibc-$GLIB_VERSION.apk
    mount -o remount,rw /proc &>/dev/null
}

usr_bind_rw() {
    if ! (cat /proc/mounts | grep -qE "\s/usr\s.*\s,?rw,?"); then
        os=$(ostree admin status | awk '/\*/{print $2}')
        dpl=$(ostree admin status | awk '/\*/{print $3}')
        mount -o bind,rw /ostree/deploy/${os}/deploy/${dpl}/usr /usr
    fi
}

usr_unlock() {
    reqsize=$(du -s /usr/ | awk '{print $1}')
    avltmp=$(df /tmp/ | awk 'NR != 1 {print $4}')
    if [ "$reqsize" -lt "$avltmp" ]; then
        tmpdir=/tmp
    else
        tmpdir=/var/tmp
    fi
    cp -a /usr "$tmpdir/.usr"
    mount --bind "$tmpdir/.usr" /usr
}

usr_lock() {
    touch /usr/.ro || { echo "it appears /usr is already locked."; exit 1; }
    umount /usr || { echo "couldn't unmount the temp bind mount"; exit 1; }
    rm -rf /tmp/.usr /var/tmp/.usr
}

## routing to add packages over existing tree
## checkout the trunk using hardlinks
#rm -rf ${ref}
#ostree checkout --repo=${repo_local} --union -H ${ref} ${ref}
### mount ro
#modprobe -q fuse
### overlay over the checkout to narrow pkg files
#rm -rf work ${pkg} over
#mkdir -p work ${pkg} over
#prepare_checkout ${ref}
#mount -t overlay -o lowerdir=${ref},workdir=work,upperdir=${pkg} none over
#apkc over add ${pkg}
### copy new files over read-only base checkout
#cp -an ${pkg}/* ${ref}-ro/
#fusermount -u ${ref}-ro/

