#!/bin/bash

debian_optimize_docker() {
    local data_path="$1"
    local docker_root="${data_path}/docker"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../../lib/common.sh"

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
