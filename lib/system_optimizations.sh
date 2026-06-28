#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

_confirm() {
    local prompt="$1"
    local default="${2:-y}"
    read -r -p "  ${prompt} (y/n) [${default}]: " response
    [[ "${response:-$default}" =~ ^[Yy]$ ]]
}

_resolve_data_path() {
    local path="${1:-}"
    if [ -n "$path" ]; then
        echo "$path"
        return
    fi
    local default="/srv/data"
    read -r -p "  Target data path [${default}]: " input
    echo "${input:-$default}"
}

debian_optimize_mmc_writes() {
    local data_path="${1:-}"

    echo -e "\n${BOLD}Starting eMMC/SSD write optimization...${NC}"

    # Step 1: Memory / Swap
    echo -e "\n${CYAN}------------------------------------------------------------${NC}"
    echo -e "${BOLD}[1/4] ZRAM & Swap Optimization${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    if _confirm "Run ZRAM, swap file, and swappiness tuning?"; then
        source "${SCRIPT_DIR}/ram.sh"
        debian_install_zram
        debian_setup_zram
        data_path=$(_resolve_data_path "$data_path")
        debian_setup_swapfile "$data_path"
        debian_tune_swappiness
    fi

    # Step 2: Journal
    echo -e "\n${CYAN}------------------------------------------------------------${NC}"
    echo -e "${BOLD}[2/4] Systemd Journal Throttling${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    if _confirm "Throttle systemd journal to 100M?"; then
        source "${SCRIPT_DIR}/journal.sh"
        debian_throttle_journal
    fi

    # Step 3: noatime
    echo -e "\n${CYAN}------------------------------------------------------------${NC}"
    echo -e "${BOLD}[3/4] Filesystem noatime Tuning${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    if _confirm "Set noatime on root filesystem?"; then
        source "${SCRIPT_DIR}/atime.sh"
        debian_disable_atime
    fi

    # Step 4: Docker
    echo -e "\n${CYAN}------------------------------------------------------------${NC}"
    echo -e "${BOLD}[4/4] Docker Storage Relocation${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    if _confirm "Relocate Docker storage to data volume?"; then
        source "${SCRIPT_DIR}/docker.sh"
        data_path=$(_resolve_data_path "$data_path")
        debian_relocate_docker "$data_path"
    fi

    echo -e "\n${GREEN}✔ Optimization complete.${NC}"
}
