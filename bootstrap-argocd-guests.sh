#!/bin/bash
set -e

# Prompt for inputs
read -p "Enter the Supervisor context name (e.g., supervisor): " SUPERVISOR_CONTEXT
read -p "Enter the vSphere namespace for Argo CD (e.g., argo-instance): " VSPHERE_NAMESPACE
read -p "Enter the Argo CD custom resource name (e.g., argocd): " ARGOCD_CR_NAME
read -p "Enter the Argo CD package version (e.g., 3.4.4+vmware.1-vks.1): " ARGOCD_VERSION
read -p "Enter the guest cluster kubeconfig context name (e.g., dev-guest:dev): " GUEST_CONTEXT_NAME
read -p "Enter the registered cluster name for Argo CD (e.g., olaf, dev, argocd-instance): " ARGO_CLUSTER_NAME

# Validate inputs
if [ -z "$SUPERVISOR_CONTEXT" ] || [ -z "$VSPHERE_NAMESPACE" ] || [ -z "$ARGOCD_CR_NAME" ] || [ -z "$ARGOCD_VERSION" ] || [ -z "$GUEST_CONTEXT_NAME" ] || [ -z "$ARGO_CLUSTER_NAME" ]; then
    echo "Error: All prompts require a non-empty value."
    exit 1
fi

echo "================================================="
echo " 1. Installing Argo CD CLI"
echo "================================================="
if ! command -v argocd &> /dev/null; then
    echo "-> Downloading CLI..."
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo install -o root -g root -m 0755 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
    echo "-> Argo CD CLI installed."
else
    echo "-> Argo CD CLI is already installed."
fi

echo ""
echo "================================================="
echo " 2. Deploying Argo CD Instance"
echo "================================================="
# Ensure we are operating against the Supervisor
kubectl config use-context "${SUPERVISOR_CONTEXT}"

# Check if the ArgoCD instance exists; if not, create it
if ! kubectl get argocd "${ARGOCD_CR_NAME}" -n "${VSPHERE_NAMESPACE}" &>/dev/null; then
    echo "-> Deploying Argo CD Instance '${ARGOCD_CR_NAME}' to namespace '${VSPHERE_NAMESPACE}'..."
    cat <<EOF | kubectl apply -f -
apiVersion: argocd-service.vsphere.vmware.com/v1alpha1
kind: ArgoCD
metadata:
  name: ${ARGOCD_CR_NAME}
  namespace: ${VSPHERE_NAMESPACE}
spec:
  version: "${ARGOCD_VERSION}"
EOF
else
    echo "-> Argo CD instance '${ARGOCD_CR_NAME}' already exists in '${VSPHERE_NAMESPACE}'."
fi

echo "-> Waiting for NSX to assign a LoadBalancer IP (this can take a few minutes)..."
ARGOCD_IP=""
while [ -z "$ARGOCD_IP" ]; do
    sleep 5
    ARGOCD_IP=$(kubectl get svc "${ARGOCD_CR_NAME}-server" -n "${VSPHERE_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    echo -n "."
done

echo ""
echo "-> Argo CD is successfully running at: https://${ARGOCD_IP}"

echo "-> Waiting for the Argo CD admin secret to be generated..."
while ! kubectl get secret "${ARGOCD_CR_NAME}-initial-admin-secret" -n "${VSPHERE_NAMESPACE}" &>/dev/null; do
    sleep 5
    echo -n "."
done
echo " Secret generated!"

echo "-> Waiting for Argo CD server to come online..."
kubectl wait --for=condition=available deployment/"${ARGOCD_CR_NAME}-server" -n "${VSPHERE_NAMESPACE}" --timeout=300s

echo ""
echo "================================================="
echo " 3. Authenticating and Registering Cluster"
echo "================================================="
# Fetch the auto-generated admin password
ARGOCD_PASSWORD=$(kubectl get secret "${ARGOCD_CR_NAME}-initial-admin-secret" -n "${VSPHERE_NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

echo "-> Logging into Argo CD CLI..."
argocd login "${ARGOCD_IP}" --username admin --password "${ARGOCD_PASSWORD}" --insecure

echo "-> Adding the '${GUEST_CONTEXT_NAME}' cluster to Argo CD as '${ARGO_CLUSTER_NAME}'..."
argocd cluster add "${GUEST_CONTEXT_NAME}" \
  --name "${ARGO_CLUSTER_NAME}" \
  --yes

echo "-> Setup complete! Cluster '${ARGO_CLUSTER_NAME}' is now managed by Argo CD."
