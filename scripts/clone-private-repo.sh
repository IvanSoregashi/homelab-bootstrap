#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

SYS_USER=$(detect_user)
GITHUB_USER="${1:-}"
if [ -z "$GITHUB_USER" ]; then
    read -r -p "  GitHub username [IvanSoregashi]: " GITHUB_USER
    GITHUB_USER=${GITHUB_USER:-IvanSoregashi}
fi

header "              CLONE PRIVATE REPOSITORY"

echo "  The private repository contains Docker Compose files"
echo "  and server-specific configurations."
echo ""

read -r -p "  Repository name [homelab]: " repo_name
repo_name=${repo_name:-homelab}
repo_url="git@github.com:${GITHUB_USER}/${repo_name}.git"

HOME_DIR=$(eval echo "~$SYS_USER")
default_target="$HOME_DIR"
read -r -p "  Target parent directory [${default_target}]: " target_parent
target_parent=${target_parent:-$default_target}
target_dir="${target_parent}/${repo_name}"

if [ -d "$target_dir" ]; then
    echo -e "${YELLOW}Warning: ${target_dir} already exists.${NC}"
    read -r -p "  Overwrite? (Pull existing instead) (y/n) [n]: " overwrite
    if [[ "$overwrite" =~ ^[Yy]$ ]]; then
        rm -rf "$target_dir"
    else
        echo "  Skipping clone."
        exit 0
    fi
fi

run sudo -u "$SYS_USER" git clone "$repo_url" "$target_dir"

chown -R "${SYS_USER}:${SYS_USER}" "$target_dir"

echo -e "\n${GREEN}✔ Private repository cloned to ${target_dir}.${NC}"
