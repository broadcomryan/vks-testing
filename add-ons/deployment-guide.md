# Deployment Guide: Contour, Harbor, and Argo CD Supervisor Services

This guide outlines the sequential deployment process for setting up **Contour**, **Harbor**, and **Argo CD** as Supervisor Services in vSphere / VMware Cloud Foundation (VCF) 9.1. Follow the steps in order to satisfy component dependencies.

---

## Prerequisites

- Active administrative access to the vSphere Supervisor Cluster.
- `kubectl` and the vSphere plugin configured with `vSphere Admin` or `Supervisor Admin` privileges.
- Package definition files (`supervisor-service-*.yml`) and customized values files stored locally in your workspace.
- A local DNS server where you can create A records for the Harbor FQDN (`harbor.vcf.lab`).

---

## Step 1: Deploy Contour Supervisor Service

Contour provides Ingress routing and Envoy proxy management for services running on the Supervisor, including Harbor.

### Installation Workflow

#### Option A: Via vSphere Client UI (Recommended)
1. In the vSphere Client, navigate to **Supervisor Management** $\rightarrow$ **Services**.
2. Click **Add New Service** and upload `supervisor-service-contour-legacy-v1.33.5.yml`.
3. Locate the **Contour** tile under **Services**, select **Actions** $\rightarrow$ **Manage Service**, and select your target Supervisor.
4. In the **YAML Service Config** box, paste the contents of `supervisor-service-contour-legacy-data-values-v1.33.5.yml`.
5. Click **Finish**.

#### Option B: Via `kubectl` CLI
Apply the Package manifest directly into the Supervisor Service namespace:

```bash
kubectl apply -f supervisor-service-contour-legacy-v1.33.5.yml
```

### Verification
Verify that the Contour controller and Envoy proxy pods reach the `Running` state before proceeding:

```bash
kubectl get pods -n svc-contour-domain-*
```

Retrieve the Envoy LoadBalancer External IP (needed for DNS configuration in Step 2):

```bash
kubectl get svc envoy -n svc-contour-domain-* -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Contour Customized Values Explained

#### 1. Contour Control Plane Settings
- `contour.useProxyProtocol: false`: Disables the PROXY protocol header requirement on Envoy listeners.
- `contour.replicas: 2`: Deploys 2 Contour control plane pods for high availability.
- `contour.pspNames: ""`: Overrides default Pod Security Policy names to match cluster policy requirements.
- `contour.logLevel: info`: Configures operational log verbosity for Contour to `info`.
- `contour.listenIPFamily: IPv4`: Restricts Contour control plane endpoints (xDS server, health checks, metrics) to IPv4.

#### 2. Envoy Proxy Settings
- `envoy.workload.type: Deployment`: Changes the Envoy deployment model from DaemonSet to a fixed Deployment.
- `envoy.workload.replicas: 2`: Runs 2 instances of the Envoy proxy.
- `envoy.service.type: LoadBalancer`: Exposes Envoy via a vSphere LoadBalancer service to receive external traffic.
- `envoy.service.externalTrafficPolicy: Cluster`: Routes incoming traffic across nodes cluster-wide.
- `envoy.service.disableWait: false`: Keeps standard resource wait logic during deployment.
- `envoy.hostPorts.enable: false`: Disables binding Envoy directly to host node ports 80/443.
- `envoy.hostNetwork: false`: Isolates Envoy pods to the Kubernetes pod network namespace.
- `envoy.terminationGracePeriodSeconds: 300`: Allows Envoy up to 5 minutes to gracefully drain active connections upon termination.
- `envoy.logLevel: info`: Sets logging verbosity for Envoy containers to `info`.
- `envoy.pspNames: ""`: Clears Pod Security Policy overrides for Envoy.
- `envoy.listenIPFamily: IPv4`: Restricts Envoy proxy listeners to IPv4 network stacks.

#### 3. Certificates & RBAC
- `certificates.caDuration: 8760h`: Sets the validity lifetime of the internal CA certificate to 1 year.
- `certificates.caRenewBefore: 720h`: Triggers internal CA certificate renewal 30 days prior to expiration.
- `certificates.leafDuration: 720h`: Sets leaf certificate validity (used for Contour-to-Envoy mTLS) to 30 days.
- `certificates.leafRenewBefore: 360h`: Triggers leaf certificate rotation 15 days before expiration.
- `enableSupervisorServiceRbac: true`: Enables required RBAC rules for Supervisor framework management of Contour CRDs (`HTTPProxy`).

---

## Step 2: Deploy Harbor Supervisor Service

Once Contour is healthy and its LoadBalancer IP is available, proceed with the Harbor deployment. Harbor utilizes Contour `HTTPProxy` Custom Resources for TLS termination and Ingress exposure.

### Pre-Deployment Certificate Preparation

Generate your base64-encoded strings for the custom TLS certificate (`harbor.crt`) and private key (`harbor.key`):

```bash
base64 -w 0 harbor.crt
base64 -w 0 harbor.key
```

Update `supervisor-service-harbor-legacy-custom-values-v2.15.2.yml` with the base64 strings:

```yaml
hostname: harbor.vcf.lab
tlsCertificate:
  tlsSecretLabels: {"managed-by": "vmware-vRegistry"}
  tls.crt: "<BASE64_CERTIFICATE_STRING>"
  tls.key: "<BASE64_PRIVATE_KEY_STRING>"
```

### Installation Workflow

#### Option A: Via vSphere Client UI (Recommended)
1. Go to **Supervisor Management** $\rightarrow$ **Services**.
2. Click **Add New Service** and upload `supervisor-service-harbor-legacy-v2.15.2.yml`.
3. Locate the **Harbor** tile, select **Actions** $\rightarrow$ **Manage Service**, and select your target Supervisor.
4. Paste the complete updated contents of `supervisor-service-harbor-legacy-custom-values-v2.15.2.yml` into **YAML Service Config**.
5. Click **Finish**.

#### Option B: Via `kubectl` CLI

```bash
kubectl apply -f supervisor-service-harbor-legacy-v2.15.2.yml
```

### Post-Deployment Configuration & Network Egress

1. **Configure DNS Mapping:** Map your Harbor domain (`harbor.vcf.lab`) to the Contour/Envoy LoadBalancer External IP retrieved in Step 1:
   ```text
   harbor.vcf.lab  IN  A  <CONTOUR_ENVOY_LOADBALANCER_IP>
   ```

2. **Apply Network Policy for Egress:** Apply an egress `NetworkPolicy` to allow Harbor pods to communicate externally and across namespaces:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-all-egress-harbor-supervisor-service
     namespace: svc-harbor-domain-*
   spec:
     podSelector:
       matchLabels:
         app: harbor
     egress:
       - {}
   ```

### Verification
Confirm all Harbor components (Core, Registry, Jobservice, Database, Redis, Trivy) are fully operational:

```bash
kubectl get pods -n svc-harbor-domain-*
kubectl get httpproxy -n svc-harbor-domain-*
```

### Harbor Customized Values Explained

#### 1. Integration & Networking
- `hostname: harbor.vcf.lab`: Defines the target FQDN for accessing Harbor core and registry endpoints.
- `port.https: 443`: Directs traffic to port 443 on the Envoy/Contour Ingress Controller.
- `tlsCertificate.tlsSecretLabels: {"managed-by": "vmware-vRegistry"}`: Required label applied to generated TLS secrets to enable vSphere Kubernetes Service (VKS) integration and automatic trust injection.
- `enableNginxLoadBalancer: false`: Disables the standalone NGINX Ingress controller option.
- `enableContourHttpProxy: true`: Configures Harbor to generate Contour `HTTPProxy` objects for Ingress routing via Contour.
- `createNetworkPolicy: true`: Enforces namespace isolation via Kubernetes `NetworkPolicy` objects.
- `network.ipFamilies: ["IPv4"]`: Restricts Harbor service communication to IPv4.

#### 2. Service Credentials & Encryption Secrets
- `harborAdminPassword: HarborAdminSec2026!`: Configures the initial password for the default admin account.
- `secretKey: K9m#pL2$vX8qN4wZ`: A 16-character key used for symmetric encryption of sensitive data stored in Harbor.
- `database.password: DbSecretPass2026!`: The administrative password for the bundled PostgreSQL database instance.
- `core.secret: CoreAuthToken2026!`: Auth token enabling core server communication with secondary components.
- `core.xsrfKey: A7k#mP9$vX2qN8wZ3eR6tY1uI4oP0sD5`: A 32-character anti-XSRF token used for web application protection.
- `jobservice.secret: JobAuthToken2026!`: Authentication secret for Jobservice API tasks.
- `registry.secret: RegAuthToken2026!`: Secret key securing image layer upload streams between clients and backend storage.

#### 3. Component Replication & Storage Provisioning
- `core.replicas: 1, jobservice.replicas: 1, registry.replicas: 1`: Deploys single-pod instances for each microservice component.
- `database.type: internal`: Deploys the built-in PostgreSQL database service within the namespace.
- `persistence.persistentVolumeClaim`: Maps component storage requests to the vSphere storage policy `vsan-default-storage-policy` with `ReadWriteOnce` access:
  - **Registry Storage:** `10Gi` (stores container image layers and artifacts).
  - **Jobservice Log Storage:** `1Gi` (stores job execution logs).
  - **Database Storage:** `1Gi` (stores PostgreSQL relational data).
  - **Redis Storage:** `1Gi` (stores cache and job queue state).
  - **Trivy Storage:** `5Gi` (stores vulnerability databases and scanner temp files).

#### 4. Observability & Caching
- `metrics.enabled: true`: Exposes Prometheus metrics endpoints on port 8001 at `/metrics` across core, registry, and exporter services.
- `cache.enabled: false`: Disables the additional intermediate caching layer.

---

## Step 3: Deploy Argo CD Supervisor Service

With both Contour and Harbor deployed and healthy, deploy the Argo CD Supervisor Service.

### Installation Workflow

#### Option A: Via vSphere Client UI (Recommended)
1. Navigate to **Supervisor Management** $\rightarrow$ **Services**.
2. Click **Add New Service** and upload `supervisor-service-argocd-legacy-1.2.0-25642124.yml`.
3. Select **Actions** $\rightarrow$ **Manage Service** and deploy to your target Supervisor.

#### Option B: Via `kubectl` CLI

```bash
kubectl apply -f supervisor-service-argocd-legacy-1.2.0-25642124.yml
```

### Verification
Ensure the Argo CD operator and compatibility API controller are healthy and running:

```bash
kubectl get pods -n svc-argocd-domain-*
```

---

## Final Verification Checklist

Verify overall stack health across all three Supervisor Service namespaces:

```bash
# 1. Verify Contour & Envoy Ingress
kubectl get pods,svc,httpproxy -n svc-contour-domain-*

# 2. Verify Harbor Registry Components & Storage
kubectl get pods,pvc,httpproxy -n svc-harbor-domain-*

# 3. Verify Argo CD Service Operator
kubectl get pods -n svc-argocd-domain-*

# 4. Test Harbor HTTPS Connection
curl -Iv https://harbor.vcf.lab
```
