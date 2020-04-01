#!/bin/sh
## this file must be sourced to operate in the correct directory

## REBOOT MANAGER
## - The clearlock scripts dequeues the node from the reboot queue stored in consul
cat << 'EOF' >etc/init.d/clearlock
#!/sbin/openrc-run

description="Delete the current host from the reboot queue"

depend()
{
        need networking
}

start() {
        ebegin "Clearing reboot lock"
        set -a
        . /etc/network-environment
        set +a
        if find /sbin/reboot -type f &>/dev/null; then
            exec /bin/busybox timeout -s2 -t900 /sbin/reboot lock clear
        fi
        eend $?
}

stop() {
        return
}
EOF
chmod +x etc/init.d/clearlock
rm sbin/reboot ## remove to avoid following symlink during copy
cp ../reboot.sh sbin/reboot
cp ../reboot_locker sbin/
cp ../reboot_try_queue sbin/
chmod +x sbin/reboot sbin/reboot_locker sbin/reboot_try_queue

## SUP
## - the sup command is wrapped to use a default Supfile script located in etc/Supfile
## for common utilities like bootstrapping an etcd cluster
mkdir -p /go
export GOPATH=/go GOROOT=/usr/lib/go
go get -u github.com/pressly/sup/cmd/sup
mv /go/bin/sup usr/bin/sup.bin
cp ../Supfile etc/
## touch hosts files to not let sup fail on local hostsless execution
touch etc/cluster etc/leaders etc/workers
cat << 'EOF' >usr/bin/sup
#!/bin/bash -l
export -f `declare -F | awk '{print $3}'`
SUP_FILE=/etc/Supfile
if $(echo "$@" | grep -qE "\-f\s+[^\s]+\s*") ; then
    exec /usr/bin/sup.bin -e SUP_FILE=$SUP_FILE $@
else
    exec /usr/bin/sup.bin -e SUP_FILE=$SUP_FILE -f $SUP_FILE $@
fi
EOF
chmod +x usr/bin/sup

## ssh wrapper to load environment vars which dropbear does not support
cat << 'EOF' >usr/bin/ssheval
#!/bin/bash -l

if [ -n "$SSH_ORIGINAL_COMMAND" ]; then
    rgx='^(([^=]*=([^[:space:]\\]*)|((\\.)+[^\\[:space:]]*))*)([[:space:]]*[^[:space:]]+)(.*)'
    [[ "$SSH_ORIGINAL_COMMAND" =~ $rgx ]]
    if [ -z "$(type -p ${BASH_REMATCH[6]% *})" ]; then
        eval "$SSH_ORIGINAL_COMMAND"
    else
        vars=${BASH_REMATCH[1]}
        args=${BASH_REMATCH[6]}${BASH_REMATCH[7]}
        rgx='^[^"'\'']*;|\n'
        if [[ "$args" =~ $rgx ]]; then ## don't exec multi commands
            eval "$SSH_ORIGINAL_COMMAND"
        else
            eval "$vars exec $args"
        fi
    fi
else

    exec /bin/sh -li
fi

EOF
chmod +x usr/bin/ssheval

## iomon script: some VMs experience I/O failure, use iostat to monitor potential stalls and reboot on occasion
cat << 'EOF' >usr/bin/iomon
#!/bin/bash

loop=${IOMON_LOOP:-30}
device=${IOMON_DEVICE:-sda}
count=2
strikes=0

while :; do
    iostat=$(iostat -d $loop $count)
    iotail=$(tail -4 <<<"$iostat")
    tps=$(awk "/$device/"'{print $2}' <<<"$iotail")
    if [ "${tps//0}" = \. ]; then
        strikes=$((strikes+1))
        if [ $strikes -gt 3 ]; then
            echo "[$(date)]: io stalled for device $device...issueing a reboot" >> /var/log/iomon.log
            reboot
        fi
    else
        strikes=0
    fi
    read -t $loop
done

EOF
chmod +x usr/bin/iomon

## some utility shell functions
cp ../functions.sh etc/profile.d/func.sh
## make sure core dumps are disabled
cat << EOF >etc/profile
ulimit -c 0
$(</etc/profile)
EOF

## enable boot logging
sed -r 's/#?(rc_logger=).*/\1"YES"/' -i etc/rc.conf

## backup config
mkdir -p etc/conf.d
cat << EOF >etc/conf.d/dup
DUP_VER=${DUP_VER:-2.1.2}
## binary naming scheme
DUP_OS=${DUP_OS:-duplicacy_linux_x64_}
## binary name on disk
DUP_ALIAS=${DUP_ALIAS:-dup}
## base dir where duplicacy and the repo are located
DUP_PREFIX=${DUP_PREFIX:-/opt}
DUP_REPO=${DUP_REPO:-/opt/dup/repo}
DUP_MAIN_REMOTE=${DUP_MAIN_REMOTE:-gcd://main}
## CLI arguments to pass to dup eg -debug
DUP_ARGS=${DUP_ARGS:-}
## CLI arguments to pass to dup commands, eg -stats for backup command
DUP_CMD_ARGS=${DUP_CMD_ARGS:-}
DUPLICACY_GCD1_GCD_TOKEN=${DUPLICACY_GCD1_GCD_TOKEN:-/opt/dup/dist/gcd-token.json}
DUPLICACY_GCD_TOKEN=${DUPLICACY_GCD_TOKEN:-/opt/dup/dist/gcd-token.json}
DUPLICACY_ATTRIBUTE_THRESHOLD=${DUPLICACY_ATTRIBUTE_THRESHOLD:-1}
STORAGE_URL=${STORAGE_URL:-'gcd://main'}
STORAGE_NAME=${STORAGE_NAME:-gcd1}
EOF

## CONSUL
# apkc add consul consul-template
# consul_repo="hashicorp/consul"
# CONSUL_VERSION=$(last_version $consul_repo)
# consul_url="https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip"
# rm usr/sbin/consul
# fetch_artifact $consul_url usr/sbin
# chmod +x usr/sbin/consul
# setcap 'cap_net_bind_service=+ep' usr/sbin/consul
cp ../checks/consul_nameserver etc/init.d/consul_nameserver
chmod +x etc/init.d/consul_nameserver

## CONTAINERPILOT
copi_repo="joyent/containerpilot"
#COPI_VERSION=$(last_version $copi_repo)
fetch_artifact "$copi_repo" ".*.tar.gz" usr/bin
chmod +x usr/bin/containerpilot
cp ../templates/containerpilot.json5 etc/containerpilot.json5

## NETDATA
# apkc add netdata