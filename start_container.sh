#!/usr/bin/env bash

docker run --env-file build.env -d \
    --name pinect \
    -v $PWD:/srv \
    -v /dev:/dev \
    -v /sys:/sys \
    --privileged \
    --cap-add=ALL \
    -w /srv alpine:latest \
    /bin/sleep 36000
