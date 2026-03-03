#!/usr/bin/env bash
#
# GCP project setup for react-fastify-skel.
# Each environment gets its own GCP project for full isolation.
# Idempotent — safe to re-run.
#
# Usage:
#   1. Fill in the configuration variables below
#   2. chmod +x scripts/gcp_setup.sh
#   3. ./scripts/gcp_setup.sh staging       # full setup for staging project
#   4. ./scripts/gcp_setup.sh production    # full setup for production project
#
# After running, configure the printed values as GitHub Environment Variables:
#   Repo → Settings → Environments → <env> → Add variable
#
set -euo pipefail

# ─── Configuration (edit these) ───────────────────────────────
PROJECT_ID_STAGING="react-fastify-skel-staging"         # must be globally unique
PROJECT_ID_PRODUCTION="react-fastify-skel-production"   # must be globally unique
REGION="us-central1"
GITHUB_ORG="nateware"    # or personal username
GITHUB_REPO="react-fastify-skel"
DOMAIN_STAGING="app.staging.nojungle.com"      # optional: e.g. staging.myapp.example.com
DOMAIN_PRODUCTION="app.nojungle.com"           # optional: e.g. myapp.example.com
API_DOMAIN_STAGING="api.staging.nojungle.com"  # optional: custom domain for Cloud Run backend
API_DOMAIN_PRODUCTION="api.nojungle.com"       # optional: custom domain for Cloud Run backend
SQL_INSTANCE="postgres"                        # Cloud SQL instance name
SQL_DB="app"                                   # database name
SQL_TIER="db-f1-micro"                         # smallest; resize via console later
# ──────────────────────────────────────────────────────────────

ENV="${1:?Usage: $0 <staging|production>}"

case "$ENV" in
  staging|production) ;;
  *) echo "Error: argument must be 'staging' or 'production'"; exit 1 ;;
esac

# Resolve per-environment config
PROJECT_ID_VAR="PROJECT_ID_$(echo "$ENV" | tr '[:lower:]' '[:upper:]')"
PROJECT_ID="${!PROJECT_ID_VAR}"
DOMAIN_VAR="DOMAIN_$(echo "$ENV" | tr '[:lower:]' '[:upper:]')"
DOMAIN="${!DOMAIN_VAR}"
API_DOMAIN_VAR="API_DOMAIN_$(echo "$ENV" | tr '[:lower:]' '[:upper:]')"
API_DOMAIN="${!API_DOMAIN_VAR}"

SA_NAME="deploy"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
WIF_POOL="github-pool"
WIF_PROVIDER="github-provider"
AR_REPO="docker"
BUCKET="${PROJECT_ID}-frontend"
BACKEND_BUCKET_NAME="${PROJECT_ID}-frontend-backend"
URL_MAP_NAME="frontend-url-map"
PROXY_NAME="frontend-https-proxy"
FWD_RULE_NAME="frontend-https-rule"
CERT_NAME="frontend-cert"
IP_NAME="frontend-ip"

echo "==> Setting up ${ENV} environment in project ${PROJECT_ID}"
gcloud config set project "$PROJECT_ID"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

# ─── Environment Tag ──────────────────────────────────────────
# GCP recommends tagging projects with an 'environment' value.
case "$ENV" in
  staging)    TAG_VALUE="Staging" ;;
  production) TAG_VALUE="Production" ;;
esac

echo "==> Tagging project with environment=${TAG_VALUE}..."
TAG_KEY=$(gcloud resource-manager tags keys list \
  --parent="projects/${PROJECT_ID}" \
  --filter="shortName=environment" \
  --format="value(name)" 2>/dev/null | head -1)

if [ -z "$TAG_KEY" ]; then
  TAG_KEY=$(gcloud resource-manager tags keys create environment \
    --parent="projects/${PROJECT_ID}" \
    --description="Environment type" \
    --format="value(name)")
fi

TAG_VALUE_NAME=$(gcloud resource-manager tags values list \
  --parent="$TAG_KEY" \
  --filter="shortName=${TAG_VALUE}" \
  --format="value(name)" 2>/dev/null | head -1)

if [ -z "$TAG_VALUE_NAME" ]; then
  TAG_VALUE_NAME=$(gcloud resource-manager tags values create "$TAG_VALUE" \
    --parent="$TAG_KEY" \
    --description="${TAG_VALUE} environment" \
    --format="value(name)")
fi

EXISTING_BINDING=$(gcloud resource-manager tags bindings list \
  --parent="//cloudresourcemanager.googleapis.com/projects/${PROJECT_NUMBER}" \
  --location=global \
  --format="value(tagValue)" 2>/dev/null | grep "${TAG_VALUE_NAME}" || true)

if [ -z "$EXISTING_BINDING" ]; then
  gcloud resource-manager tags bindings create \
    --tag-value="$TAG_VALUE_NAME" \
    --parent="//cloudresourcemanager.googleapis.com/projects/${PROJECT_NUMBER}" \
    --location=global
fi

# ─── Enable APIs ──────────────────────────────────────────────
echo "==> Enabling required APIs..."
gcloud services enable \
  --project="$PROJECT_ID" \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  secretmanager.googleapis.com \
  dns.googleapis.com \
  sqladmin.googleapis.com

# ─── Artifact Registry ────────────────────────────────────────
echo "==> Creating Artifact Registry repository..."
gcloud artifacts repositories describe "$AR_REPO" \
  --project="$PROJECT_ID" \
  --location="$REGION" --format="value(name)" 2>/dev/null || \
gcloud artifacts repositories create "$AR_REPO" \
  --project="$PROJECT_ID" \
  --repository-format=docker \
  --location="$REGION" \
  --description="Docker images"

# ─── Workload Identity Federation ──────────────────────────────
echo "==> Setting up Workload Identity Federation..."

gcloud iam workload-identity-pools describe "$WIF_POOL" \
  --project="$PROJECT_ID" \
  --location="global" --format="value(name)" 2>/dev/null || \
gcloud iam workload-identity-pools create "$WIF_POOL" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions"

gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" \
  --project="$PROJECT_ID" \
  --workload-identity-pool="$WIF_POOL" \
  --location="global" --format="value(name)" 2>/dev/null || \
gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" \
  --project="$PROJECT_ID" \
  --workload-identity-pool="$WIF_POOL" \
  --location="global" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='${GITHUB_ORG}/${GITHUB_REPO}'"

# ─── Service Account ──────────────────────────────────────────
echo "==> Creating service account..."
if ! gcloud iam service-accounts describe "$SA_EMAIL" \
  --project="$PROJECT_ID" --format="value(email)" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="GitHub Actions Deploy"
  echo "   Waiting for service account to propagate..."
  sleep 10
fi

echo "==> Granting roles to service account..."
for ROLE in \
  roles/run.admin \
  roles/artifactregistry.writer \
  roles/storage.admin \
  roles/iam.serviceAccountUser \
  roles/cloudsql.client \
  roles/cloudsql.instanceUser; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$ROLE" \
    --condition=None \
    --quiet
done

echo "==> Binding WIF to service account..."
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}" \
  --quiet

# ─── GCS Bucket (frontend SPA) ────────────────────────────────
echo "==> Creating GCS bucket for frontend..."
if ! gsutil ls -b "gs://${BUCKET}" 2>/dev/null; then
  gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${BUCKET}"
fi

echo "==> Configuring bucket for static website hosting..."
gsutil web set -m index.html -e index.html "gs://${BUCKET}"
gsutil iam ch allUsers:objectViewer "gs://${BUCKET}"

# ─── Cloud CDN + Load Balancer ─────────────────────────────────
echo "==> Creating backend bucket for CDN..."
gcloud compute backend-buckets describe "$BACKEND_BUCKET_NAME" \
  --project="$PROJECT_ID" 2>/dev/null || \
gcloud compute backend-buckets create "$BACKEND_BUCKET_NAME" \
  --project="$PROJECT_ID" \
  --gcs-bucket-name="$BUCKET" \
  --enable-cdn

echo "==> Creating URL map..."
gcloud compute url-maps describe "$URL_MAP_NAME" \
  --project="$PROJECT_ID" 2>/dev/null || \
gcloud compute url-maps create "$URL_MAP_NAME" \
  --project="$PROJECT_ID" \
  --default-backend-bucket="$BACKEND_BUCKET_NAME"

if [ -n "$DOMAIN" ]; then
  echo "==> Creating managed SSL certificate..."
  gcloud compute ssl-certificates describe "$CERT_NAME" \
    --project="$PROJECT_ID" 2>/dev/null || \
  gcloud compute ssl-certificates create "$CERT_NAME" \
    --project="$PROJECT_ID" \
    --domains="$DOMAIN" \
    --global

  echo "==> Creating HTTPS proxy..."
  gcloud compute target-https-proxies describe "$PROXY_NAME" \
    --project="$PROJECT_ID" 2>/dev/null || \
  gcloud compute target-https-proxies create "$PROXY_NAME" \
    --project="$PROJECT_ID" \
    --url-map="$URL_MAP_NAME" \
    --ssl-certificates="$CERT_NAME" \
    --global

  echo "==> Reserving static IP..."
  gcloud compute addresses describe "$IP_NAME" \
    --project="$PROJECT_ID" --global 2>/dev/null || \
  gcloud compute addresses create "$IP_NAME" \
    --project="$PROJECT_ID" --global

  echo "==> Creating forwarding rule..."
  gcloud compute forwarding-rules describe "$FWD_RULE_NAME" \
    --project="$PROJECT_ID" --global 2>/dev/null || \
  gcloud compute forwarding-rules create "$FWD_RULE_NAME" \
    --project="$PROJECT_ID" \
    --global \
    --target-https-proxy="$PROXY_NAME" \
    --address="$IP_NAME" \
    --ports=443

  STATIC_IP=$(gcloud compute addresses describe "$IP_NAME" \
    --project="$PROJECT_ID" --global --format="value(address)")

  # ─── Cloud DNS (frontend) ──────────────────────────────────
  DNS_ZONE_NAME="frontend-dns-${ENV}"

  echo "==> Creating Cloud DNS zone for ${DOMAIN}..."
  gcloud dns managed-zones describe "$DNS_ZONE_NAME" \
    --project="$PROJECT_ID" 2>/dev/null || \
  gcloud dns managed-zones create "$DNS_ZONE_NAME" \
    --project="$PROJECT_ID" \
    --dns-name="${DOMAIN}." \
    --description="Frontend DNS (${ENV})"

  echo "==> Creating A record pointing to load balancer..."
  EXISTING_A=$(gcloud dns record-sets list \
    --project="$PROJECT_ID" \
    --zone="$DNS_ZONE_NAME" \
    --name="${DOMAIN}." \
    --type=A \
    --format="value(name)" 2>/dev/null)

  if [ -z "$EXISTING_A" ]; then
    gcloud dns record-sets create "${DOMAIN}." \
      --project="$PROJECT_ID" \
      --zone="$DNS_ZONE_NAME" \
      --type="A" \
      --ttl=300 \
      --rrdatas="$STATIC_IP"
  else
    echo "   A record already exists, updating..."
    gcloud dns record-sets update "${DOMAIN}." \
      --project="$PROJECT_ID" \
      --zone="$DNS_ZONE_NAME" \
      --type="A" \
      --ttl=300 \
      --rrdatas="$STATIC_IP"
  fi

  FRONTEND_NS=$(gcloud dns managed-zones describe "$DNS_ZONE_NAME" \
    --project="$PROJECT_ID" --format="value(nameServers)")
  echo ""
  echo "   Frontend static IP: ${STATIC_IP}"
  echo ""
  echo "   Update your domain registrar's NS records for ${DOMAIN} to:"
  echo "   ${FRONTEND_NS}" | tr ';' '\n' | sed 's/^/   /'
else
  echo "   (No DOMAIN_$(echo "$ENV" | tr '[:lower:]' '[:upper:]') set — skipping HTTPS proxy.)"
  echo "   Set it in this script and re-run to create SSL + LB."
fi

# ─── Cloud Run (backend placeholder) ─────────────────────────
# Create the Cloud Run service with a placeholder image so that
# domain mapping can be configured immediately. The first real
# deploy from GitHub Actions will replace the placeholder.
echo "==> Creating Cloud Run backend service..."
if ! gcloud run services describe backend \
  --project="$PROJECT_ID" --region="$REGION" --format="value(name)" >/dev/null 2>&1; then
  gcloud run deploy backend \
    --project="$PROJECT_ID" \
    --image="us-docker.pkg.dev/cloudrun/container/hello" \
    --region="$REGION" \
    --platform=managed \
    --allow-unauthenticated \
    --set-env-vars="NODE_ENV=production" \
    --quiet
else
  echo "   Cloud Run backend service already exists."
fi

# ─── Cloud SQL (PostgreSQL Enterprise) ────────────────────────
echo "==> Creating Cloud SQL instance (this may take several minutes)..."
if ! gcloud sql instances describe "$SQL_INSTANCE" \
  --project="$PROJECT_ID" --format="value(name)" >/dev/null 2>&1; then
  gcloud sql instances create "$SQL_INSTANCE" \
    --project="$PROJECT_ID" \
    --database-version=POSTGRES_18 \
    --edition=ENTERPRISE \
    --tier="$SQL_TIER" \
    --region="$REGION" \
    --storage-type=SSD \
    --storage-size=10 \
    --availability-type=zonal \
    --database-flags=cloudsql.iam_authentication=on \
    --quiet
else
  echo "   Cloud SQL instance already exists. Ensuring IAM auth flag is enabled..."
  gcloud sql instances patch "$SQL_INSTANCE" \
    --project="$PROJECT_ID" \
    --database-flags=cloudsql.iam_authentication=on \
    --quiet
fi

CLOUDSQL_CONNECTION="${PROJECT_ID}:${REGION}:${SQL_INSTANCE}"

echo "==> Creating database..."
gcloud sql databases describe "$SQL_DB" \
  --instance="$SQL_INSTANCE" \
  --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || \
gcloud sql databases create "$SQL_DB" \
  --instance="$SQL_INSTANCE" \
  --project="$PROJECT_ID"

# ─── IAM Database User ───────────────────────────────────────
# Use IAM authentication — no passwords to manage.
# The service account authenticates directly via Cloud SQL Connector.
IAM_DB_USER="${SA_EMAIL%.gserviceaccount.com}"

echo "==> Creating IAM database user for ${IAM_DB_USER}..."
EXISTING_IAM_USER=$(gcloud sql users list \
  --instance="$SQL_INSTANCE" \
  --project="$PROJECT_ID" \
  --filter="name=${IAM_DB_USER}" \
  --format="value(name)" 2>/dev/null)

if [ -z "$EXISTING_IAM_USER" ]; then
  gcloud sql users create "$IAM_DB_USER" \
    --instance="$SQL_INSTANCE" \
    --project="$PROJECT_ID" \
    --type=CLOUD_IAM_SERVICE_ACCOUNT
else
  echo "   IAM user already exists."
fi

# Grant schema privileges to the IAM user.
# Requires psql (brew install libpq / apt install postgresql-client).
echo "==> Granting database privileges to IAM user..."
POSTGRES_PASSWORD=$(openssl rand -base64 24)
gcloud sql users set-password postgres \
  --instance="$SQL_INSTANCE" \
  --project="$PROJECT_ID" \
  --password="$POSTGRES_PASSWORD" \
  --quiet

# Run the Cloud SQL proxy directly so we can call psql with PGPASSWORD.
# gcloud sql connect doesn't forward env vars to its child psql process.
# Pass --token so the proxy uses gcloud's auth (not Application Default Credentials).
PROXY_PORT=15432
PROXY_BIN="$(gcloud info --format='value(installation.sdk_root)')/bin/cloud-sql-proxy"
ACCESS_TOKEN="$(gcloud auth print-access-token)"

echo "   Starting Cloud SQL proxy..."
"$PROXY_BIN" "${CLOUDSQL_CONNECTION}" --port "$PROXY_PORT" --token "$ACCESS_TOKEN" --quiet &
PROXY_PID=$!
sleep 3

PGPASSWORD="$POSTGRES_PASSWORD" psql \
  -h 127.0.0.1 -p "$PROXY_PORT" -U postgres -d "$SQL_DB" <<EOSQL
GRANT ALL PRIVILEGES ON SCHEMA public TO "${IAM_DB_USER}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "${IAM_DB_USER}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "${IAM_DB_USER}";
CREATE SCHEMA IF NOT EXISTS drizzle;
GRANT ALL PRIVILEGES ON SCHEMA drizzle TO "${IAM_DB_USER}";
ALTER DEFAULT PRIVILEGES IN SCHEMA drizzle GRANT ALL ON TABLES TO "${IAM_DB_USER}";
EOSQL

kill "$PROXY_PID" 2>/dev/null
wait "$PROXY_PID" 2>/dev/null
echo "   Privileges granted."

# ─── API Domain (Cloud Run backend) ──────────────────────────
if [ -n "$API_DOMAIN" ]; then
  API_DNS_ZONE_NAME="api-dns-${ENV}"

  echo "==> Creating Cloud DNS zone for ${API_DOMAIN}..."
  gcloud dns managed-zones describe "$API_DNS_ZONE_NAME" \
    --project="$PROJECT_ID" 2>/dev/null || \
  gcloud dns managed-zones create "$API_DNS_ZONE_NAME" \
    --project="$PROJECT_ID" \
    --dns-name="${API_DOMAIN}." \
    --description="API backend DNS (${ENV})"

  # Cloud Run domain mapping uses Google's IPs for apex domains.
  # CNAME is not allowed at zone apex, so we use A records instead.
  # See: https://cloud.google.com/run/docs/mapping-custom-domains#dns_update
  CLOUD_RUN_IPS="216.239.32.21,216.239.34.21,216.239.36.21,216.239.38.21"

  echo "==> Creating A records for Cloud Run domain mapping..."
  EXISTING_A=$(gcloud dns record-sets list \
    --project="$PROJECT_ID" \
    --zone="$API_DNS_ZONE_NAME" \
    --name="${API_DOMAIN}." \
    --type=A \
    --format="value(name)" 2>/dev/null)

  if [ -z "$EXISTING_A" ]; then
    gcloud dns record-sets create "${API_DOMAIN}." \
      --project="$PROJECT_ID" \
      --zone="$API_DNS_ZONE_NAME" \
      --type="A" \
      --ttl=300 \
      --rrdatas="$CLOUD_RUN_IPS"
  else
    echo "   A records already exist."
  fi

  echo "==> Creating Cloud Run domain mapping for ${API_DOMAIN}..."
  gcloud beta run domain-mappings describe \
    --project="$PROJECT_ID" \
    --domain="$API_DOMAIN" \
    --region="$REGION" 2>/dev/null || \
  gcloud beta run domain-mappings create \
    --project="$PROJECT_ID" \
    --service=backend \
    --domain="$API_DOMAIN" \
    --region="$REGION"

  API_NS=$(gcloud dns managed-zones describe "$API_DNS_ZONE_NAME" \
    --project="$PROJECT_ID" --format="value(nameServers)")
  echo ""
  echo "   Update your domain registrar's NS records for ${API_DOMAIN} to:"
  echo "   ${API_NS}" | tr ';' '\n' | sed 's/^/   /'
fi

# ─── Print GitHub Environment Variables ────────────────────────
WIF_PROVIDER_FULL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/providers/${WIF_PROVIDER}"

echo ""
echo "============================================"
echo " GitHub Environment Variables for: ${ENV}"
echo "============================================"
echo " Set at: Settings → Environments → ${ENV} → Add variable"
echo ""
echo "  GCP_PROJECT_ID      = ${PROJECT_ID}"
echo "  GCP_REGION          = ${REGION}"
echo "  WIF_PROVIDER        = ${WIF_PROVIDER_FULL}"
echo "  WIF_SERVICE_ACCOUNT = ${SA_EMAIL}"
echo "  GCS_BUCKET          = ${BUCKET}"
echo "  CDN_URL_MAP         = ${URL_MAP_NAME}"
echo "  CLOUDSQL_CONNECTION = ${CLOUDSQL_CONNECTION}"
echo "  DB_IAM_USER         = ${IAM_DB_USER}"
echo "  DB_NAME             = ${SQL_DB}"
echo "  CLOUD_RUN_SERVICE_ACCOUNT = ${SA_EMAIL}"
echo "  CORS_ORIGIN         = https://${DOMAIN:-<your-${ENV}-frontend-domain>}"
echo "  VITE_API_URL        = https://${API_DOMAIN:-<your-backend-${ENV}-cloud-run-url>}"
echo ""
echo " GitHub Secrets (Settings → Environments → ${ENV} → Add secret):"
echo ""
echo "  POSTGRES_PASSWORD   = ${POSTGRES_PASSWORD}"
echo ""
echo "Done (${ENV})!"
