#!/bin/bash
set -e

echo "================================================="
echo " VCF 9.1 CLI Setup & Context Builder"
echo "================================================="

read -p "Enter Supervisor Endpoint (FQDN or IP): " ENDPOINT
read -p "Enter Username (e.g. administrator@wld.sso): " USERNAME
read -p "Enter a Name for your Supervisor Context (e.g. supervisor): " SUP_CONTEXT
read -p "Enter VCF CLI URL Path (e.g. /wcp/vcf-cli/v9.1.1.0/25662425/linux/amd64/vcf-cli.tar.gz): " VCF_URL_PATH

echo "-> Downloading latest stable kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

echo "-> Downloading VCF CLI from Supervisor..."
curl -kLO "https://${ENDPOINT}${VCF_URL_PATH}"

echo "-> Extracting and installing vcf..."
tar -xzf vcf-cli.tar.gz
VCF_BIN=$(find . -maxdepth 1 -type f -name "*vcf*" ! -name "*.tar.gz" | head -n 1)
sudo install -o root -g root -m 0755 "${VCF_BIN}" /usr/local/bin/vcf
rm -f vcf-cli.tar.gz "${VCF_BIN}"

echo ""
echo "================================================="
echo " Creating Supervisor Context"
echo "================================================="
vcf context create "${SUP_CONTEXT}" \
  --endpoint "${ENDPOINT}" \
  --username "${USERNAME}" \
  --insecure-skip-tls-verify

# ADD THIS LINE to set the current context explicitly
kubectl config use-context "${SUP_CONTEXT}"

echo "-> Downloading cluster certificate directly from Supervisor..."

# Use OpenSSL to download the root certificate chain directly from the endpoint
echo -n | openssl s_client -connect "${ENDPOINT}:443" -showcerts 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "$(pwd)/supervisor-ca.crt"

# Verify the file is not empty before continuing
if [ ! -s "$(pwd)/supervisor-ca.crt" ]; then
    echo "Error: Certificate extraction failed. The file is empty."
    exit 1
fi

echo "-> Certificate saved to $(pwd)/supervisor-ca.crt"
echo ""
echo "================================================="
echo " Guest Cluster Context (Optional)"
echo "================================================="
read -p "Do you want to add a guest cluster context now? (y/n): " ADD_GUEST

if [[ "$ADD_GUEST" =~ ^[Yy]$ ]]; then
    read -p "Enter Guest Cluster Namespace: " NAMESPACE
    read -p "Enter Guest Cluster Name: " CLUSTER_NAME
    read -p "Enter a Name for your Guest Context (e.g. ${CLUSTER_NAME}-admin): " GUEST_CONTEXT
    
    echo "-> Authenticating to Guest Cluster..."
    vcf context create "${GUEST_CONTEXT}" \
      --endpoint "${ENDPOINT}" \
      --username "${USERNAME}" \
      --ca-certificate "$(pwd)/supervisor-ca.crt" \
      --workload-cluster-namespace "${NAMESPACE}" \
      --workload-cluster-name "${CLUSTER_NAME}"
      
    echo "-> Context added. You are now securely connected to ${CLUSTER_NAME}."
else
    echo "-> Setup complete. You are connected to the Supervisor."
fi
