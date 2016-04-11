#!/bin/bash

export GITHUB_USER=${GITHUB_USER:-phuslu}
export GITHUB_REPO=${GITHUB_REPO:-goproxy}
export GITHUB_CI_REPO=${GITHUB_CI_REPO:-goproxy-ci}
export GITHUB_COMMIT_ID=${TRAVIS_COMMIT:-${COMMIT_ID:-master}}
export WORKING_DIR=$HOME/tmp.$(date "+%Y%m%d%H%M%S").${RANDOM:-$$}.${GITHUB_REPO}
export GOROOT_BOOTSTRAP=${WORKING_DIR}/go1.6
export GOROOT=${WORKING_DIR}/go
export GOPATH=${WORKING_DIR}/gopath
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH

if [ ${#GITHUB_TOKEN} -eq 0 ]; then
	echo "\$GITHUB_TOKEN is not set, abort"
	exit 1
fi

function init_github() {
	mkdir -p ${WORKING_DIR} && cd ${WORKING_DIR}

	git config --global user.name ${GITHUB_USER}
	git config --global user.email "${GITHUB_USER}@noreply.github.com"

	if ! grep -q 'machine github.com' ~/.netrc; then
		(set +x; echo "machine github.com login $GITHUB_USER password $GITHUB_TOKEN" >>~/.netrc)
	fi

	local GITHUB_RELEASE_BINARY_URL=https://github.com/aktau/github-release/releases/download/v0.6.2/linux-amd64-github-release.tar.bz2
	local GITHUB_RELEASE_BINARY_PATH=$(pwd)/$(curl -L ${GITHUB_RELEASE_BINARY_URL} | tar xjpv | head -1)
	export PATH=$PATH:${GITHUB_RELEASE_BINARY_PATH%/*}
}

function build_go() {
	mkdir -p ${WORKING_DIR} && cd ${WORKING_DIR}

	curl -k https://storage.googleapis.com/golang/go1.6.linux-amd64.tar.gz | tar xz
	mv go go1.6

	git clone https://github.com/phuslu/go
	(cd go &&\
		git remote add -f upstream https://github.com/golang/go &&\
		git rebase upstream/master &&\
		git push -f origin master \
	)
	(cd go/src/ &&\
		BUILD_GO_TAG_BACK_STEPS=~3 bash ./make.bash \
	)

	(set +x; \
		echo '======================================' ;\
		cat /etc/issue ;\
		uname -a ;\
		echo ;\
		go version ;\
		go env ;\
		echo ;\
		env | grep -v GITHUB_TOKEN ;\
		echo '======================================' ;\
	)
}

function build_goproxy() {
	mkdir -p ${WORKING_DIR} && cd ${WORKING_DIR}

	git clone --branch "master" https://github.com/${GITHUB_USER}/${GITHUB_REPO} ${GITHUB_REPO}

	cd ${GITHUB_REPO}
	git checkout -f ${GITHUB_COMMIT_ID}

	export RELEASE=$(git rev-list HEAD| wc -l |xargs)
	export RELEASE_DESCRIPTION=$(git log -1 --oneline --format="r${RELEASE}: [\`%h\`](https://github.com/${GITHUB_USER}/${GITHUB_REPO}/commit/%h) %s")
	if [ -n "${TRAVIS_BUILD_ID}" ]; then
		export RELEASE_DESCRIPTION=$(echo ${RELEASE_DESCRIPTION} | sed -E "s#^(r[0-9]+)#[\1](https://travis-ci.org/${GITHUB_USER}/${GITHUB_REPO}/builds/${TRAVIS_BUILD_ID})#g")
	fi

	mkdir ${WORKING_DIR}/r${RELEASE}

	awk 'match($1, /"((github\.com|golang\.org|gopkg\.in)\/.+)"/) {if (!seen[$1]++) {gsub("\"", "", $1); print $1}}' $(find . -name "*.go") | xargs -n1 -i go get -v {}

	for OSARCH in linux/amd64 linux/386 linux/arm linux/arm64 linux/mips64 linux/mips64le darwin/amd64 darwin/386 windows/amd64 windows/386; do
		make GOOS=${OSARCH%/*} GOARCH=${OSARCH#*/}
		cp -r build/dist/* ${WORKING_DIR}/r${RELEASE}
		make clean
	done

	ls -lht ${WORKING_DIR}/r${RELEASE}/*
}

function release_goproxy_ci() {
	mkdir -p ${WORKING_DIR} && cd ${WORKING_DIR}

	if [ "$TRAVIS_PULL_REQUEST" == "true" ]; then
		return
	fi

	git clone --branch "master" https://github.com/${GITHUB_USER}/${GITHUB_CI_REPO} ${GITHUB_CI_REPO}
	cd ${GITHUB_CI_REPO}

	git commit --allow-empty -m "release"
	git tag -d r${RELEASE} || true
	git tag r${RELEASE}
	git push -f origin r${RELEASE}

	cd ${WORKING_DIR}/r${RELEASE}/
	github-release delete --user ${GITHUB_USER} --repo ${GITHUB_CI_REPO} --tag r${RELEASE} >/dev/null 2>&1 || true
	sleep 1
	github-release release --pre-release --user ${GITHUB_USER} --repo ${GITHUB_CI_REPO} --tag r${RELEASE} --name "${GITHUB_REPO} r${RELEASE}" --description "${RELEASE_DESCRIPTION}"

	for FILE in *; do
		github-release upload --user ${GITHUB_USER} --repo ${GITHUB_CI_REPO} --tag r${RELEASE} --name ${FILE} --file ${FILE}
	done
}

function clean() {
	cd ${WORKING_DIR}/r${RELEASE}/
	ls -lht
	cd
	rm -rf $HOME/tmp.*.${GITHUB_REPO}
}

init_github
build_go
build_goproxy
release_goproxy_ci
clean