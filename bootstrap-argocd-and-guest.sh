#!/bin/bash
set -e

# Variables (Matches your environment based on earlier steps)
VSPHERE_NAMESPACE="dev"
GUEST_CONTEXT_NAME="dev-context" # Or whatever you named the context in the previous script

echo "================================================="
echo " 1. Installing Argo CD CLI"
echo "================================================="
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -o root -g root -m 0755 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
echo "-> Argo CD CLI installed successfully."

echo ""
echo "================================================="
echo " 2. Authenticating to Argo CD Server"
echo "================================================="
# Ensure you are pointing at the Supervisor context to fetch the Argo CD secrets
kubectl config use-context supervisor

# Fetch the LoadBalancer IP and auto-generated admin password
ARGOCD_IP=$(kubectl get svc argocd-server -n ${VSPHERE_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n ${VSPHERE_NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)

echo "-> Argo CD is available at: https://${ARGOCD_IP}"
echo "-> Logging in..."

# Log the CLI into the Argo CD instance
argocd login ${ARGOCD_IP} --username admin --password "${ARGOCD_PASSWORD}" --insecure

echo ""
echo "================================================="
echo " 3. Registering the Guest Cluster"
echo "================================================="
echo "-> Adding the '${GUEST_CONTEXT_NAME}' cluster to Argo CD..."

# Use the guest cluster context we built earlier to register it with Argo CD
argocd cluster add ${GUEST_CONTEXT_NAME} \
  --namespace ${VSPHERE_NAMESPACE} \
  --name dev \
  --yes

echo "-> Setup complete! Your 'dev' cluster is now registered."
