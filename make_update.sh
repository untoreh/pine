#!/usr/bin/env bash

. ./functions.sh

if [ "${COMMIT_MSG/scratch-build}" != "${COMMIT_MSG}" ]; then
    printc "building image...(init)"
    ./init/build.sh
    printc "building ovz...(init)"
    ./init/build_ovz.sh
else
    printc "building image...(update)"
    ./build_update.sh
    if [ "${COMMIT_MSG/scratch-ovz}" != "${COMMIT_MSG}" ]; then
        printc "building ovz...(init)"
        ./init/build_ovz.sh
    else
        printc "building ovz...(update)"
        ./build_update_ovz.sh
    fi
fi
