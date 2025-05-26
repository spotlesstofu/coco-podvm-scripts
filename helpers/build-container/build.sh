#! /bin/bash

IMAGE_PATH=$1

if [ -z ${IMAGE_PATH} ]; then
    echo "Usage: $0 <qcow2 path>"
    exit 1
fi

cp $IMAGE_PATH .
FILENAME=$(basename $IMAGE_PATH)
podman build -t coco-podvm --build-arg PODVM_IMAGE_SRC=$FILENAME .
rm -f $FILENAME