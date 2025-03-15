#/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while read line; do apt-get install -y $line; done < ${SCRIPT_DIR}/packages
