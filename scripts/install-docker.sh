#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/platform.sh"

SYS_USER="${1:-$(detect_user)}"

header "                 DOCKER ENGINE INSTALL"

if os_is_debian; then
    source "${SCRIPT_DIR}/../lib/docker.sh"
    debian_install_docker "$SYS_USER"
else
    error "No distribution-specific Docker installation available for $(detect_os)."
    echo "  Please install Docker manually for your distribution."
    exit 1
fi
