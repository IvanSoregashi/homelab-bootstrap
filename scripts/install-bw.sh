#!/bin/bash

install_bw() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../lib/common.sh"

    if command -v bw &>/dev/null; then
        echo "  Bitwarden CLI is already installed. Skipping."
        return 0
    fi

    echo "--> Installing Bitwarden CLI..."

    if ! command -v jq &>/dev/null; then
        apt-get install -y jq
    fi
    if ! command -v unzip &>/dev/null; then
        apt-get install -y unzip
    fi
    if ! command -v curl &>/dev/null; then
        apt-get install -y curl
    fi

    curl -sSL -o /tmp/bw.zip "https://vault.bitwarden.com/download/?app=cli&platform=linux"
    unzip -o /tmp/bw.zip -d /tmp
    mv /tmp/bw /usr/local/bin/
    rm -f /tmp/bw.zip
    chmod +x /usr/local/bin/bw

    echo -e "  ${GREEN}✔ Bitwarden CLI installed.${NC}"
}
