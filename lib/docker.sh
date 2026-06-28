#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

debian_install_docker() {
    local sys_user="${1:-$(detect_user)}"

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

debian_relocate_docker() {
    local data_path="$1"
    local docker_root="${data_path}/docker"

    if ! command -v docker &>/dev/null; then
        echo "  Docker is not installed. Skipping relocation."
        return 0
    fi

    if [ -f /etc/docker/daemon.json ] && grep -q "\"data-root\".*\"${docker_root}\"" /etc/docker/daemon.json 2>/dev/null; then
        echo "  Docker root already set to ${docker_root}. Skipping."
        return 0
    fi

    echo -e "--> Relocating Docker storage to ${docker_root}..."

    systemctl stop docker.service docker.socket || true

    mkdir -p "$docker_root"
    apt-get install -y rsync

    if [ -d "/var/lib/docker" ]; then
        rsync -aP /var/lib/docker/ "$docker_root/"
        mv /var/lib/docker /var/lib/docker.old
    fi

    cat << EOF > /etc/docker/daemon.json
{
  "data-root": "${docker_root}"
}
EOF

    systemctl start docker

    if [ -d "/var/lib/docker.old" ]; then
        rm -rf /var/lib/docker.old
    fi

    echo -e "  Docker storage relocated."
}
