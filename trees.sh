#!/bin/bash -l
shopt -s expand_aliases

while [[ $# -gt 0 ]]; do
		case $1 in
				-b | --base)
						base="$2"
						shift
						;;
				-n | --name)
						name="$2"
						shift
						;;
				-f | --force)
						clob=1
						;;
				-d | --delete)
						action=delete
						;;
				-t | --target)
						target="$2"
						shift
						;;
				-h | --help | -* | --*)
						action=help
						;;
				co | checkout)
						action=checkout
						;;
				*)
						case $action in
							checkout)
								target=${target:-$1}
								;;
							*)
								name=${name:-$1}
						esac
						;;
		esac
		shift
done

## vars

repo=untoreh/$base
appsrepo=untoreh/trees
ostrepo=/var/lib/apps/repo
workdir=/var/tmp/sup/${name}
action=${action:-install}
alias ostree="ostree --repo=$ostrepo"

## ovz
source /etc/ovz &>/dev/null
if [ -z "$OVZ" ]; then
		$(which /usr/bin/ostree) admin status | grep -q ovz && \
		echo OVZ=1 >/etc/ovz || \
		echo OVZ=0 >/etc/ovz
fi
source /etc/ovz

## actions

help() {
		cat <<-EOF
		Usage: trees APP [FLAGS]...

		Install apps through ostree deltas checkouts.
		-b, --base  base image (alp,trub...)
		-n, --name  name of the app (etcd,hhvm...)
		-f, --force clear before install
		-d, --delete clear checkout and prune ostree repo

		EOF
		exit
}

delete() {
		[ -z "$name" ] && exit 1
		rm -rf --one-file-system $ostrepo/$name
		ostree refs --delete $name
		ostree prune --refs-only
		/usr/bin/ostree admin cleanup
}

install() {
		## prepare files
		mkdir -p $workdir && \
				cd $workdir && \
				\
				[ -n "$clob" ] && \
				rm -f $workdir/* && \
				ostree refs --delete $name && \
				rm -rf --one-file-system $ostrepo/$name

		## data
		## ovz is only for the alpine base since they share with host repo
		if [ $OVZ = 1 ] && [ "$base" = "pine" -o -z "$base" ]; then
				artf="${name}_ovz.tar"
		else
				artf="${name}.tar"
		fi
		fetch_artifact ${appsrepo}:${name} $artf $workdir
		rev=$(b64name $workdir)
		[ -z "$rev" ] && err "error: app not found..." && exit 1

		## install
		applied=$(ostree static-delta apply-offline $rev && echo true || echo false)
		! $applied && err "error: troubles applying the delta..." && exit 1
		ostree refs --create=$name $rev

		## deploy
		mkdir -p $ostrepo/$name
		ostree checkout -H $name $ostrepo/$name/rootfs
}

checkout() {
		mkdir -p $ostrepo/$name
		dest=${target:-$ostrepo/$name/rootfs}
		ostree checkout --require-hardlinks --union-add $name $dest
}

eval $action
