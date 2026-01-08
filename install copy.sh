#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Resolve repo root (no hardcoding)
# ----------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${N8NSTACK_DIR:-$SCRIPT_DIR}"

CERT_MANAGER_DIR="${REPO_DIR}/cert-manager"
N8N_DIR="${REPO_DIR}/n8n"
ELK_DIR="${REPO_DIR}/elk"

# ----------------------------
# Resolve “real” user (handles sudo)
# ----------------------------
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  RUN_AS_USER="${SUDO_USER}"
else
  RUN_AS_USER="${USER}"
fi

USER_HOME="$(eval echo "~${RUN_AS_USER}")"

# ----------------------------
# Config
# ----------------------------
KUBECONFIG_SRC="/etc/rancher/k3s/k3s.yaml"
KUBECONFIG_DST="${USER_HOME}/.kube/config"

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.19.2}"
CERT_MANAGER_MANIFEST="https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

# ----------------------------
# Helpers
# ----------------------------
info() { echo -e "\n==> $*"; }

install_curl() {
  if ! command -v curl >/dev/null 2>&1; then
    info "curl not found — installing"
    apt-get update -qq
    apt-get install -y curl
  fi
}

install_helm() {
  if ! command -v helm >/dev/null 2>&1; then
    info "helm not found — installing"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
}

# ----------------------------
# Preflight
# ----------------------------
info "Running preflight checks"

install_curl
install_helm

if [[ ! -d "${CERT_MANAGER_DIR}" ]]; then
  echo "ERROR: cert-manager directory not found: ${CERT_MANAGER_DIR}"
  exit 1
fi

if [[ ! -d "${N8N_DIR}" ]]; then
  echo "ERROR: n8n directory not found: ${N8N_DIR}"
  exit 1
fi

info "Repo dir: ${REPO_DIR}"
info "Running as user: ${RUN_AS_USER}"
info "User home: ${USER_HOME}"

# ----------------------------
# K3s uninstall/install
# ----------------------------
if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
  info "Uninstalling existing K3s"
  /usr/local/bin/k3s-uninstall.sh
else
  info "No existing K3s install detected"
fi

info "Installing K3s"
curl -sfL https://get.k3s.io | sh -

info "Waiting for K3s node to be Ready"
for i in {1..36}; do
  if sudo k3s kubectl get nodes >/dev/null 2>&1; then
    if sudo k3s kubectl get nodes | awk 'NR>1 {print $2}' | grep -q "Ready"; then
      break
    fi
  fi
  sleep 5
done

sudo k3s kubectl get nodes

# ----------------------------
# Kubeconfig permissions (user-aware)
# ----------------------------
info "Configuring kubeconfig for user: ${RUN_AS_USER}"
sudo chmod 644 "${KUBECONFIG_SRC}"
sudo mkdir -p "${USER_HOME}/.kube"
sudo cp -f "${KUBECONFIG_SRC}" "${KUBECONFIG_DST}"
sudo chown -R "${RUN_AS_USER}:${RUN_AS_USER}" "${USER_HOME}/.kube"

# kubectl should now be available via PATH
command -v kubectl >/dev/null 2>&1 || ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

# ----------------------------
# Cert-Manager install
# ----------------------------
info "Installing Cert-Manager ${CERT_MANAGER_VERSION}"
kubectl apply -f "${CERT_MANAGER_MANIFEST}"

info "Waiting for Cert-Manager to become ready"
kubectl wait --namespace cert-manager --for=condition=Available deployment --all --timeout=240s

info "Applying Cert-Manager kustomize"
kubectl apply -k "${CERT_MANAGER_DIR}"

# ----------------------------
# N8N install
# ----------------------------
info "Installing N8N"
kubectl get ns n8n >/dev/null 2>&1 || kubectl create ns n8n

kubectl apply -k "${N8N_DIR}"

info "Patching n8n deployment"
kubectl -n n8n patch deployment n8n --type=json -p='[
  {"op":"add","path":"/spec/template/spec/serviceAccountName","value":"n8n-k8s"},
  {"op":"add","path":"/spec/template/spec/containers/0/env","value":[
    {"name":"K8S_BEARER_TOKEN","valueFrom":{"secretKeyRef":{"name":"n8n-k8s-token","key":"token"}}}
  ]}
]'

# ----------------------------
# ELK install
# ----------------------------
info "Installing ELK stack"
kubectl get ns logging >/dev/null 2>&1 || kubectl create namespace logging

helm repo add elastic https://helm.elastic.co >/dev/null 2>&1 || true
helm repo update

helm upgrade --install elasticsearch elastic/elasticsearch \
  -n logging \
  --set replicas=1

helm upgrade --install kibana elastic/kibana \
  -n logging \
  --set service.type=LoadBalancer

info "Waiting for ELK to become ready"
kubectl wait --namespace logging --for=condition=Available deployment --all --timeout=240s

kubectl apply -k "${ELK_DIR}"

info "ELK credentials"
echo -n "Username: "
kubectl get secrets --namespace=logging elasticsearch-master-credentials \
  -ojsonpath='{.data.username}' | base64 -d
echo

echo -n "Password: "
kubectl get secrets --namespace=logging elasticsearch-master-credentials \
  -ojsonpath='{.data.password}' | base64 -d
echo

# ----------------------------
# Cloudflared Install
# ----------------------------
info "Installing Cloudflared"
sudo apt-get update
sudo apt-get install -y curl gnupg lsb-release
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-main.list
sudo apt-get update
sudo apt-get install -y cloudflared
cloudflared --version


info "Install complete 🎉"
