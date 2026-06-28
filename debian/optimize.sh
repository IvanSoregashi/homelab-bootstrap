#!/bin/bash

debian_optimize_system() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local optimize_dir="${script_dir}/optimize"
    local data_path="$1"

    echo -e "Starting system optimization for Debian..."

    if [ -f "${optimize_dir}/memory.sh" ]; then
        source "${optimize_dir}/memory.sh"
        debian_optimize_memory "$data_path"
    fi

    if [ -f "${optimize_dir}/logs.sh" ]; then
        source "${optimize_dir}/logs.sh"
        debian_optimize_logs
    fi

    if [ -f "${optimize_dir}/filesystem.sh" ]; then
        source "${optimize_dir}/filesystem.sh"
        debian_optimize_filesystem
    fi

    if [ -f "${optimize_dir}/docker.sh" ]; then
        source "${optimize_dir}/docker.sh"
        debian_optimize_docker "$data_path"
    fi

    echo -e "\n${GREEN}✔ Optimization complete. Monitor your system logs for any issues.${NC}"
}
