#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_URL="http://localhost:8080/keycloak"
REALM_NAME="mlflow"
CLIENT_ID="oauth2-proxy"
REDIRECT_URI="http://localhost/oauth2/callback"
TEST_USER="user"
TEST_PASSWORD="password"
NAMESPACE="mlflow-oidc"

# Start port-forward to Keycloak in background
echo "--- Starting port-forward to Keycloak ---"
kubectl port-forward -n "$NAMESPACE" svc/keycloak 8080:8080 &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null || true" EXIT

# Wait for port-forward to be ready
echo "--- Waiting for port-forward ---"
for i in $(seq 1 30); do
  if curl -sf "$KEYCLOAK_URL/health/ready" > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

# 1. Get admin token
echo "--- Getting admin token ---"
ADMIN_TOKEN=$(curl -sf -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ "$ADMIN_TOKEN" = "null" ] || [ -z "$ADMIN_TOKEN" ]; then
  echo "ERROR: Failed to get admin token"
  exit 1
fi

# 2. Create realm
echo "--- Creating realm: $REALM_NAME ---"
curl -sf -X POST "$KEYCLOAK_URL/admin/realms" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "realm": "'"$REALM_NAME"'",
    "enabled": true
  }' || true

# 3. Create client
echo "--- Creating client: $CLIENT_ID ---"
curl -sf -X POST "$KEYCLOAK_URL/admin/realms/$REALM_NAME/clients" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "'"$CLIENT_ID"'",
    "enabled": true,
    "protocol": "openid-connect",
    "publicClient": false,
    "clientAuthenticatorType": "client-secret",
    "redirectUris": ["'"$REDIRECT_URI"'"],
    "webOrigins": ["http://localhost"],
    "standardFlowEnabled": true,
    "directAccessGrantsEnabled": true
  }'

# 4. Get client UUID and secret
echo "--- Getting client secret ---"
CLIENT_UUID=$(curl -sf "$KEYCLOAK_URL/admin/realms/$REALM_NAME/clients?clientId=$CLIENT_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')

CLIENT_SECRET=$(curl -sf "$KEYCLOAK_URL/admin/realms/$REALM_NAME/clients/$CLIENT_UUID/client-secret" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.value')

echo "--- Client secret: $CLIENT_SECRET ---"

# 5. Create test user
echo "--- Creating test user: $TEST_USER ---"
curl -sf -X POST "$KEYCLOAK_URL/admin/realms/$REALM_NAME/users" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "'"$TEST_USER"'",
    "enabled": true,
    "emailVerified": true,
    "email": "'"$TEST_USER"'@example.com",
    "credentials": [{
      "type": "password",
      "value": "'"$TEST_PASSWORD"'",
      "temporary": false
    }]
  }'

# 6. Generate cookie secret (32 bytes, base64)
COOKIE_SECRET=$(python3 -c "import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())")

# 7. Create Kubernetes secret for oauth2-proxy
echo "--- Creating Kubernetes secret ---"
kubectl create secret generic oauth2-proxy \
  --namespace "$NAMESPACE" \
  --from-literal=client-id="$CLIENT_ID" \
  --from-literal=client-secret="$CLIENT_SECRET" \
  --from-literal=cookie-secret="$COOKIE_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "--- Keycloak configuration complete ---"
