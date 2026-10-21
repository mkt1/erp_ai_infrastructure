#!/bin/bash
# Installs Docker Engine from Docker's official apt repository.
# Supports Debian and Ubuntu: the repository path follows the distribution ID
# (download.docker.com/linux/debian vs. .../linux/ubuntu). Runs unattended.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

. /etc/os-release
case "${ID:-}" in
    debian|ubuntu)
        DOCKER_DISTRO="$ID"
        DOCKER_CODENAME="${VERSION_CODENAME:-}"
        ;;
    *)
        echo "❌ Unsupported distribution '${ID:-unknown}' — only Debian and Ubuntu are supported." >&2
        exit 1
        ;;
esac
# Ubuntu sets UBUNTU_CODENAME as well; prefer it if VERSION_CODENAME is empty
[ -n "$DOCKER_CODENAME" ] || DOCKER_CODENAME="${UBUNTU_CODENAME:-}"
if [ -z "$DOCKER_CODENAME" ]; then
    echo "❌ Could not determine the release codename from /etc/os-release." >&2
    exit 1
fi
echo "Installing Docker for ${DOCKER_DISTRO} ${DOCKER_CODENAME}..."

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_DISTRO} \
  ${DOCKER_CODENAME} stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install Docker Engine, CLI, containerd, Buildx, and Compose:
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install additional packages:
sudo apt-get install -y wget rsync tree
