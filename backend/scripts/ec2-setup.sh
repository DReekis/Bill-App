#!/bin/bash
# ==============================================================================
# 🚀 1-Click AWS EC2 Free Tier Auto-Setup Script for Billket Cloud
# Compatible with Ubuntu 22.04 LTS & Ubuntu 24.04 LTS on t2.micro / t3.micro
# ==============================================================================

set -e

echo "=========================================================="
echo "  🚀 Billket Cloud - 100% Free Tier EC2 Setup             "
echo "=========================================================="

# 1. Update OS packages
echo "[1/4] Updating Linux system packages..."
sudo apt-get update -y

# 2. Configure 1.5GB Swap Memory
# Crucial for t2.micro (1GB RAM) to avoid memory starvation during build/spikes
if [ ! -f /swapfile ]; then
    echo "[2/4] Allocating 1.5GB Swap space for t2.micro stability..."
    sudo fallocate -l 1536M /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "Swap allocated successfully."
else
    echo "[2/4] Swap space already present, skipping."
fi

# 3. Install Docker Engine and Docker Compose Plugin
if ! command -v docker &> /dev/null; then
    echo "[3/4] Installing official Docker & Docker Compose..."
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker "$USER" || true
    echo "Docker installed successfully."
else
    echo "[3/4] Docker already installed, skipping."
fi

# 4. Success summary and instructions
echo "[4/4] Setup complete!"
echo "=========================================================="
echo "  ✅ AWS EC2 is ready to run Billket Cloud!               "
echo "=========================================================="
echo "To launch the complete PostgreSQL + Fastify stack:"
echo "  sudo docker compose up -d --build"
echo ""
echo "To check status and live logs:"
echo "  sudo docker compose ps"
echo "  sudo docker compose logs -f api"
echo "=========================================================="
