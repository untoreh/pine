#!/bin/bash
. ./functions.sh
cd /srv

# $1 repo/tree name
init_repo() {
    local name=$1 ref=trunk
    rm -rf ${name} ${name}_tree
    mkdir -p ${name} ${name}_tree
    ostree --repo=${name} --mode=archive-z2 init
    ostree --repo=${name} commit -s $(date)'-build' -b $ref --tree=dir=${name}_tree
}

printc "init repo pine"
init_repo pine
printc "init repo ovz"
init_repo pine_ovz
