# Deployment Guide: Contour, Harbor, and ArgoCD Add-ons

This README outlines the sequential deployment process for setting up **Contour**, **Harbor**, and **ArgoCD** as Supervisor Services. Follow the steps in order to ensure dependencies are properly satisfied.

---

## Prerequisites

* Active access to the vSphere Supervisor Cluster.
* `kubectl` configured with administrative privileges.
* The package manifests and data values YAML files stored locally in your deployment directory.

---

## Step 1: Deploy Contour

Contour provides Ingress routing and Envoy proxy management for services running on the Supervisor, including Harbor.

### Installation Steps

1. Apply the Contour Supervisor Service Package:
   ```bash
   kubectl apply -f supervisor-service-contour-legacy-v1.33.5.yml
   ```

2. Apply the custom data values configuration:
   ```bash
   kubectl apply -f supervisor-service-contour-legacy-data-values-v1.33.5.yml
   ```

3. Verify that the Contour controller and Envoy proxy pods are in `Running` state before moving to Step 2:
   ```bash
   kubectl get pods -n tanzu-system-ingress
   ```

---

### Contour Customized Values Explained

Below is the detailed breakdown of the values configured in `supervisor-service-contour-legacy-data-values-v1.33.5.yml`:

#### 1. Contour Control Plane Settings
* **`contour.useProxyProtocol: false`**: Disables the PROXY protocol header requirement on Envoy listeners.
* **`contour.replicas: 2`**: Deploys 2 Contour control plane pods for high availability.
* **`contour.pspNames: ""`**: Overrides default Pod Security Policy names to match cluster policy requirements.
* **`contour.logLevel: info`**: Configures operational log verbosity for Contour to `info`.
* **`contour.listenIPFamily: IPv4`**: Restricts Contour's control plane endpoints (xDS server, health checks, and metrics) to IPv4.

#### 2. Envoy Proxy Settings
* **`envoy.workload.type: Deployment`**: Changes the Envoy deployment model from the default `DaemonSet` to a fixed Kubernetes `Deployment`.
* **`envoy.workload.replicas: 2`**: Runs 2 instances of the Envoy proxy.
* **`envoy.service.type: LoadBalancer`**: Exposes Envoy via a cloud/vSphere LoadBalancer service to receive external traffic.
* **`envoy.service.externalTrafficPolicy: Cluster`**: Routes incoming traffic across nodes cluster-wide.
* **`envoy.service.disableWait: false`**: Keeps standard resource wait logic during deployment.
* **`envoy.hostPorts.enable: false`**: Disables binding Envoy directly to ports 80/443 on the underlying host node network.
* **`envoy.hostNetwork: false`**: Isolates Envoy pods to the Kubernetes pod network namespace rather than host networking.
* **`envoy.terminationGracePeriodSeconds: 300`**: Allows Envoy up to 5 minutes to gracefully drain active client connections during pod termination.
* **`envoy.logLevel: info`**: Sets logging verbosity for Envoy containers to `info`.
* **`envoy.pspNames: ""`**: Clears Pod Security Policy overrides for Envoy.
* **`envoy.listenIPFamily: IPv4`**: Restricts Envoy proxy listeners exclusively to IPv4 network stacks.

#### 3. Certificates & RBAC
* **`certificates.caDuration: 8760h`**: Sets the valid lifetime of the internal CA certificate to 1 year (8,760 hours).
* **`certificates.caRenewBefore: 720h`**: Triggers internal CA certificate renewal 30 days (720 hours) prior to expiration.
* **`certificates.leafDuration: 720h`**: Sets leaf certificate validity (used for Contour-to-Envoy mTLS) to 30 days (720 hours).
* **`certificates.leafRenewBefore: 360h`**: Triggers leaf certificate rotation 15 days (360 hours) before expiration.
* **`enableSupervisorServiceRbac: true`**: Enables required RBAC rules allowing Supervisor framework management of Contour CRDs (e.g., `HTTPProxy`).

---

## Step 2: Deploy Harbor

Once Contour is healthy and active on the Supervisor, proceed with the Harbor deployment. Harbor utilizes Contour `HTTPProxy` CRDs for secure endpoint exposure.

### Installation Steps

1. Apply the Harbor Supervisor Service Package:
   ```bash
   kubectl apply -f supervisor-service-harbor-legacy-v2.15.2.yml
   ```

2. Apply the custom data values configuration:
   ```bash
   kubectl apply -f supervisor-service-harbor-legacy-custom-values-v2.15.2.yml
   ```

3. Confirm all Harbor components (Core, Registry, Jobservice, Database, Redis, Trivy) are fully operational:
   ```bash
   kubectl get pods -n tanzu-system-registry
   ```

---

### Harbor Customized Values Explained

Below is the detailed breakdown of the custom values defined in `supervisor-service-harbor-legacy-custom-values-v2.15.2.yml`:

#### 1. Integration & Networking
* **`hostname: depot.kube-system.svc`**: Defines the target cluster-internal FQDN used for accessing the Harbor core and registry endpoints.
* **`port.https: 443`**: Directs traffic to port 443 on the Envoy/Contour Ingress Controller.
* **`tlsCertificate.tlsSecretLabels: {"managed-by": "vmware-vRegistry"}`**: Mandated label applied to generated TLS secrets to enable vSphere Kubernetes Service (VKS) integration.
* **`enableNginxLoadBalancer: false`**: Disables the standalone NGINX Ingress controller option.
* **`enableContourHttpProxy: true`**: Configures Harbor to generate Contour `HTTPProxy` objects for ingress routing via Contour.
* **`createNetworkPolicy: true`**: Enforces namespace isolation via Kubernetes `NetworkPolicy` objects (mandatory for Supervisor Services).
* **`network.ipFamilies: ["IPv4"]`**: Restricts Harbor service communication to IPv4.

#### 2. Service Credentials & Encryption Secrets
* **`harborAdminPassword: HarborAdminSec2026!`**: Configures the initial password for the default `admin` account.
* **`secretKey: K9m#pL2$vX8qN4wZ`**: A 16-character key used for symmetric encryption of sensitive data stored in Harbor.
* **`database.password: DbSecretPass2026!`**: The root administrative password for the bundled PostgreSQL database instance.
* **`core.secret: CoreAuthToken2026!`**: Auth token enabling core server communication with secondary components.
* **`core.xsrfKey: A7k#mP9$vX2qN8wZ3eR6tY1uI4oP0sD5`**: A 32-character anti-XSRF token used for web application protection.
* **`jobservice.secret: JobAuthToken2026!`**: Authentication secret for Jobservice API tasks.
* **`registry.secret: RegAuthToken2026!`**: Secret key securing image layer upload streams between clients and backend storage.

#### 3. Component Replication & Storage Provisioning
* **`core.replicas: 1`**, **`jobservice.replicas: 1`**, **`registry.replicas: 1`**: Runs single-pod deployments for each core microservice component.
* **`database.type: internal`**: Deploys the built-in PostgreSQL database service within the namespace.
* **`persistence.persistentVolumeClaim`**: Maps component storage requests to the vSphere storage policy `vsan-default-storage-policy` with `ReadWriteOnce` access:
  * **Registry Storage**: `10Gi` (stores container image layers and artifacts).
  * **Jobservice Log Storage**: `1Gi` (stores job execution logs).
  * **Database Storage**: `1Gi` (stores PostgreSQL relational data).
  * **Redis Storage**: `1Gi` (stores cache and job queue state).
  * **Trivy Storage**: `5Gi` (stores vulnerability databases and scanner temp files).

#### 4. Observability & Caching
* **`metrics.enabled: true`**: Exposes Prometheus metrics endpoints on port `8001` at `/metrics` across the `core`, `registry`, and `exporter` services.
* **`cache.enabled: false`**: Disables the additional intermediate caching layer.

---

## Step 3: Deploy ArgoCD Add-on

With both Contour and Harbor deployed and healthy, deploy the ArgoCD Service.

### Installation Steps

1. Apply the ArgoCD Supervisor Service Package manifest:
   ```bash
   kubectl apply -f supervisor-service-argocd-legacy-1.2.0-25642124.yml
   ```

2. Validate the deployment status:
   ```bash
   kubectl get pods -n argocd-service
   ```

3. Ensure both the `argocd-service` manager controller and the `compatibility-api` endpoints are healthy and running.

---

## Final Verification Checklist

Verify overall stack health across all three namespaces:

```bash
# 1. Verify Contour & Envoy Ingress
kubectl get pods,svc,httpproxy -n tanzu-system-ingress

# 2. Verify Harbor Registry Components
kubectl get pods,pvc -n tanzu-system-registry

# 3. Verify ArgoCD Service Manager
kubectl get pods -n argocd-service
```
