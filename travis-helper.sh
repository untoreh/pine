#!/bin/bash

gem install travis
source functions.*
env >build.env

handle_deploy() {
	if [ "$TRAVIS_TAG" -a -f file.up ]; then
		GIT_REMOTE=$(git remote show origin | grep -i "push.*url" \
			| sed -r 's~.*push.*?:[ \s]+(.*?://)(.*)$~\1'$GIT_USER:$GIT_TOKEN'@\2~i')
		git tag -d $TRAVIS_TAG
		git push --delete $GIT_REMOTE $TRAVIS_TAG
		travis cancel $TRAVIS_BUILD_NUMBER --no-interactive -t $TRAVIS_TOKEN
	fi
}

handle_tags() {
	## since a build has been deployed rebuild dependend images on the /trees repo
	git clone --depth=1 https://$GIT_USER:$GIT_TOKEN@github.com/$trees_repo && cd $(basename $trees_repo)
	git tag ${tag_prefix}-$(md)
	git push --tags --force
}