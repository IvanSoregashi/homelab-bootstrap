#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

SYS_USER=$(detect_user)

header "              CLONE PRIVATE REPOSITORY"

echo "  The homelab-private repository contains Docker Compose files"
echo "  and server-specific configurations."
echo ""

read -r -p "SSH clone URL (e.g., git@github.com:user/homelab-private.git): " repo_url
if [ -z "$repo_url" ]; then
    warn "No URL provided. Skipping clone."
    exit 0
fi

read -r -p "Target directory [default: /srv/encrypted/app/private]: " target_dir
target_dir=${target_dir:-/srv/encrypted/app/private}

if [ -d "$target_dir" ]; then
    echo -e "${YELLOW}Warning: ${target_dir} already exists.${NC}"
    read -r -p "Overwrite? (Pull existing instead) (y/n) [n]: " overwrite
    if [[ "$overwrite" =~ ^[Yy]$ ]]; then
        rm -rf "$target_dir"
    else
        echo "  Skipping clone."
        exit 0
    fi
fi

mkdir -p "$(dirname "$target_dir")"
run sudo -u "$SYS_USER" git clone "$repo_url" "$target_dir"

chown -R "${SYS_USER}:${SYS_USER}" "$target_dir"

echo -e "\n${GREEN}✔ Private repository cloned to ${target_dir}.${NC}"
