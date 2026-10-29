#!/bin/bash
set -e

echo "================================================="
echo " VCF 9.1 CLI Setup & Context Builder"
echo "================================================="

read -p "Enter Supervisor Endpoint (FQDN or IP): " ENDPOINT
read -p "Enter Username (e.g. administrator@vsphere.local): " USERNAME
read -p "Enter a Name for your Supervisor Context (e.g. supervisor): " SUP_CONTEXT

echo "-> Downloading latest stable kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

echo "-> Downloading VCF CLI from Supervisor..."
curl -kLO "https://${ENDPOINT}/wcp/plugin/linux-amd64/vsphere-plugin.zip"

echo "-> Extracting and installing vcf..."
unzip -q vsphere-plugin.zip
sudo install -o root -g root -m 0755 bin/vcf /usr/local/bin/vcf
rm -rf bin/ vsphere-plugin.zip

echo ""
echo "================================================="
echo " Creating Supervisor Context"
echo "================================================="
vcf context create "${SUP_CONTEXT}" \
  --endpoint "${ENDPOINT}" \
  --username "${USERNAME}" \
  --insecure-skip-tls-verify

echo "-> Extracting cluster certificate..."
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$(pwd)/supervisor-ca.crt"
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
