#!/bin/bash
##################################################
## Make sure that you installed the packages
## described here:
## ./installer/README.md
##################################################
## vars
export XCLEAN=true
export XBUILD=true
export XUSE_UPDATE=60
#export XDEBUG=true
export XCACHE=true
EXTRA_FLAGS="--disable-warnings-as-errors" # disable warning error

if [ "$XCACHE" = "true" ]; then
    echo "Using ccache"
    EXTRA_FLAGS="${EXTRA_FLAGS} --enable-ccache --with-ccache-dir=${PWD}/.ccache"
fi

export XEXTRA_FLAGS=${EXTRA_FLAGS}
###################################################
## first, lets clean the output dir. DO NOT STORE
## ANYTHING IN THIS FOLDER, IT WILL GET DELETED!
if [ -d "OBF_DROP_DIR" ]; then
    # rm -rf OBF_DROP_DIR
    echo "Deleted OBF_DROP_DIR"
fi
## build openjdk 11. The first parameter (if not empty)
## has to be one of the following:
## 1. --just-build when we are compiling...
## if empty, then it will build and clone when needed
echo "Building OpenJDK11"
$PWD/installer/linux/standalone-job.sh --just-build

echo "Untar OpenJDK11"
$PWD/untar.sh
###################################################
## done
###################################################
