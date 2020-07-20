#!/bin/bash

usage() {
    echo "$(basename $0) <dirs_path> <mount_points_path>"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

DIRS_PATH=$1
MOUNT_POINTS_PATH=$2

SCRIPT="
for i in \$(seq -f '%02g' 5); do
    mkdir -p ${DIRS_PATH}/\$i;
    mkdir -p ${MOUNT_POINTS_PATH}/\$i;
    echo \"${DIRS_PATH}/\$i ${MOUNT_POINTS_PATH}/\$i none defaults,bind 0 0\" >> /etc/fstab;
done
mount -a
"

echo "$SCRIPT"