#!/bin/bash -l
shopt -s expand_aliases

while [[ $# -gt 0 ]]; do
	key="$1"
	case $key in
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
			shift
			;;
		-h | --help)
			cat <<-EOF

			Install apps through ostree deltas checkouts.
			-b, --base  base image (alp,trub...)
			-n, --name  name of the app (etcd,hhvm...)
			-f, --force clear before install
			-d, --delete clear checkout and prune ostree repo

			EOF
			exit
			;;
		-d | --delete)
			action=delete
shift
            ;;
        *)
            name=$key
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

delete() {
    rm -rf --on-file-system $ostrepo/$name
    ostree refs --delete=$name
    ostree prune --refs-only
    ostree admin cleanup
}

install() {
    ## prepare files
	mkdir -p $workdir \
        && cd $workdir \
        && [ -n "$clob" ] && rm -f $workdir/*

    ## data
	fetch_artifact ${appsrepo}:${name} ${name}.tar $workdir
	rev=$(b64name $workdir)
	[ -z "$rev" ] && echo "error: app not found..." && exit 1

    ## install
    applied=$(ostree static-delta apply-offline $rev && echo true || echo false)
    [ ! $applied ] && echo "error: troubles applying the delta..." && exit 1
    ostree refs --create=$name $rev

    ## deploy
    ostree checkout -H $name $ostrepo/$name
}

eval $action