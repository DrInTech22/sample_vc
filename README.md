# Yamify vCluster Setup
This repository uses terraform to setup Google Kubernetes engine (GKE) cluster and deploy vclusters on it.

## Access the cluster
- set up gcloud cli
```sh
  gcloud components install gke-gcloud-auth-plugin
  gcloud config set project yamifystaging
```

- Deploy the cluster
```sh
  terraform init
  terraform plan
  terraform apply
```
- Generate the kubeconfig for authentication
```sh
  gcloud container clusters get-credentials private-gke-cluster  --region=us-central1
```

- External access is granted to the private cluster via `master_authorized_networks` in gke module

## Install VCluster
- Install vcluster cli on your machine to interact with the vclusters.
```sh
curl -L -o vcluster "https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64" && \
sudo install -c -m 0755 vcluster /usr/local/bin && \
rm -f vcluster
```

- The vcluster is created in the cluster via terraform. Pass inputs into `vclusters` variable

## Setting Up Nginx ingress controller
```
module "nginx-controller" {
  source     = "terraform-iaac/nginx-controller/helm"
  version    = "2.3.0"  
  depends_on = [module.gke]
  ip_address = google_compute_address.ingress_ip_address.address
}
```
The above deploys the ingress controller as `daemonset` but doesn't include the `--enable-ssl-passthrough` flag which is needed for SSL termination at the host cluster/vcluster level.

The helm ingress setup includes the flag but set up the controller as a `deployment`.

## How to Create VCluster
- Decide the name of your vcluster (e.g team-a)
Note: The vcluster name must match the format of accepted subdomain name. This is because the vcluster name is used to create a subddomain for the vcluster ingress.

- Create a namespace
```sh
kubectl create namespace team-a
```

- Create an ingress in that namespace
```sh
kubectl apply -f - <<-EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    external-dns.alpha.kubernetes.io/hostname: team-a.aiscaler.ai
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  name: team-a-ingress
  namespace: team-a
spec:
  ingressClassName: nginx 
  tls:
  - hosts:
    - team-a.aiscaler.ai
    secretName: team-a-tls-cert
  rules:
  - host: team-a.aiscaler.ai
    http:
      paths:
      - backend:
          service:
            name: team-a
            port:
              number: 443
        path: /
        pathType: ImplementationSpecific
EOF
```

- create values.yaml for VCluster
```sh
cat <<EOF > values.yaml
controlPlane:
  ingress:
    enabled: false # manually created
  proxy:
    extraSANs:
    - team-a.aiscaler.ai
sync:
  toHost:
    ingresses:
      enabled: true 

  fromHost:
    ingressClasses:
      enabled: true 
EOF
```

- create the vcluster
```sh
vcluster create team-a -n team-a --connect=false -f values.yaml
```

- Retrieve the kubeconfig
```sh
vcluster connect team-a -n team-a --print --server=https://team-a.aiscaler.ai > kubeconfig.yaml
```

- Running Commands on the vCluster Without Entering Its Context
```sh
kubectl --kubeconfig=./kubeconfig.yaml get pods
```

- Access the vCluster via its kubeconfig context
```sh
export KUBECONFIG=./kubeconfig.yaml

kubectl get ns
kubectl get cluster-info
```

- Exit the vCluster and return to host cluster
```
unset KUBECONFIG
```

- Delete the vCluster
```sh
vcluster delete team-a -n team-a
kubectl delete ingress team-a-ingress -n team-a
kubectl delete namespace team-a
```

- We have to find a way to automate the deletion of subdomain records after ingresses are deleted.


## Set Up Code Server
```sh
# Add Nicholas Wilde Helm repository
helm repo add nicholaswilde https://nicholaswilde.github.io/helm-charts/
helm repo update

# Create a values.yaml file for Code Server configuration
cat > codeserver-values.yaml << 'EOF'
# Container image configuration
image:
  repository: ghcr.io/linuxserver/code-server
  pullPolicy: IfNotPresent
  tag: "latest"  # Use the latest tag or specify a version

# Basic auth credentials - set a password for code-server
secret:
  PASSWORD: "changeme"  # Please change this to a secure password

# Environment variables for the container
env:
  TZ: "UTC"
  PUID: "1000"  # String value to avoid type issues
  PGID: "1000"  # String value to avoid type issues

# Service configuration
service:
  port:
    port: 8443

# Ingress configuration
ingress:
  enabled: true
  ingressClassName: "nginx"  # Using the proper field instead of the annotation
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    # nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    kubernetes.io/ingress.class: nginx
    external-dns.alpha.kubernetes.io/hostname: codeserver-1.aiscaler.ai
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: "codeserver-1.aiscaler.ai"
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: codeserver-1-tls-cert
      hosts:
        - codeserver-1.aiscaler.ai

# Persistence configuration for saving code and settings
persistence:
  config:
    enabled: true
    emptyDir: false
    mountPath: /config
    # You can specify a storageClass or use the default
    # storageClass: ""
    accessMode: ReadWriteOnce
    size: 10Gi
EOF

# Create a namespace for Code Server
kubectl create namespace codeserver-1

# Get chart details to ensure compatibility
# helm show values nicholaswilde/code-server > chart-values.yaml
# echo "Chart values have been saved to chart-values.yaml for reference"

# Install Code Server using Helm with version specified to ensure compatibility
helm install codeserver nicholaswilde/code-server --namespace codeserver-1 -f codeserver-values.yaml --debug

# Wait for Code Server to be ready
echo "Waiting for Code Server deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/codeserver -n codeserver-1

# Access Code Server at: https://codeserver.aiscaler.ai
echo "Access Code Server at: https://codeserver-1.aiscaler.ai"
echo "Default password: changeme (Please change this as soon as possible)"
```

## Uninstall Code Server
```sh
# Uninstall commands for Code Server
echo "=== Uninstall Code Server ==="
helm uninstall codeserver -n codeserver-1
kubectl delete namespace codeserver-1
# Remove any persistent volumes if needed (optional)
# kubectl get pv | grep codeserver | awk '{print $1}' | xargs kubectl delete pv
kubectl delete secret codeserver-1-tls-cert --ignore-not-found
helm repo remove nicholaswilde
echo "Code Server has been completely uninstalled."
```

## Set up ArgoCD
```sh
# Add ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Create a values.yaml file for ArgoCD configuration
cat > argocd-values.yaml << 'EOF'
server:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
      # nginx.ingress.kubernetes.io/ssl-passthrough: "true"
      external-dns.alpha.kubernetes.io/hostname: argocd.aiscaler.ai
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
    hosts:
      - argocd.aiscaler.ai
    tls:
      - hosts:
          - argocd.aiscaler.ai
        secretName: argocd-server-tls
  extraArgs:
    - --insecure # Required when terminating TLS at the ingress level
global:
  domain: argocd.aiscaler.ai
EOF

# Create a namespace for ArgoCD
kubectl create namespace argocd

# Install ArgoCD using Helm
helm install argocd argo/argo-cd --namespace argocd -f argocd-values.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get the initial admin password (you should change this after logging in)
echo "Initial ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# Access ArgoCD at: https://argocd.aiscaler.ai
echo "Access ArgoCD at: https://argocd.aiscaler.ai"
echo "Username: admin"
```

## Uninstall ArgoCD
```sh
# Uninstall commands for ArgoCD
echo "=== Uninstall ArgoCD ==="
helm uninstall argocd -n argocd
kubectl delete secret argocd-server-tls --ignore-not-found
helm repo remove argo
echo "ArgoCD has been completely uninstalled."
```
