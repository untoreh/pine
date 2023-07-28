#!/usr/bin/env bash

. ./functions.sh

if [ "${TRIGGER_MSG/scratch-build}" != "${TRIGGER_MSG}" ]; then
    printc "building image...(init)"
    ./init/build.sh
    printc "building ovz...(init)"
    ./init/build_ovz.sh
else
    printc "building image...(update)"
    ./build_update.sh
    if [ "${TRIGGER_MSG/scratch-ovz}" != "${TRIGGER_MSG}" ]; then
        printc "building ovz...(init)"
        ./init/build_ovz.sh
    else
        printc "building ovz...(update)"
        ./build_update_ovz.sh
    fi
fi
