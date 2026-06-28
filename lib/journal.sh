#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

debian_throttle_journal() {
    if grep -q "SystemMaxUse=100M" /etc/systemd/journald.conf 2>/dev/null && \
       grep -q "MaxLevelStore=info" /etc/systemd/journald.conf 2>/dev/null; then
        echo "  Journal already throttled. Skipping."
        return 0
    fi

    echo -e "--> Throttling systemd journal writes..."

    cp /etc/systemd/journald.conf /etc/systemd/journald.conf.bak 2>/dev/null || true

    sed -i '/^SystemMaxUse=/c\SystemMaxUse=100M' /etc/systemd/journald.conf
    sed -i '/^MaxLevelStore=/c\MaxLevelStore=info' /etc/systemd/journald.conf

    if ! grep -q "SystemMaxUse=100M" /etc/systemd/journald.conf 2>/dev/null; then
        echo "SystemMaxUse=100M" >> /etc/systemd/journald.conf
    fi
    if ! grep -q "MaxLevelStore=info" /etc/systemd/journald.conf 2>/dev/null; then
        echo "MaxLevelStore=info" >> /etc/systemd/journald.conf
    fi

    systemctl restart systemd-journald
    echo -e "  Journal throttling configured."
}
