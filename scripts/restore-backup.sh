#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

header "              RESTORE FROM BACKUP"

RESTIC_CORE_ENV="/srv/encrypted/apps/restic/core-env.sh"
RESTIC_DATA_ENV="/srv/encrypted/apps/restic/data-env.sh"

if [ ! -f "$RESTIC_CORE_ENV" ] || [ ! -f "$RESTIC_DATA_ENV" ]; then
    warn "Restic environment files not found. Run bootstrap first."
    exit 1
fi

echo "  Which repository would you like to restore from?"
echo "  1) Core (encrypted data - vault, archive, app configs)"
echo "  2) Data (bulk data - gallery, books)"
echo "  3) Both"
echo ""

read -r -p "Select [1-3]: " restore_choice

case "$restore_choice" in
    1|2)
        local env_file="$RESTIC_CORE_ENV"
        local label="Core"
        if [ "$restore_choice" = "2" ]; then
            env_file="$RESTIC_DATA_ENV"
            label="Data"
        fi

        source "$env_file"

        if ! restic snapshots --no-lock 2>/dev/null; then
            error "Could not list snapshots for ${label}. Check connectivity."
            exit 1
        fi

        echo ""
        read -r -p "Enter snapshot ID to restore (or 'latest'): " snapshot_id
        snapshot_id=${snapshot_id:-latest}

        read -r -p "Target directory for restore [default: /tmp/restore-${label,,}]: " target
        target=${target:-/tmp/restore-${label,,}}

        if [ "$snapshot_id" = "latest" ]; then
            run restic restore latest --target "$target"
        else
            run restic restore "$snapshot_id" --target "$target"
        fi

        echo -e "\n${GREEN}✔ ${label} backup restored to ${target}.${NC}"
        echo "  Manually move files to their proper locations as needed."
        ;;
    3)
        echo "  Restoring both repositories sequentially..."
        bash "$0" 1
        bash "$0" 2
        ;;
    *)
        warn "Invalid choice. Exiting."
        exit 0
        ;;
esac
