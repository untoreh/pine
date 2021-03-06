#!/bin/sh

if [ "$1" != lock ] ; then
    shift
    exec /bin/busybox reboot $@
fi

consul=${CONSUL_PATH:-/opt/bin/consul}
default_max_reboots=3

consul_reboot_clear(){
    $consul kv delete reboot/queue/$IPv4
}

consul_reboot(){
    ## get the current allowed queue length (>=1)
    max=$($consul kv get reboot/max || echo $default_max_reboots)
    $consul lock -n $max reboot reboot_locker $max
}

## setup vars
. /etc/network-environment
[ -z "$NODE" -o -z "$CONSUL_HTTP_ADDR" ] &&
    echo "error: empty NODE id or CONSUL_HTTP_ADDR, check /etc/network-environment" && exit 1

shift
case "$1" in
    clear) consul_reboot_clear ;;
    queue) consul_reboot $@ ;;
esac
