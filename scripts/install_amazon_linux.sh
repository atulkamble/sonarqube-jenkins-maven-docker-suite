#!/usr/bin/env bash
set -euo pipefail

# Tested on Amazon Linux 2023
echo "[INFO] Updating OS packages..."
sudo dnf -y update

echo "[INFO] Installing prerequisites..."
sudo dnf -y install git curl jq util-linux-user

echo "[INFO] Installing Docker..."
# Amazon Linux 2023
sudo dnf -y install docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER || true

echo "[INFO] Installing Docker Compose plugin..."
# docker-compose v2 (compose CLI plugin)
DOCKER_COMPOSE_VERSION="v2.29.7"
sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose version

echo "[INFO] Setting vm.max_map_count for SonarQube (requires sudo)..."
if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Optional: raise file descriptors a bit
if ! grep -q "fs.file-max" /etc/sysctl.conf; then
  echo "fs.file-max=131072" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

REPO_DIR="${1:-sonarqube-jenkins-maven-docker-suite}"

if [ ! -d "$REPO_DIR" ]; then
  echo "[INFO] Cloning example repo skeleton..."
  git clone https://github.com/example/${REPO_DIR}.git || true
fi

cd "$REPO_DIR" || { echo "Repo dir not found"; exit 1; }

echo "[INFO] Creating .env from template if missing..."
[ -f .env ] || cp .env.example .env

echo "[INFO] Bringing stack up..."
docker-compose up -d

echo
echo "[SUCCESS] Stack is starting."
echo "Jenkins:    http://<EC2-Public-IP>:8080"
echo "SonarQube:  http://<EC2-Public-IP>:9000"
echo
echo "NOTE: Log out and back in (or 'newgrp docker') to use Docker without sudo."
