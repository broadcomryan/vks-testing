#!/bin/bash
set -e

VSPHERE_NAMESPACE="dev"
GUEST_CONTEXT_NAME="dev-context:dev" # Ensure this matches your kubeconfig context name

# Run 'kubectl get argocdversion' on your Supervisor to verify this string
ARGOCD_VERSION="3.4.4+vmware.1-vks.1" 

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
kubectl config use-context supervisor

# Check if the ArgoCD instance exists; if not, create it
if ! kubectl get argocd argocd -n ${VSPHERE_NAMESPACE} &>/dev/null; then
    echo "-> Deploying Argo CD Instance to namespace '${VSPHERE_NAMESPACE}'..."
    cat <<EOF | kubectl apply -f -
apiVersion: argocd-service.vsphere.vmware.com/v1alpha1
kind: ArgoCD
metadata:
  name: argocd
  namespace: ${VSPHERE_NAMESPACE}
spec:
  version: "${ARGOCD_VERSION}"
EOF
else
    echo "-> Argo CD instance already exists in '${VSPHERE_NAMESPACE}'."
fi

echo "-> Waiting for NSX to assign a LoadBalancer IP (this can take a few minutes)..."
ARGOCD_IP=""
while [ -z "$ARGOCD_IP" ]; do
    sleep 5
    # Suppress errors while waiting for the service/IP to populate
    ARGOCD_IP=$(kubectl get svc argocd-server -n ${VSPHERE_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    echo -n "."
done

echo ""
echo "-> Argo CD is successfully running at: https://${ARGOCD_IP}"

# ==========================================
# ADD THESE NEW WAIT LOOPS HERE
# ==========================================
echo "-> Waiting for the Argo CD admin secret to be generated..."
while ! kubectl get secret argocd-initial-admin-secret -n ${VSPHERE_NAMESPACE} &>/dev/null; do
    sleep 5
    echo -n "."
done
echo " Secret generated!"

echo "-> Waiting for Argo CD server to come online..."
kubectl wait --for=condition=available deployment/argocd-server -n ${VSPHERE_NAMESPACE} --timeout=300s

echo ""
echo "================================================="
echo " 3. Authenticating and Registering Cluster"
echo "================================================="
# Fetch the auto-generated admin password
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n ${VSPHERE_NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)

echo "-> Logging into Argo CD CLI..."
argocd login ${ARGOCD_IP} --username admin --password "${ARGOCD_PASSWORD}" --insecure

echo "-> Adding the '${GUEST_CONTEXT_NAME}' cluster to Argo CD..."
argocd cluster add ${GUEST_CONTEXT_NAME} \
  --namespace ${VSPHERE_NAMESPACE} \
  --name dev \
  --yes

echo "-> Setup complete! Your 'dev' cluster is now managed by Argo CD."
