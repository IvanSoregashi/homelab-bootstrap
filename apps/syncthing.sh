#!/bin/bash
set -euo pipefail

SECURE_PATH="$1"
DATA_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Syncthing..."

mkdir -p "${SECURE_PATH}/apps/syncthing"
mkdir -p "${SECURE_PATH}/vault"

chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/apps/syncthing"
echo "  Syncthing directories initialized."
