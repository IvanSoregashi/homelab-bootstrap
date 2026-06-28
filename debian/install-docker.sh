#!/bin/bash

debian_install_docker() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../lib/common.sh"

    local sys_user="${1:-$(detect_user)}"

    echo -e "--> Checking Docker installation..."

    if command -v docker &>/dev/null; then
        echo "  Docker is already installed. Skipping."
        return 0
    fi

    echo "  Installing Docker Engine dependencies..."
    apt-get update
    apt-get install -y ca-certificates curl

    echo "  Configuring Docker repository..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    cat <<EOF > /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    echo "  Installing Docker Engine and plugins..."
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "  Adding user '${sys_user}' to docker group..."
    if getent group docker >/dev/null; then
        usermod -aG docker "$sys_user"
        echo -e "  ✔ User '${sys_user}' added to 'docker' group. Please log out and back in for changes to take effect."
    else
        echo -e "  ! Warning: Docker group not found."
    fi

    echo -e "  ✔ Docker installed successfully."
}
