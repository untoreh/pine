#!/bin/sh
## this file must be sourced to operate in the correct directory

## install packages from alpine to install init scripts...etc, then replace binaries
## with the upstream ones
# apkc add docker

## DOCKER
# DOCKER_VERSION=`last_version docker/docker`
# wget -q https://get.docker.com/builds/Linux/x86_64/docker-${DOCKER_VERSION}.tgz -O docker.tgz
# tar xf docker.tgz
# mv docker/docker* usr/bin/
# rm -rf docker docker.tgz
