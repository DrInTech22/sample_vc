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
  proxy:
    extraSANs:
    - team-a.aiscaler.ai
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

- Access the vCluster
```sh
export KUBECONFIG=./kubeconfig.yaml

kubectl get ns
kubectl get cluster-info
```

- Delete the vCluster
```sh
vcluster delete team-a -n team-a
kubectl delete ingress team-a-ingress -n team-a
kubectl delete namespace team-a
```

- We have to find a way to automate the deletion of subdomain records after ingresses are deleted.


