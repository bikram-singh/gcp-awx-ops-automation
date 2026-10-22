#!/usr/bin/env bash
# One-time bootstrap: Terraform state bucket, deployer service account and
# Workload Identity Federation (keyless auth) for GitHub Actions.
#
# Usage:
#   export PROJECT_ID=your-project-id
#   export GITHUB_REPO=owner/repo
#   ./scripts/bootstrap.sh
#
# Optional overrides: REGION, STATE_BUCKET, POOL_ID, PROVIDER_ID, DEPLOYER_SA_NAME
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID}"
: "${GITHUB_REPO:?Set GITHUB_REPO as owner/repo}"

REGION="${REGION:-asia-south1}"
STATE_BUCKET="${STATE_BUCKET:-${PROJECT_ID}-tfstate}"
POOL_ID="${POOL_ID:-github-pool}"
PROVIDER_ID="${PROVIDER_ID:-github-provider}"
DEPLOYER_SA_NAME="${DEPLOYER_SA_NAME:-tf-deployer}"
DEPLOYER_SA="${DEPLOYER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo ">> Using project ${PROJECT_ID}, repo ${GITHUB_REPO}"
gcloud config set project "${PROJECT_ID}" >/dev/null
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"

echo ">> Enabling bootstrap APIs"
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  sts.googleapis.com \
  storage.googleapis.com

echo ">> Creating Terraform state bucket gs://${STATE_BUCKET}"
if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi
gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning

echo ">> Creating deployer service account ${DEPLOYER_SA}"
if ! gcloud iam service-accounts describe "${DEPLOYER_SA}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${DEPLOYER_SA_NAME}" \
    --display-name="Terraform deployer (GitHub Actions)"
fi

# Lab-friendly role set. Tighten or split per stack for production.
ROLES=(
  roles/compute.admin
  roles/container.admin
  roles/cloudsql.admin
  roles/secretmanager.admin
  roles/iam.serviceAccountAdmin
  roles/iam.serviceAccountUser
  roles/resourcemanager.projectIamAdmin
  roles/servicenetworking.networksAdmin
  roles/serviceusage.serviceUsageAdmin
  roles/pubsub.admin
  roles/monitoring.admin
  roles/logging.admin
  roles/artifactregistry.admin
)
for role in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${DEPLOYER_SA}" \
    --role="${role}" \
    --condition=None >/dev/null
done

gcloud storage buckets add-iam-policy-binding "gs://${STATE_BUCKET}" \
  --member="serviceAccount:${DEPLOYER_SA}" \
  --role="roles/storage.objectAdmin" >/dev/null

echo ">> Creating Workload Identity pool and GitHub provider"
if ! gcloud iam workload-identity-pools describe "${POOL_ID}" --location=global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "${POOL_ID}" \
    --location=global \
    --display-name="GitHub Actions"
fi

if ! gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
  --location=global --workload-identity-pool="${POOL_ID}" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
    --location=global \
    --workload-identity-pool="${POOL_ID}" \
    --display-name="GitHub OIDC" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository=='${GITHUB_REPO}'"
fi

echo ">> Allowing the repo to impersonate the deployer service account"
gcloud iam service-accounts add-iam-policy-binding "${DEPLOYER_SA}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}" >/dev/null

WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

cat <<EOF

=====================================================================
Bootstrap complete. Add these as GitHub repository VARIABLES
(Settings > Secrets and variables > Actions > Variables):

  GCP_PROJECT_ID    = ${PROJECT_ID}
  GCP_WIF_PROVIDER  = ${WIF_PROVIDER}
  GCP_DEPLOYER_SA   = ${DEPLOYER_SA}
  TF_STATE_BUCKET   = ${STATE_BUCKET}

Also create a GitHub Environment named "production" with required
reviewers; the apply job waits for approval there.
=====================================================================
EOF
