#!/usr/bin/env bash
# Initializes, unseals and configures the local Vault for the app secrets. Safe to re-run.
#
# - First run: initializes Vault with a single unseal key and saves the unseal key and
#   root token to .vault/init.json (git-ignored, mode 600). Keep that file: without it a
#   sealed Vault can't be opened again.
# - Every run: unseals Vault if it is sealed (it seals itself whenever its pod restarts),
#   then makes sure the KV engine, Kubernetes auth, the per-app policies and roles exist.
# - Seeds secret/auth-service/app, secret/mysql/root and secret/mysql/app-user once.
#   Existing Kubernetes Secrets with the same names are copied in, so a MySQL that was
#   initialized with them keeps working. Otherwise random values are generated.
#
# Usage: setup.sh          full setup (make vault-setup)
#        setup.sh unseal   only unseal (make vault-unseal)
set -euo pipefail

NS=vault
POD=vault-0
APP_NS=${APP_NAMESPACE:-default}
KEYS_FILE=${VAULT_KEYS_FILE:-.vault/init.json}

if ! kubectl get pod -n "$NS" "$POD" >/dev/null 2>&1; then
  echo "Vault isn't deployed. Run 'make deploy-vault' first." >&2
  exit 1
fi
kubectl wait -n "$NS" --for=jsonpath='{.status.phase}'=Running "pod/$POD" --timeout=180s >/dev/null

# `vault status` exits 0 when unsealed, 2 when sealed and 1 when Vault doesn't answer yet.
status_json() { kubectl exec -n "$NS" "$POD" -- vault status -format=json 2>/dev/null || true; }
for _ in $(seq 1 60); do
  status_json | grep -q '"initialized"' && break
  sleep 2
done
initialized() { status_json | grep -q '"initialized": true'; }
sealed() { status_json | grep -q '"sealed": true'; }

if ! initialized; then
  if [ -f "$KEYS_FILE" ]; then
    mv "$KEYS_FILE" "$KEYS_FILE.old-$(date +%s)"
    echo "Vault has a new, empty data volume; moved the old $KEYS_FILE aside."
  fi
  mkdir -p "$(dirname "$KEYS_FILE")"
  (umask 077 && kubectl exec -n "$NS" "$POD" -- \
    vault operator init -key-shares=1 -key-threshold=1 -format=json > "$KEYS_FILE")
  echo "Initialized Vault. Its unseal key and root token are in $KEYS_FILE: keep it safe, never commit it."
fi

if [ ! -f "$KEYS_FILE" ]; then
  echo "Vault is initialized but $KEYS_FILE is missing, and it holds the only unseal key." >&2
  exit 1
fi
UNSEAL_KEY=$(sed -n '/"unseal_keys_b64"/{n;s/[^"]*"\([^"]*\)".*/\1/p;}' "$KEYS_FILE")
ROOT_TOKEN=$(sed -n 's/.*"root_token": *"\([^"]*\)".*/\1/p' "$KEYS_FILE")

if sealed; then
  # The key goes over stdin (key=-), so it never shows up in a process list.
  # `vault operator unseal` only prompts on a terminal, hence the raw sys/unseal call.
  printf '%s' "$UNSEAL_KEY" | kubectl exec -i -n "$NS" "$POD" -- vault write sys/unseal key=- >/dev/null
  echo "Unsealed Vault."
else
  echo "Vault is unsealed."
fi
[ "${1:-}" = "unseal" ] && exit 0

# Seed values: an existing Kubernetes Secret wins, otherwise a random value.
k8s_value() { kubectl get secret -n "$APP_NS" "$1" -o jsonpath="{.data.$2}" 2>/dev/null | base64 --decode; }
or_random() { [ -n "$1" ] && printf '%s' "$1" || printf '%s' "$2"; }
quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
APP_KEY=$(or_random "$(k8s_value auth-service-app APP_KEY)" "base64:$(openssl rand -base64 32)")
ROOT_PASSWORD=$(or_random "$(k8s_value mysql-root password)" "$(openssl rand -hex 16)")
APP_USER=$(or_random "$(k8s_value mysql-app-user username)" app)
APP_PASSWORD=$(or_random "$(k8s_value mysql-app-user password)" "$(openssl rand -hex 16)")

# The script runs inside the Vault pod. It and the root token travel over stdin, not argv.
{
  printf 'export VAULT_TOKEN=%s\n' "$(quote "$ROOT_TOKEN")"
  printf 'APP_NS=%s APP_KEY=%s ROOT_PASSWORD=%s APP_USER=%s APP_PASSWORD=%s\n' \
    "$(quote "$APP_NS")" "$(quote "$APP_KEY")" "$(quote "$ROOT_PASSWORD")" \
    "$(quote "$APP_USER")" "$(quote "$APP_PASSWORD")"
  cat <<'SCRIPT'
set -eu
vault secrets list | grep -q '^secret/' || vault secrets enable -path=secret kv-v2 >/dev/null
vault auth list | grep -q '^kubernetes/' || vault auth enable kubernetes >/dev/null
# Vault reviews the apps' ServiceAccount tokens with its own in-cluster credentials.
vault write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc >/dev/null

# Each app can read only its own secrets.
vault policy write auth-service - >/dev/null <<'POLICY'
path "secret/data/auth-service/app" { capabilities = ["read"] }
path "secret/data/mysql/app-user"   { capabilities = ["read"] }
POLICY
vault policy write mysql - >/dev/null <<'POLICY'
path "secret/data/mysql/root"     { capabilities = ["read"] }
path "secret/data/mysql/app-user" { capabilities = ["read"] }
POLICY
for app in auth-service mysql; do
  vault write "auth/kubernetes/role/$app" \
    bound_service_account_names="$app" bound_service_account_namespaces="$APP_NS" \
    policies="$app" audience=vault token_ttl=1h >/dev/null
done

seed() {
  path=$1; shift
  if vault kv get "secret/$path" >/dev/null 2>&1; then
    echo "secret/$path already exists, kept."
  else
    vault kv put "secret/$path" "$@" >/dev/null
    echo "secret/$path seeded."
  fi
}
seed auth-service/app APP_KEY="$APP_KEY"
seed mysql/root password="$ROOT_PASSWORD"
seed mysql/app-user username="$APP_USER" password="$APP_PASSWORD"
SCRIPT
} | kubectl exec -i -n "$NS" "$POD" -- sh -s
echo "Vault is configured."
