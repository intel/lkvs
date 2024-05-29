#!/bin/bash
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PARENT_DIR/tools" || exit 1
make