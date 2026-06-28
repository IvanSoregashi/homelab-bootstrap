#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/platform.sh"

require_root

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_data_volume>"
    echo "Example: $0 /bulk"
    exit 1
fi

DATA_PATH=$(realpath "$1")

header "                 SYSTEM OPTIMIZATION"

if os_is_debian; then
    source "${SCRIPT_DIR}/../lib/system_optimizations.sh"
    debian_optimize_mmc_writes "$DATA_PATH"
else
    info "No distribution-specific optimization available for $(detect_os)."
    echo "  Skipping system optimization."
fi
