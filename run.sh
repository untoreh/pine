#!/bin/sh
. ./functions.sh

## prepare
printc "preparing..."
./prepare.sh

cat <<EOF >main_ex
. ./functions.sh
main() {
	## init the repo
	printc "initializing the repo..."
	./repo.sh

	## the tree of files
	printc "growing bare/kvm tree..."
	./make.sh
	printc "growing ovz tree..."
	./make_ovz.sh

	## update image from github
	printc "building image..."
	printc "$COMMIT_MSG"
	if [ "\${COMMIT_MSG/scratch-build}" != "\${COMMIT_MSG}" ]; then
		printc "this is a scratch build..."
		./init/build.sh
		printc "ovz..."
		./init/build_ovz.sh
	else
		printc "this is an updated build..."
		./build-update.sh
		printc "ovz..."
		./build-update_ovz.sh
	fi
}
main
EOF

mkfifo foo
stdbuf -o0 -e0 -i0 grep . foo | while read line; do echo -e "\e[01;31m$line\e[0m" >&2; done &
stdbuf -o0 -e0 -i0 bash main_ex 2>foo
