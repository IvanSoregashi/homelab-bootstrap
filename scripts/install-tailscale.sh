#!/bin/bash

install_tailscale() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../lib/common.sh"

    if command -v tailscale &>/dev/null; then
        echo "  Tailscale is already installed. Skipping."
        return 0
    fi

    echo "--> Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh

    echo -e "  ${GREEN}✔ Tailscale installed.${NC}"
    echo "  Connect to your tailnet with: sudo tailscale up"
    echo "  Or use an auth key: sudo tailscale up --authkey=tskey-..."
}
