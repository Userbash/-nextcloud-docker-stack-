#!/bin/bash
# Script for automating secret deployment to GitHub from .env file
# Usage: ./scripts/push-secrets.sh

# Resolve script directory to handle paths correctly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

REPO="Userbash/nextcloud-docker-stack"
ENV_FILE="$PROJECT_ROOT/.env"
TEMPLATE_FILE="$PROJECT_ROOT/.env.template"

if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) not found. Please install it."
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    if [ -f "$TEMPLATE_FILE" ]; then
        echo "Warning: $ENV_FILE not found. Creating it from $TEMPLATE_FILE..."
        cp "$TEMPLATE_FILE" "$ENV_FILE"
        echo "Please edit $ENV_FILE with your actual secrets and run this script again."
        exit 1
    else
        echo "Error: Neither .env nor .env.template found in $PROJECT_ROOT."
        exit 1
    fi
fi

echo "Pushing secrets to $REPO from $ENV_FILE..."

# Export variables from .env
set -o allexport
source "$ENV_FILE"
set +o allexport

# List of secrets to push - these match the GitHub secrets names used in deploy.yml
# We use a mapping if local var names differ from secret names.
# Here we ensure they match exactly as expected in deploy.yml.
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
)

for key in "${!SECRETS_MAP[@]}"; do
  secret_name="${SECRETS_MAP[$key]}"
  val="${!key}"
  if [ -z "$val" ]; then
    echo "Warning: Variable $key is empty, skipping."
    continue
  fi
  echo "Setting secret $secret_name from $key..."
  echo "$val" | gh secret set "$secret_name" --repo "$REPO"
done

echo "✅ All secrets pushed successfully."
