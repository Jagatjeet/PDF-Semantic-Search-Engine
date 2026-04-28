#!/usr/bin/env bash
# deploy.sh — Build images, push to ACR, deploy to Azure Container Apps
# Prerequisites: az CLI, Docker, logged in to Azure and ACR
#
# Usage:
#   export ACR_NAME=mypdfacr
#   export RESOURCE_GROUP=pdf-search-rg
#   export DOCKERHUB_USERNAME=myuser
#   export DOCKERHUB_PASSWORD=mytoken   # Docker Hub PAT (read-only scope is sufficient)
#   bash deploy.sh

set -euo pipefail

: "${ACR_NAME:?Set ACR_NAME}"
: "${RESOURCE_GROUP:=pdf-search-rg}"
: "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME (Docker Hub login) to avoid pull rate limits}"
: "${DOCKERHUB_PASSWORD:?Set DOCKERHUB_PASSWORD (Docker Hub password or PAT)}"
LOCATION="${LOCATION:-eastus2}"

ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"

echo "==> Importing base images into ACR (authenticated Docker Hub pull avoids rate limits)"
az acr import --name "$ACR_NAME" --source docker.io/library/python:3.11-slim --image python:3.11-slim --username "$DOCKERHUB_USERNAME" --password "$DOCKERHUB_PASSWORD" --force
az acr import --name "$ACR_NAME" --source docker.io/library/node:20-alpine    --image node:20-alpine    --username "$DOCKERHUB_USERNAME" --password "$DOCKERHUB_PASSWORD" --force
az acr import --name "$ACR_NAME" --source docker.io/library/nginx:alpine       --image nginx:alpine       --username "$DOCKERHUB_USERNAME" --password "$DOCKERHUB_PASSWORD" --force

echo "==> Building and pushing backend image (ACR Task)"
az acr build \
  --registry "$ACR_NAME" \
  --image "pdf-search-backend:latest" \
  --build-arg REGISTRY="${ACR_LOGIN_SERVER}/" \
  ./backend

echo "==> Building and pushing frontend image (ACR Task)"
az acr build \
  --registry "$ACR_NAME" \
  --image "pdf-search-frontend:latest" \
  --build-arg REGISTRY="${ACR_LOGIN_SERVER}/" \
  ./frontend

echo "==> Creating resource group (if needed)"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

# The ACA environment must be created with workload profiles enabled from the start.
# If an old Consumption-only environment exists, delete it and its apps before redeploying.
echo "==> Checking for existing ACA environment (Consumption-only environments must be recreated)"
ENV_EXISTS=$(az containerapp env show -g "$RESOURCE_GROUP" -n pdf-search-env --query "name" -o tsv 2>/dev/null || true)
if [ -n "$ENV_EXISTS" ]; then
  echo "    Deleting existing container apps and environment..."
  for app in pdf-search-frontend pdf-search-backend ollama qdrant; do
    az containerapp delete -g "$RESOURCE_GROUP" -n "$app" --yes --no-wait 2>/dev/null || true
  done
  # Wait for apps to be deleted before removing the environment
  sleep 30
  az containerapp env delete -g "$RESOURCE_GROUP" -n pdf-search-env --yes
  echo "    Waiting for environment to be fully deleted..."
  for i in $(seq 1 30); do
    STATE=$(az containerapp env show -g "$RESOURCE_GROUP" -n pdf-search-env --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Deleted")
    echo "    State: $STATE (attempt $i/30)"
    if [ "$STATE" = "Deleted" ] || [ -z "$STATE" ]; then
      echo "    Environment deleted."
      break
    fi
    if [ "$i" -eq 30 ]; then
      echo "ERROR: Environment still not deleted after 5 minutes. Aborting." >&2
      exit 1
    fi
    sleep 10
  done
fi

echo "==> Deploying Bicep template"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters acrName="$ACR_NAME" \
  --query '{frontendUrl:properties.outputs.frontendUrl.value, backendUrl:properties.outputs.backendUrl.value, ollamaUrl:properties.outputs.ollamaUrl.value}' \
  --output json

echo "==> Deployment complete!"
