#!/usr/bin/env bash

. ./functions.sh

if [ "\${COMMIT_MSG/scratch-build}" != "\${COMMIT_MSG}" ]; then
    printc "this is a scratch build..."
    ./init/build.sh
    printc "ovz..."
    ./init/build_ovz.sh
else
    printc "this is an updated build..."
    ./build_update.sh
    printc "ovz..."
    ./build_update_ovz.sh
fi
