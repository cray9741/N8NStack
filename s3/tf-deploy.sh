#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Args
# ------------------------------------------------------------
AUTO_APPROVE=false
if [[ "${1:-}" == "--yes" ]]; then
  AUTO_APPROVE=true
fi

# ------------------------------------------------------------
# Config (override via env vars if desired)
# ------------------------------------------------------------
K8S_NAMESPACE="${K8S_NAMESPACE:-n8n}"
AWS_SECRET_NAME="${AWS_SECRET_NAME:-aws-credentials}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PLAN_FILE="${PLAN_FILE:-tfplan}"

# ------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------
for cmd in terraform kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required but not installed."
    exit 1
  fi
done

# Ensure we're in the Terraform directory (current dir)
if ! ls ./*.tf >/dev/null 2>&1; then
  echo "ERROR: No .tf files found in current directory: $(pwd)"
  echo "Run this script from the folder that contains your Terraform files (./s3)."
  exit 1
fi

# Ensure terraform.tfvars exists (explicitly required)
if [[ ! -f "./terraform.tfvars" ]]; then
  echo "ERROR: terraform.tfvars not found in current directory: $(pwd)"
  exit 1
fi

echo "✔ Pre-flight checks passed"
echo "📁 Terraform working dir: $(pwd)"
echo "🧾 Using default tfvars: ./terraform.tfvars"

# ------------------------------------------------------------
# Terraform init + plan
# ------------------------------------------------------------
echo "🚀 Running terraform init..."
terraform init -upgrade

echo "🧾 Running terraform plan..."
terraform plan -out="${PLAN_FILE}"

# ------------------------------------------------------------
# Approval gate
# ------------------------------------------------------------
if [[ "${AUTO_APPROVE}" == "true" ]]; then
  echo "⚠️  --yes supplied; skipping manual approval"
else
  echo
  echo "------------------------------------------------------------"
  echo "Type 'apply' to approve and run terraform apply."
  echo "Anything else will cancel."
  echo "------------------------------------------------------------"
  read -r -p "> " APPROVAL

  if [[ "${APPROVAL}" != "apply" ]]; then
    echo "🛑 Cancelled. No changes applied."
    exit 0
  fi
fi

# ------------------------------------------------------------
# Terraform apply
# ------------------------------------------------------------
echo "✅ Running terraform apply..."
terraform apply -auto-approve "${PLAN_FILE}"

# ------------------------------------------------------------
# Fetch Terraform outputs
# ------------------------------------------------------------
echo "🔐 Fetching outputs from Terraform..."
AWS_ACCESS_KEY_ID="$(terraform output -raw iam_access_key_id)"
AWS_SECRET_ACCESS_KEY="$(terraform output -raw iam_secret_access_key)"
KMS_KEY_ARN="$(terraform output -raw kms_key_arn)"

if [[ -z "${AWS_ACCESS_KEY_ID}" || -z "${AWS_SECRET_ACCESS_KEY}" || -z "${KMS_KEY_ARN}" ]]; then
  echo "ERROR: Missing one or more required Terraform outputs:"
  echo "  - iam_access_key_id"
  echo "  - iam_secret_access_key"
  echo "  - kms_key_arn"
  exit 1
fi

# ------------------------------------------------------------
# Ensure namespace exists
# ------------------------------------------------------------
if ! kubectl get namespace "${K8S_NAMESPACE}" >/dev/null 2>&1; then
  echo "📦 Creating namespace '${K8S_NAMESPACE}'..."
  kubectl create namespace "${K8S_NAMESPACE}"
fi

# ------------------------------------------------------------
# Create or update Kubernetes secret
# ------------------------------------------------------------
echo "🔑 Creating/updating Kubernetes secret '${AWS_SECRET_NAME}' in '${K8S_NAMESPACE}'..."

kubectl -n "${K8S_NAMESPACE}" create secret generic "${AWS_SECRET_NAME}" \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
  --from-literal=AWS_DEFAULT_REGION="${AWS_REGION}" \
  --from-literal=KMS_KEY_ARN="${KMS_KEY_ARN}" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF

🎉 Done.

Terraform:
  - tfvars: ./terraform.tfvars
  - plan:   ./${PLAN_FILE}
  - mode:   $( [[ "${AUTO_APPROVE}" == "true" ]] && echo "auto-apply (--yes)" || echo "interactive" )

Kubernetes secret:
  - ${K8S_NAMESPACE}/${AWS_SECRET_NAME}
  - keys: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION, KMS_KEY_ARN

EOF
