#!/bin/bash
# Update and maintenance script
# Usage: ./scripts/update.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname "$script_dir")"

echo "🔄 Nextcloud Update & Maintenance"
echo "=================================="
echo ""

cd "$project_dir"

# Pull latest images
echo "📥 Pulling latest images..."
if docker-compose -f docker-compose.yml -f docker-compose.prod.yml pull; then
    echo "✅ Images updated"
else
    echo "❌ Failed to pull images"
    exit 1
fi

# Backup before update
echo "💾 Creating backup..."
if bash "$script_dir/backup.sh"; then
    echo "✅ Backup created"
else
    echo "⚠️  Backup creation had issues"
fi

# Update containers
echo "🔄 Updating containers and waiting for healthchecks..."
if docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d --wait; then
    echo "✅ All services updated and healthy"
else
    echo "❌ Deployment failed healthchecks. Rolling back..."
    docker-compose -f docker-compose.yml -f docker-compose.prod.yml down
    exit 1
fi

echo ""
echo "✅ Update complete!"
echo ""
echo "📋 Next steps:"
echo "1. Check Nextcloud admin panel: https://${NEXTCLOUD_DOMAIN}"
echo "2. Review: docker-compose -f docker-compose.yml -f docker-compose.prod.yml logs -f app"
echo "3. Verify: docker-compose -f docker-compose.yml -f docker-compose.prod.yml exec app php occ status"
