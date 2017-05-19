shopt -s expand_aliases &>/dev/null
cn="\033[1;32;40m"
cf="\033[0m"
printc() {
    echo -e "${cn}$@${cf}"
}

git_versions() {
    git ls-remote -t git://github.com/"$1".git | awk '{print $2}' | cut -d '/' -f 3 | grep -v "\-rc" | cut -d '^' -f 1 | sed 's/^v//'
}

pine_version() {
    git_versions untoreh/pine | sort -bt- -k1nr -k2nr | head -1
}

last_version() {
    git_versions $1 | sort -bt. -k1nr -k2nr -k3r -k4r -k5r | head -1
}

## $1 repo
last_release() {
    wget -qO- https://api.github.com/repos/${1}/releases/latest |  \
 awk '/tag_name/ { print $2 }' | head -1 | sed -r 's/",?//g'
}

## $1 repo
## $2 artifact name
## $3 dest dir
fetch_artifact() {
    [ -f $3/$2 ] && return 0
    art_url=$(wget -qO- https://api.github.com/repos/${1}/releases |
    grep browser_download_url | grep ${2} | head -n 1 | cut -d '"' -f 4)
    [ -z "$(echo "$art_url" | grep "://")" ] && exit 1
    ## if no destination dir stream to stdo
    if [ "$3" = "-" ]; then
        wget $art_url -qO-
    else
        mkdir -p $3
        if [ $(echo "$2" | grep -E "gz|tgz|zip|xz|7z") ]; then
            wget $art_url -qO- | tar xz -C $3
        else
            wget $art_url -qO- | tar x -C $3
        fi
        touch $3/$2
    fi
}

## $1 image file path
## $2 mount target
## mount image, ${lon} populated with loop device number
mount_image() {
    umount -Rfd $2 ; rm -rf $2 && mkdir $2
    lon=0
    while [ -z "`losetup -P /dev/loop${lon} $(realpath ${1}) && echo true`" ]; do
        lon=$((lon + 1))
        [ $lon -gt 10 ] && return 1
        sleep 1
    done
    ldev=/dev/loop${lon}
    tgt=$(realpath $2)
    mkdir -p $tgt
    for p in $(find /dev/loop${lon}p*); do
        mp=$(echo "$p" | sed 's~'$ldev'~~')
        mkdir -p $tgt/$mp
        mount -o nouuid $p $tgt/$mp
    done
}

## $@ packages to install
install_tools() {
    setup=false
    tools="$@"
    for t in $tools ; do
        if [ -z "`apk info -e $t`" ] ; then
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

compare_csums() {
    if [ "$new_csum" = "$old_csum" ] ; then
        printc "${pkg} already up to update."
        echo $pkg >> file.up
        exit
    fi
}

if [ $(echo "$SHELL" | grep bash) ]; then
    export -f `declare -F | awk '{print $3}'`
fi
