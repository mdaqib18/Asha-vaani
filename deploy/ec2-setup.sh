#!/usr/bin/env bash
# Prepare a fresh Ubuntu 24.04 EC2 instance with Docker Engine, Compose v2,
# and host mount directories for Asha Vaani.

set -euo pipefail

echo "==> Updating apt package index and installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg git

echo "==> Adding Docker's official GPG key and apt repository..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# shellcheck disable=SC1091
source /etc/os-release
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  ${VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

echo "==> Installing Docker Engine and Compose plugin..."
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Enabling Docker service and adding user to docker group..."
sudo systemctl enable --now docker
TARGET_USER="${SUDO_USER:-$USER}"
sudo usermod -aG docker "$TARGET_USER"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$REPO_ROOT/data" "$REPO_ROOT/backups"

echo ""
echo "Docker Engine and Compose installed cleanly:"
docker --version
docker compose version
echo ""
echo "IMPORTANT: Log out and SSH back in (or run 'newgrp docker') so '$TARGET_USER' can run docker without sudo."
