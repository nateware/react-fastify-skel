#!/usr/bin/env bash
#
# GCP project setup for react-fastify-skel.
# Idempotent — safe to re-run.
#
# Usage:
#   1. Fill in the configuration variables below
#   2. chmod +x scripts/gcp_setup.sh
#   3. ./scripts/gcp_setup.sh init          # shared resources (once)
#   4. ./scripts/gcp_setup.sh staging       # per-environment
#   5. ./scripts/gcp_setup.sh production    # per-environment
#
# After running, configure the printed values as GitHub Variables:
#   Repo → Settings → Secrets and variables → Actions → Variables
#   Repo → Settings → Environments → <env> → Add variable
#
set -euo pipefail

# ─── Configuration (edit these) ───────────────────────────────
PROJECT_ID="your-gcp-project-id"
REGION="us-central1"
GITHUB_ORG="your-github-org"    # or personal username
GITHUB_REPO="react-fastify-skel"
DOMAIN_STAGING=""                # optional: e.g. staging.myapp.example.com
DOMAIN_PRODUCTION=""             # optional: e.g. myapp.example.com
# ──────────────────────────────────────────────────────────────

SA_NAME="github-deploy"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
WIF_POOL="github-pool"
WIF_PROVIDER="github-provider"
AR_REPO="docker"

MODE="${1:?Usage: $0 <init|staging|production>}"

case "$MODE" in
  init|staging|production) ;;
  *) echo "Error: argument must be 'init', 'staging', or 'production'"; exit 1 ;;
esac

echo "==> Setting project to ${PROJECT_ID}"
gcloud config set project "$PROJECT_ID"

# ═══════════════════════════════════════════════════════════════
# init — shared resources (run once)
# ═══════════════════════════════════════════════════════════════
if [ "$MODE" = "init" ]; then

  # ─── Enable APIs ────────────────────────────────────────────
  echo "==> Enabling required APIs..."
  gcloud services enable \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    compute.googleapis.com \
    storage.googleapis.com \
    iam.googleapis.com \
    iamcredentials.googleapis.com \
    cloudresourcemanager.googleapis.com \
    secretmanager.googleapis.com

  # ─── Artifact Registry ──────────────────────────────────────
  echo "==> Creating Artifact Registry repository..."
  gcloud artifacts repositories describe "$AR_REPO" \
    --location="$REGION" --format="value(name)" 2>/dev/null || \
  gcloud artifacts repositories create "$AR_REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker images"

  # ─── Workload Identity Federation ────────────────────────────
  echo "==> Setting up Workload Identity Federation..."
  PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

  gcloud iam workload-identity-pools describe "$WIF_POOL" \
    --location="global" --format="value(name)" 2>/dev/null || \
  gcloud iam workload-identity-pools create "$WIF_POOL" \
    --location="global" \
    --display-name="GitHub Actions"

  gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" \
    --workload-identity-pool="$WIF_POOL" \
    --location="global" --format="value(name)" 2>/dev/null || \
  gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" \
    --workload-identity-pool="$WIF_POOL" \
    --location="global" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition="assertion.repository=='${GITHUB_ORG}/${GITHUB_REPO}'"

  # ─── Service Account ────────────────────────────────────────
  echo "==> Creating service account..."
  gcloud iam service-accounts describe "$SA_EMAIL" 2>/dev/null || \
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="GitHub Actions Deploy"

  echo "==> Granting roles to service account..."
  for ROLE in \
    roles/run.admin \
    roles/artifactregistry.writer \
    roles/storage.admin \
    roles/iam.serviceAccountUser; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="$ROLE" \
      --condition=None \
      --quiet
  done

  echo "==> Binding WIF to service account..."
  gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}" \
    --quiet

  # ─── Print shared GitHub Variables ──────────────────────────
  WIF_PROVIDER_FULL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/providers/${WIF_PROVIDER}"

  echo ""
  echo "============================================"
  echo " GitHub Repository Variables (shared):"
  echo "============================================"
  echo " Set at: Settings → Secrets and variables → Actions → Variables"
  echo ""
  echo "  GCP_PROJECT_ID      = ${PROJECT_ID}"
  echo "  GCP_REGION          = ${REGION}"
  echo "  WIF_PROVIDER        = ${WIF_PROVIDER_FULL}"
  echo "  WIF_SERVICE_ACCOUNT = ${SA_EMAIL}"
  echo ""
  echo "Next: run '$0 staging' and '$0 production' to create per-environment resources."
  echo ""
  echo "Done (init)!"
  exit 0
fi

# ═══════════════════════════════════════════════════════════════
# staging / production — per-environment resources
# ═══════════════════════════════════════════════════════════════
ENV="$MODE"
BUCKET="${PROJECT_ID}-frontend-${ENV}"
BACKEND_BUCKET_NAME="${PROJECT_ID}-frontend-backend-${ENV}"
URL_MAP_NAME="frontend-url-map-${ENV}"
PROXY_NAME="frontend-https-proxy-${ENV}"
FWD_RULE_NAME="frontend-https-rule-${ENV}"
CERT_NAME="frontend-cert-${ENV}"
IP_NAME="frontend-ip-${ENV}"

# Pick the right domain for this environment
DOMAIN_VAR="DOMAIN_$(echo "$ENV" | tr '[:lower:]' '[:upper:]')"
DOMAIN="${!DOMAIN_VAR}"

# ─── GCS Bucket ───────────────────────────────────────────────
echo "==> Creating GCS bucket for ${ENV} frontend..."
if ! gsutil ls -b "gs://${BUCKET}" 2>/dev/null; then
  gsutil mb -l "$REGION" "gs://${BUCKET}"
fi

echo "==> Configuring bucket for static website hosting..."
gsutil web set -m index.html -e index.html "gs://${BUCKET}"
gsutil iam ch allUsers:objectViewer "gs://${BUCKET}"

# ─── Cloud CDN + Load Balancer ────────────────────────────────
echo "==> Creating backend bucket for CDN..."
gcloud compute backend-buckets describe "$BACKEND_BUCKET_NAME" 2>/dev/null || \
gcloud compute backend-buckets create "$BACKEND_BUCKET_NAME" \
  --gcs-bucket-name="$BUCKET" \
  --enable-cdn

echo "==> Creating URL map..."
gcloud compute url-maps describe "$URL_MAP_NAME" 2>/dev/null || \
gcloud compute url-maps create "$URL_MAP_NAME" \
  --default-backend-bucket="$BACKEND_BUCKET_NAME"

if [ -n "$DOMAIN" ]; then
  echo "==> Creating managed SSL certificate..."
  gcloud compute ssl-certificates describe "$CERT_NAME" 2>/dev/null || \
  gcloud compute ssl-certificates create "$CERT_NAME" \
    --domains="$DOMAIN" \
    --global

  echo "==> Creating HTTPS proxy..."
  gcloud compute target-https-proxies describe "$PROXY_NAME" 2>/dev/null || \
  gcloud compute target-https-proxies create "$PROXY_NAME" \
    --url-map="$URL_MAP_NAME" \
    --ssl-certificates="$CERT_NAME" \
    --global

  echo "==> Reserving static IP..."
  gcloud compute addresses describe "$IP_NAME" --global 2>/dev/null || \
  gcloud compute addresses create "$IP_NAME" --global

  echo "==> Creating forwarding rule..."
  gcloud compute forwarding-rules describe "$FWD_RULE_NAME" --global 2>/dev/null || \
  gcloud compute forwarding-rules create "$FWD_RULE_NAME" \
    --global \
    --target-https-proxy="$PROXY_NAME" \
    --address="$IP_NAME" \
    --ports=443

  STATIC_IP=$(gcloud compute addresses describe "$IP_NAME" --global --format="value(address)")
  echo ""
  echo "   Static IP: ${STATIC_IP}"
  echo "   Point your DNS A record for ${DOMAIN} to ${STATIC_IP}"
else
  echo "   (No DOMAIN_$(echo "$ENV" | tr '[:lower:]' '[:upper:]') set — skipping HTTPS proxy.)"
  echo "   Set it in this script and re-run to create SSL + LB."
fi

# ─── Print environment-scoped GitHub Variables ────────────────
echo ""
echo "============================================"
echo " GitHub Environment Variables for: ${ENV}"
echo "============================================"
echo " Set at: Settings → Environments → ${ENV} → Add variable"
echo ""
echo "  GCS_BUCKET   = ${BUCKET}"
echo "  CDN_URL_MAP  = ${URL_MAP_NAME}"
echo "  CORS_ORIGIN  = https://${DOMAIN:-<your-${ENV}-frontend-domain>}"
echo "  VITE_API_URL = https://<your-backend-${ENV}-cloud-run-url>"
echo ""
echo "Done (${ENV})!"
