#!/bin/bash
set -e

echo "================================================="
echo " VCF 9.0 CLI Setup & Context Builder"
echo "================================================="

read -p "Enter Supervisor Endpoint (FQDN or IP): " ENDPOINT
read -p "Enter Username (e.g. administrator@vsphere.local): " USERNAME

echo "-> Downloading CLI tools from Supervisor: ${ENDPOINT}..."
curl -kLO "https://${ENDPOINT}/wcp/plugin/linux-amd64/vsphere-plugin.zip"

echo "-> Extracting binaries..."
unzip -q vsphere-plugin.zip

echo "-> Installing kubectl and kubectl-vsphere to /usr/local/bin/..."
sudo install -o root -g root -m 0755 bin/kubectl /usr/local/bin/kubectl
sudo install -o root -g root -m 0755 bin/kubectl-vsphere /usr/local/bin/kubectl-vsphere
rm -rf bin/ vsphere-plugin.zip

echo ""
echo "================================================="
echo " Creating Supervisor Context"
echo "================================================="
kubectl-vsphere login \
  --server="${ENDPOINT}" \
  --vsphere-username="${USERNAME}" \
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
    
    echo "-> Authenticating to Guest Cluster..."
    kubectl-vsphere login \
      --server="${ENDPOINT}" \
      --vsphere-username="${USERNAME}" \
      --tanzu-kubernetes-cluster-namespace="${NAMESPACE}" \
      --tanzu-kubernetes-cluster-name="${CLUSTER_NAME}"
      
    echo "-> Context added. Run 'kubectl config get-contexts' to verify."
else
    echo "-> Setup complete. You are connected to the Supervisor."
fi
