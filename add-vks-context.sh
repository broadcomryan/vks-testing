#!/bin/bash
# Exit on any error
set -e

# ==========================================
# Static Environment Variables
# ==========================================
SUPERVISOR_IP="10.150.4.2"
USERNAME="administrator@wld.sso"
CERT_FILE="supervisor-ca.crt"

# ==========================================
# Dynamic Input Variables
# ==========================================
VSPHERE_NAMESPACE=$1
VKS_CLUSTER_NAME=$2

# Input validation
if [ -z "$VSPHERE_NAMESPACE" ] || [ -z "$VKS_CLUSTER_NAME" ]; then
    echo "Error: Missing required arguments."
    echo "Usage: ./add-vks-context.sh <namespace> <cluster-name>"
    echo "Example: ./add-vks-context.sh dev my-new-cluster"
    exit 1
fi

CONTEXT_NAME="${VKS_CLUSTER_NAME}"

echo "================================================="
echo " Creating Context for VKS Cluster: ${VKS_CLUSTER_NAME}"
echo "================================================="

# Ensure the certificate file exists
if [ ! -f "${CERT_FILE}" ]; then
    echo "Error: Certificate file '${CERT_FILE}' not found."
    echo "Please ensure the Supervisor CA cert is in the same directory."
    exit 1
fi

echo "-> Authenticating via vCenter SSO..."
echo "-> The VCF CLI will now securely prompt for your password:"

# Generate the kubeconfig context
vcf context create "${CONTEXT_NAME}" \
  --endpoint "${SUPERVISOR_IP}" \
  --username "${USERNAME}" \
  --insecure-skip-tls-verify \
  #--ca-certificate "${CERT_FILE}" \
  --workload-cluster-namespace "${VSPHERE_NAMESPACE}" \
  --workload-cluster-name "${VKS_CLUSTER_NAME}"

echo ""
echo "================================================="
echo " Context Created Successfully!"
echo "================================================="
echo "To verify and use your new cluster, run:"
echo "  kubectl config use-context ${CONTEXT_NAME}"
echo "  kubectl get nodes"
