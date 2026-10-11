#!/bin/bash
# ==============================================================================
# 🔒 1-Click Nginx Reverse Proxy & SSL Setup Script for Billket
# Installs Nginx + Certbot, configures reverse proxy to port 4000, and enables HTTPS
#
# Usage:
#   sudo bash setup-nginx-ssl.sh [DOMAIN] [EMAIL]
#
# Examples:
#   1) With Domain and Free SSL (Certbot):
#      sudo bash setup-nginx-ssl.sh api.billket.in admin@billket.in
#
#   2) Without Domain (Direct EC2 IP / HTTP on Port 80):
#      sudo bash setup-nginx-ssl.sh _
# ==============================================================================

set -euo pipefail

DOMAIN="${1:-_}"
EMAIL="${2:-}"

echo "=========================================================="
echo "  🔒 Billket Cloud - Nginx & SSL Automation Setup        "
echo "=========================================================="
echo "Configuring domain: ${DOMAIN}"

# 1. Install Nginx and Certbot
echo "[1/4] Installing Nginx and Certbot..."
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx

# 2. Configure Nginx site
echo "[2/4] Generating Nginx configuration..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/nginx-billket.conf"

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "❌ Error: Template ${TEMPLATE_FILE} not found!" >&2
  exit 1
fi

sed "s/YOUR_DOMAIN_OR_IP/${DOMAIN}/g" "$TEMPLATE_FILE" > /etc/nginx/sites-available/billket.conf

# Enable site and remove default
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/billket.conf /etc/nginx/sites-enabled/billket.conf

# 3. Test and reload Nginx
echo "[3/4] Testing Nginx configuration..."
nginx -t
systemctl restart nginx
systemctl enable nginx

# 4. Issue Let's Encrypt SSL certificate if domain is provided and not '_'
if [ "$DOMAIN" != "_" ] && [ -n "$EMAIL" ]; then
  echo "[4/4] Obtaining free SSL certificate from Let's Encrypt for ${DOMAIN}..."
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
  systemctl reload nginx
  echo "✅ HTTPS SSL certificate successfully installed and activated for ${DOMAIN}!"
else
  echo "[4/4] Skipping Certbot (no domain/email provided). Nginx is running HTTP on port 80."
fi

echo "=========================================================="
echo "  ✅ Nginx Reverse Proxy Setup Completed Successfully!    "
echo "=========================================================="
