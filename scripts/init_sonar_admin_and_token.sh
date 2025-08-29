#!/usr/bin/env bash
set -euo pipefail

SONARQUBE_HOST="${SONARQUBE_HOST:-http://localhost:9000}"
SONARQUBE_ADMIN_NEW_PASSWORD="${SONARQUBE_ADMIN_NEW_PASSWORD:-ChangeMe123!}"
SONARQUBE_TOKEN_NAME="${SONARQUBE_TOKEN_NAME:-jenkins-token}"

echo "[INFO] Waiting for SonarQube to be ready..."
for i in {1..60}; do
  if curl -sSf "$SONARQUBE_HOST/api/system/health" | jq -e '.health=="GREEN"' >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

echo "[INFO] Changing default admin password..."
curl -sSf -u admin:admin -X POST "$SONARQUBE_HOST/api/users/change_password" \
  -d "login=admin&previousPassword=admin&password=${SONARQUBE_ADMIN_NEW_PASSWORD}"

echo "[INFO] Generating token..."
TOKEN_JSON=$(curl -sSf -u admin:${SONARQUBE_ADMIN_NEW_PASSWORD} \
  -X POST "$SONARQUBE_HOST/api/user_tokens/generate" -d "name=${SONARQUBE_TOKEN_NAME}")
TOKEN=$(echo "$TOKEN_JSON" | jq -r '.token')

echo "[SUCCESS] SONAR_TOKEN=${TOKEN}"
