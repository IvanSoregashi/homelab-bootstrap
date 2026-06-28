#!/bin/bash

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

os_is_debian() {
    local os
    os=$(detect_os)
    [ "$os" = "debian" ] || [ "$os" = "ubuntu" ] || [ "$os" = "linuxmint" ] || [ "$os" = "pop" ]
}
