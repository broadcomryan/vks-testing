#!/bin/bash
set -e

# ==========================================
# Variables
# ==========================================
SUPERVISOR_IP="10.150.4.2"
USERNAME="administrator@wld.sso"
CONTEXT_NAME="supervisor"
CERT_OUTPUT_FILE="supervisor-ca.crt"

echo "-> Logging into Supervisor and building kubeconfig..."

# 1. Authenticate to the Supervisor (This builds/updates ~/.kube/config)
vcf context create "${CONTEXT_NAME}" \
  --endpoint "${SUPERVISOR_IP}" \
  --username "${USERNAME}" \
  --insecure-skip-tls-verify

echo "-> Extracting cluster certificate..."

# 2. Extract the CA certificate from the active kubeconfig context
# --minify ensures we only pull data for the current context we just created
# --raw ensures the certificate data is output in base64 rather than redacted
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "${CERT_OUTPUT_FILE}"

echo "================================================="
echo " Success!"
echo " Kubeconfig Context: ${CONTEXT_NAME} (Active)"
echo " Certificate saved to: ./${CERT_OUTPUT_FILE}"
echo "================================================="
