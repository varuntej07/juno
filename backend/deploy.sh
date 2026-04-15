#!/usr/bin/env bash
# deploy.sh — Build and deploy Juno backend to Google Cloud Run
#
# Prerequisites (run once):
#   1. Install gcloud CLI: https://cloud.google.com/sdk/docs/install
#   2. gcloud auth login
#   3. gcloud auth configure-docker
#   4. Create secrets (see SECRETS SETUP section below)
#
# Usage:
#   bash backend/deploy.sh <GCP_PROJECT_ID> <REGION>
#   bash backend/deploy.sh my-juno-project us-central1

set -euo pipefail

# Config
PROJECT_ID="${1:?Usage: deploy.sh <GCP_PROJECT_ID> <REGION>}"
REGION="${2:-us-central1}"
SERVICE_NAME="juno-backend"
IMAGE="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

echo "▶ Deploying ${SERVICE_NAME} to project=${PROJECT_ID} region=${REGION}"

# Enable required APIs (idempotent)
echo "▶ Enabling GCP APIs..."
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  containerregistry.googleapis.com \
  secretmanager.googleapis.com \
  --project="${PROJECT_ID}"

# Build & push image
echo "▶ Building Docker image..."
# Run from repo root so the build context is backend/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker build -t "${IMAGE}:latest" "${SCRIPT_DIR}"

echo "▶ Pushing image to GCR..."
docker push "${IMAGE}:latest"

# Deploy to Cloud Run
echo "▶ Deploying to Cloud Run..."
gcloud run deploy "${SERVICE_NAME}" \
  --image="${IMAGE}:latest" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --platform=managed \
  --allow-unauthenticated \
  --min-instances=1 \
  --max-instances=3 \
  --memory=512Mi \
  --cpu=1 \
  --timeout=3600 \
  --concurrency=80 \
  --set-env-vars="ENV=production" \
  --set-env-vars="AWS_REGION=us-east-1" \
  --set-env-vars="ANTHROPIC_MODEL=claude-sonnet-4-6" \
  --set-env-vars="ANTHROPIC_MAX_TOKENS=1024" \
  --set-env-vars="BEDROCK_SONIC_MODEL_ID=us.amazon.nova-2-sonic-v1:0" \
  --set-env-vars="BEDROCK_SONIC_VOICE=matthew" \
  --set-env-vars="GOOGLE_REDIRECT_URI=postmessage" \
  --set-secrets="ANTHROPIC_API_KEY=juno-anthropic-api-key:latest" \
  --set-secrets="AWS_ACCESS_KEY_ID=juno-aws-access-key-id:latest" \
  --set-secrets="AWS_SECRET_ACCESS_KEY=juno-aws-secret-access-key:latest" \
  --set-secrets="GOOGLE_CLIENT_ID=juno-google-client-id:latest" \
  --set-secrets="GOOGLE_CLIENT_SECRET=juno-google-client-secret:latest" \
  --set-secrets="/run/secrets/service-account.json=juno-firebase-service-account:latest" \
  --set-env-vars="GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/service-account.json" \

# Print service URL 
SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(status.url)")

echo ""
echo "✅ Deployed! Service URL:"
echo "   ${SERVICE_URL}"
echo ""
echo "📌 Next steps:"
echo "   1. Update lib/core/config/environment.dart → apiBaseUrl: '${SERVICE_URL}'"
echo "   2. Update lib/core/config/environment.dart → wsBaseUrl: '${SERVICE_URL/https/wss}'"
echo "   3. Add to backend/.env: GOOGLE_CALENDAR_WEBHOOK_URL=${SERVICE_URL}/integrations/google-calendar/webhook"
echo "   4. Re-deploy after step 3 to activate calendar webhooks"
