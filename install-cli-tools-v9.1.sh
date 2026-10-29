#!/bin/bash
# Exit on any error
set -e

# ==========================================
# Configuration Variables
# ==========================================
# Change these placeholders for your automated environments
SUPERVISOR_IP="10.150.4.2" 
USERNAME="administrator@wld.sso"
CONTEXT_NAME="supervisor"

# The specific path to the CLI bundle from your Supervisor UI
VCF_URL_PATH="/wcp/vcf-cli/v9.1.1.0/25662425/linux/amd64/vcf-cli.tar.gz"

echo "================================================="
echo " 1/2: Installing kubectl and VCF CLI"
echo "================================================="

# Install standard kubectl 
echo "-> Downloading latest stable kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
echo "-> kubectl installed successfully."

# Install VCF CLI from the Supervisor Endpoint
echo "-> Downloading VCF CLI from Supervisor (${SUPERVISOR_IP})..."
curl -kLO "https://${SUPERVISOR_IP}${VCF_URL_PATH}"

echo "-> Extracting VCF CLI..."
tar -xzf vcf-cli.tar.gz

# The tarball typically extracts a binary named 'vcf-cli-linux_amd64' or similar.
# This finds the extracted file and installs it as 'vcf'
VCF_BIN=$(find . -maxdepth 1 -type f -name "*vcf*" ! -name "*.tar.gz" | head -n 1)
sudo install -o root -g root -m 0755 "${VCF_BIN}" /usr/local/bin/vcf

# Clean up local directory
rm -f vcf-cli.tar.gz "${VCF_BIN}"
echo "-> VCF CLI installed successfully."

echo ""
echo "================================================="
echo " 2/2: Creating Initial VCF Context"
echo "================================================="
echo "-> Initializing context. The VCF CLI will now securely prompt for your password:"

# Authenticate and generate kubeconfig context
vcf context create "${CONTEXT_NAME}" \
  --endpoint "${SUPERVISOR_IP}" \
  --username "${USERNAME}" \
  --insecure-skip-tls-verify

echo ""
echo "================================================="
echo " Setup Complete!"
echo "================================================="
echo "To verify your active context, run:"
echo "  kubectl config get-contexts"
