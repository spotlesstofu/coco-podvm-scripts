#!/bin/bash

BUILD_SCRIPT=$(realpath $0)
TAR_FOLDER=$(dirname $BUILD_SCRIPT)
OUT_DIR=$(dirname $TAR_FOLDER)

TAR=$OUT_DIR/luks-config.tar.gz

rm -f $TAR
cd $TAR_FOLDER
tar -czvf $TAR usr etc