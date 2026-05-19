#!/bin/bash
# Script for automating secret generation and deployment to GitHub
# Usage: ./scripts/push-secrets.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
REPO="Userbash/nextcloud-docker-stack"

# 1. Ensure .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found. Please create it from .env.example before pushing secrets."
    exit 1
fi

# 2. Load variables securely
while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.* ]] || [[ -z "$key" ]] && continue
    export "$key"="$value"
done < "$ENV_FILE"

# 3. Comprehensive Secret Map covering ALL env vars needed for deployment
declare -A SECRETS_MAP=(
  ["POSTGRES_DB"]="DB_NAME"
  ["POSTGRES_USER"]="DB_USER"
  ["POSTGRES_PASSWORD"]="DB_PASSWORD"
  ["POSTGRES_HOST"]="DB_HOST"
  ["NEXTCLOUD_ADMIN_USER"]="ADMIN_USER"
  ["NEXTCLOUD_ADMIN_PASSWORD"]="ADMIN_PASSWORD"
  ["NEXTCLOUD_DOMAIN"]="DOMAIN"
  ["NEXTCLOUD_TRUSTED_DOMAINS"]="TRUSTED_DOMAINS"
  ["LETSENCRYPT_EMAIL"]="EMAIL"
  ["OVERWRITEPROTOCOL"]="OVERWRITEPROTOCOL"
  ["PHP_MEMORY_LIMIT"]="PHP_MEMORY_LIMIT"
  ["PHP_UPLOAD_MAX_FILESIZE"]="PHP_UPLOAD_MAX_FILESIZE"
  ["PHP_POST_MAX_SIZE"]="PHP_POST_MAX_SIZE"
  ["PHP_MAX_EXECUTION_TIME"]="PHP_MAX_EXECUTION_TIME"
  ["PHP_OPCACHE_ENABLE"]="PHP_OPCACHE_ENABLE"
  ["PHP_OPCACHE_MEMORY_CONSUMPTION"]="PHP_OPCACHE_MEMORY_CONSUMPTION"
  ["PHP_APCU_ENABLED"]="PHP_APCU_ENABLED"
  ["REDIS_HOST"]="REDIS_HOST"
  ["REDIS_PORT"]="REDIS_PORT"
  ["REDIS_PASSWORD"]="REDIS_PASSWORD"
)

# 4. Push Secrets
for key in "${!SECRETS_MAP[@]}"; do
    secret_name="${SECRETS_MAP[$key]}"
    val=$(eval echo "\$$key")
    if [ -z "$val" ]; then
        echo "Warning: Variable $key is empty."
        continue
    fi
    echo "Setting $secret_name to GitHub..."
    echo "$val" | gh secret set "$secret_name" --repo "$REPO"
done

echo "✅ All secrets and deployment configurations fully synced."