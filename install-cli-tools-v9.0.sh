#!/bin/bash
# Exit on any error
set -e

# Define versions (Update VCF_CLI_VERSION as needed; v9.1.0 is current for VCF 9.1; this is for v9.0)
# Need to update this script to get latest version of VCF CLI
VCF_CLI_VERSION="v9.0.2"
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

echo "================================================="
echo " 1/2: Installing kubectl and VCF CLI"
echo "================================================="

# Install kubectl
echo "-> Downloading kubectl ${KUBECTL_VERSION}..."
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
echo "-> kubectl installed successfully."

# Install VCF CLI
echo "-> Downloading VCF CLI ${VCF_CLI_VERSION}..."
VCF_CLI_URL="https://packages.broadcom.com/artifactory/vcf-distro/vcf-cli/linux/amd64/${VCF_CLI_VERSION}/vcf-cli.tar.gz"
curl -LO "${VCF_CLI_URL}"

echo "-> Extracting VCF CLI..."
tar -xzf vcf-cli.tar.gz

echo "-> Installing VCF CLI to /usr/local/bin/vcf..."
sudo install -o root -g root -m 0755 vcf-cli-linux_amd64 /usr/local/bin/vcf
rm vcf-cli.tar.gz vcf-cli-linux_amd64
echo "-> VCF CLI installed successfully."


echo ""
echo "================================================="
echo " 2/2: Creating Initial VCF Context"
echo "================================================="

# Streamlined prompt for environment specifics
read -p "Enter Supervisor Endpoint (FQDN or IP): " ENDPOINT
read -p "Enter Username (e.g. administrator@vsphere.local): " USERNAME
read -p "Enter a Context Name (e.g. vcf-cluster): " CONTEXT_NAME

echo ""
echo "-> Initializing context. The VCF CLI will now securely prompt for your password:"

# Authenticate and generate kubeconfig context. 
# --insecure-skip-tls-verify is included for lab environments without trusted certs; 
# remove it if you have valid CA certificates installed.
vcf context create "${CONTEXT_NAME}" \
  --endpoint "${ENDPOINT}" \
  --username "${USERNAME}" \
  --insecure-skip-tls-verify

echo ""
echo "================================================="
echo " Setup Complete!"
echo "================================================="
echo "To verify your active context, run:"
echo "  kubectl config get-contexts"
echo "  kubectl get namespaces"
