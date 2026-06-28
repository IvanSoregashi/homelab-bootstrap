#!/bin/bash

install_restic() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../lib/common.sh"
    source "${script_dir}/../lib/platform.sh"

    if command -v restic &>/dev/null; then
        echo "  Restic is already installed. Skipping."
        return 0
    fi

    echo "--> Installing Restic..."

    if os_is_debian; then
        apt-get update
        apt-get install -y restic
    else
        echo "  Restic not available via package manager. Installing from GitHub..."
        local latest_url
        latest_url=$(curl -s https://api.github.com/repos/restic/restic/releases/latest | grep "browser_download_url.*linux_amd64" | cut -d'"' -f4)
        if [ -n "$latest_url" ]; then
            curl -sSL -o /tmp/restic.bz2 "$latest_url"
            bzip2 -d /tmp/restic.bz2
            mv /tmp/restic /usr/local/bin/restic
            chmod +x /usr/local/bin/restic
            rm -f /tmp/restic.bz2
        else
            error "Could not determine latest Restic release URL."
            exit 1
        fi
    fi

    echo -e "  ${GREEN}✔ Restic installed.${NC}"
}
