#!/bin/bash

shopt -s expand_aliases &>/dev/null
if [ -n "${GIT_TOKEN}" ]; then
    function wget() {
        /usr/bin/wget --header "Authorization: token ${GIT_TOKEN}" $@
    }
fi
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

check_vars(){
    [ -z "$*" ] && return
    local is_set=0 d
    for v in $@; do
        eval "d=\$$v"
        [ -z "$d" ] && {
            echo "$v ${message:-not set}"
            is_set=1
        }
    done
    return $is_set
}

git_versions() {
    local remote tags
    if [ "$2" = c ]; then
        remote="$1"
    else
        remote="https://github.com/$1.git"
    fi
    printc "fetching git version with ls-remote"
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
    git_versions "$1" |  sort -bt. -k1nr -k2nr -k3r -k4r -k5r | sort -bt'-' -k2n | grep -E '.*\.|\-.*'  | tail -n 1
}

last_version_g(){
    git_versions $1 | grep "[0-9]" | sort -Vr | head -1
}

## $1 repo $2 type
last_release() {
    set +e
    local repo="${1}"
    if [ -n "$2" ]; then
        local latest=
        if [ "$2" = offset ]; then
            local offset=$3
        else
            local release_type="$2"
        fi
    else
        local latest="/latest"
    fi
    wget -qO- https://api.github.com/repos/${repo}/releases$latest \
        | awk '/tag_name/ { print $2 }' | grep "$release_type" | head -${offset:-1} | tail -1 | sed -r 's/",?//g'
    set -e
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
    this_tag=false
    next_release=""
    for remote_tag in $near_tags; do
        echo "looking for releases tagged $remote_tag" 1>&2
        if [ $remote_tag = $cur_tag ]; then
            this_tag=true
            continue
        fi
        if [ $this_tag = true ]; then
            next_release=$(wget -qO- https://api.github.com/repos/${1}/releases/tags/${cur_tag})
        fi
        [ -n "$next_release" ] && break
    done
    echo $remote_tag
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
    trap "unset -f wget_partial fetch_releases_data" RETURN
    # downloading assets while providing a token gives bad requests
    function wget_partial(){ /usr/bin/wget $@; }
    if [ "${1:0:4}" = "http" ]; then
        art_url="$1"
        artf=$(basename $art_url)
        dest="$2"
        shift 2
    else
        local repo_fetch=${1/:*} repo_tag=${1/*:} draft= opts=
        [ -z "$repo_tag" -o "$repo_tag" = "$1" ] && repo_tag=releases/latest || repo_tag=releases/tags/${repo_tag}
        [ "$repo_tag" = "releases/tags/last" ] && repo_tag=releases
        [ "$repo_tag" = "releases/tags/draft" ] && repo_tag=releases && draft=true
        artf="$2"
        local data= tries=0
        while [ -z "$data" ]; do
            data=$(wget -qO- https://api.github.com/repos/${repo_fetch}/${repo_tag})
            tries=$((tries+1))
            [ $tries -gt 3 ] && { err "couldn't fetch releases data"; return 1; }
            sleep $tries
        done
        if [ -n "$draft" ]; then
            art_url=$(echo "$data" | grep "${artf}" -B 3 | grep '"url"' | head -n 1 | cut -d '"' -f 4)
            wget_partial(){ /usr/bin/wget --header "Accept: application/octet-stream" $@; }
        else
            art_url=$(echo "$data"| grep browser_download_url | grep ${artf} | head -n 1 | cut -d '"' -f 4)
        fi
        dest="$3"
        shift 3
    fi
    echo "$art_url" | grep "://" || { err "no url found for ${artf} at ${repo_fetch}:${repo_tag}"; return 1; }
    ## if no destination dir stream to stdo
    case "$dest" in
        "-")
        wget_partial $@ $art_url -qO-
        ;;
        "-q")
        return 0
        ;;
        *)
        mkdir -p $dest
        if echo "$artf" | grep -E "(gz|tgz|xz|7z)$"; then
            wget_partial $@ $opts $art_url -qO- | tar xzf - -C $dest
        else
            if echo "$artf" | grep -E "zip$"; then
                wget_partial $@ $hader $art_url -qO artifact.zip && unzip artifact.zip -d $dest
                rm artifact.zip
            else
                if echo "$artf" | grep -E "bz2$"; then
                    wget_partial $@ $opts $art_url -qO- | tar xjf - -C $dest
                else
                    wget_partial $@ $opts $art_url -qO- | tar xf - -C $dest
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
    shift
    apkrepos="${root_path}/etc/apk"
    apkreposfile="${apkrepos}/repositories"
    mkdir -p ${apkrepos}
    if [ ! -f $apkreposfile ]; then
        cp /etc/apk/repositories ${apkrepos}
        cat /etc/apk/edge-repositories >> ${apkreposfile}
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
        ## offset by 1 since the last tag is the one being build
        lasV=$(last_release ${repo} offset 2)
        if [ -z "$lasV" ]; then
            err "couldn't determine the last version for ${repo}"
            exit 1
        fi
        fetch_artifact ${repo}:${lasV} image.pine.tgz $dest
        if [ ! -f $dest/image.pine -o "$?" != 0 ]; then
	          err "failed downloading previous image, terminating."
	          exit 1
        fi
    fi
    printc "finished downloading image"
}

# mount a image on a loop device
# $1 : image path
loop_image() {
    local image_path=$1
    losetup -D "$image_path"
    find /dev/loop*p* -exec rm {} \; 2>/dev/null
    [ -e "$image_path" ] || {
        echo "${FUNCNAME[0]}: image not found"
        exit 1
    }
    lon=0
    while
        [ -e /dev/loop$lon ] || {
            echo "${FUNCNAME[0]}: exhausted loop devices"
            exit 1
        }
        losetup -P /dev/loop$lon "$image_path"
        sleep 1
        ## https://github.com/moby/moby/issues/27886#issuecomment-417074845
        LOOPDEV=$(losetup --find --show --partscan "$image_path" 2>/dev/null)
        [ -n "$LOOPDEV" ] && break
        parts=$(find /dev/loop*p*)
        [ -n "$parts" ] && break
        losetup -D "$image_path"
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

ostree_pending() {
    ostree admin status | grep -q pending
}

## system upgrade
wrap_up() {
    ##
    ## cleanup tmp folder
    rm -rf $work
    ## prune ostree
    ostree prune --refs-only --keep-younger-than="1 months ago"
    ## finish
    if $upg || ostree_pending; then
        date=$(date +%Y-%m-%d)
        echo -e "$curV updated to:\n$lasV -- $cmt\n@ ${date}\nrebooting..."
        if [ "$1" = "-f" ]; then
            reboot -f
        else
            reboot lock queue -d 10
        fi
    else
        echo -e "$curV checked for updates.\n@ ${date}"
    fi
}

del_deployments() {
    # make sure the ostree flag is set
    [ -e /run/ostree-booted ]
    # dangling tmp files can make commands fail if no space is available
    rm -rf /ostree/repo/tmp/staging-*
    set +e; ostree admin undeploy 1 || ostree admin undeploy 0; set -e
    ostree prune --keep-younger-than=1s
    ostree admin cleanup
}

get_delta() {
    check_vars repo curV delta
    set +e
    if [ -z "$1" ]; then
        nexV=$(next_release $repo $curV)
        [ -z "$nexV" -o "$nexV" = "$curV" ] && nexV=$lasV
        ## download delta
        fetch_artifact ${repo}:${nexV} ${delta}.tar $PWD
        d_status=$?
        n_files=$(find $PWD | wc -l)
        if [ $d_status != 0 -o $n_files -lt 2 ]; then
            next_v_failed=y
            err "*next* version download failed, fetching the *last* version"
        fi
    fi
    if [ -n "$1" -o -n "$next_v_failed" ]; then
        fetch_artifact ${repo}:${lasV} ${delta}_base.tar $PWD
        d_status=$?
        n_files=$(find $PWD | wc -l)
        if [ $d_status != 0  ]; then
            err "*last* version download failed"
            exit 1
        elif [ $n_files -lt 2 ]; then
            err "*last* version archive was empty (!?), build system failure"
            exit 1
        else
            printc "*last* ($lasV) delta download was succesful"
        fi
    else
        printc "*next* ($nexV) delta download was succesful"
    fi
    set -e
    get_commit
}

get_commit() {
    ## the delta file name is also the commit number
    echo "looking for commit data in $PWD ..."
    set +e; cmt_path=$(find | grep -E [a-z0-9]{64}); set -e
    if [ -n "$cmt_path" ]; then
        export cmt=$(basename $cmt_path)
    elif [ "$1" != "-q" ]; then
        echo "error: no file carried the name of a commit."
        return 1
    fi
}

apply_upgrade() {
    ## first try to upgrade, if no upgrade is available apply the delta and upgrade again
    if ostree admin upgrade --os=${os} --override-commit=$cmt 2>&1 | \
           grep -qE "Transaction complete|No update"; then
        upg=true
    else
        upg=false
    fi
    ## if no upgrade was done
    if ! $upg; then
        ostree  static-delta apply-offline $cmt
        if ostree admin upgrade --os=${os} --override-commit=$cmt 2>&1 | \
               grep -qE "Transaction complete|No update"; then
            upg=true
        else
            upg=false
        fi
    fi
}

## $@ packages to install
install_tools() {
    set +e
    setup=false
    tools="$@"
    for t in $tools; do
        if [ -z "$(apk info -e $t)" ]; then
            setup=true
            toinst="$toinst $t"
        fi
    done
    $setup && apk add --no-cache $toinst
    set -e
}

## $1 path to search
## return the name of the first file named with 64numchars
b64name() {
    echo $(basename $(find $1 | grep -E [a-z0-9]{64}))
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

