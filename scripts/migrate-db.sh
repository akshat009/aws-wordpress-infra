#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: scripts/migrate-db.sh
# Description: Automated two-way database migration between Local MySQL and Amazon RDS.
#              Enables seamless transition from Budget Standalone to Enterprise HA.
#
# Usage:
#   sudo ./scripts/migrate-db.sh local-to-rds <RDS_ENDPOINT>
#   sudo ./scripts/migrate-db.sh rds-to-local <RDS_ENDPOINT>
# ==============================================================================

DIRECTION="${1:-local-to-rds}"
RDS_HOST="${2:-}"
DB_NAME="${DB_NAME:-wordpress}"
DB_USER="${DB_USER:-wpuser}"
DB_PASS="${DB_PASS:-SecureLabPass2026!}"

# Strip port :3306 if present
RDS_HOST=$(echo "$RDS_HOST" | cut -d: -f1)

if [ -z "$RDS_HOST" ]; then
    echo "❌ Error: RDS host endpoint required!"
    echo "Usage: sudo $0 <local-to-rds | rds-to-local> <rds-endpoint-hostname>"
    exit 1
fi

echo "=================================================="
echo "  WordPress Universal Database Migration Tool     "
echo "=================================================="
echo "Migration Direction : $DIRECTION"
echo "Database Name       : $DB_NAME"
echo "Database User       : $DB_USER"
echo "Target RDS Host     : $RDS_HOST"
echo "Timestamp           : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=================================================="

BACKUP_FILE="/tmp/wp_migration_$(date +%Y%m%d_%H%M%S).sql"

if [ "$DIRECTION" = "local-to-rds" ]; then
    echo "📦 Step 1: Exporting Local MySQL database..."
    mysqldump -u "$DB_USER" -p"$DB_PASS" \
        --single-transaction \
        --quick \
        --routines \
        --triggers \
        "$DB_NAME" > "$BACKUP_FILE"
    
    echo "✅ Export complete! Backup size: $(ls -lh "$BACKUP_FILE" | awk '{print $5}')"

    echo "🚀 Step 2: Streaming data into Amazon RDS MySQL ($RDS_HOST)..."
    mysql -h "$RDS_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$BACKUP_FILE"
    echo "✅ Import into Amazon RDS completed successfully!"

    echo "🔧 Step 3: Updating /var/www/html/wp-config.php DB_HOST to RDS..."
    sed -i "s/define(\s*['\"]DB_HOST['\"]\s*,\s*['\"][^'\"]*['\"]\s*);/define('DB_HOST', '$RDS_HOST');/" /var/www/html/wp-config.php
    
    echo "🔍 Step 4: Validating PHP syntax..."
    php -l /var/www/html/wp-config.php

    echo "🔄 Step 5: Reloading Nginx & PHP-FPM daemons..."
    systemctl reload nginx php*-fpm || true

    echo "🎉 SUCCESS: WordPress is now running on Amazon RDS ($RDS_HOST)!"

elif [ "$DIRECTION" = "rds-to-local" ]; then
    echo "📦 Step 1: Exporting Amazon RDS MySQL database ($RDS_HOST)..."
    mysqldump -h "$RDS_HOST" -u "$DB_USER" -p"$DB_PASS" \
        --single-transaction \
        --quick \
        --routines \
        --triggers \
        "$DB_NAME" > "$BACKUP_FILE"
    
    echo "✅ Export complete! Backup size: $(ls -lh "$BACKUP_FILE" | awk '{print $5}')"

    echo "🚀 Step 2: Streaming data into Local MySQL daemon..."
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$BACKUP_FILE"
    echo "✅ Import into Local MySQL completed successfully!"

    echo "🔧 Step 3: Updating /var/www/html/wp-config.php DB_HOST to localhost..."
    sed -i "s/define(\s*['\"]DB_HOST['\"]\s*,\s*['\"][^'\"]*['\"]\s*);/define('DB_HOST', 'localhost');/" /var/www/html/wp-config.php
    
    echo "🔍 Step 4: Validating PHP syntax..."
    php -l /var/www/html/wp-config.php

    echo "🔄 Step 5: Reloading Nginx & PHP-FPM daemons..."
    systemctl reload nginx php*-fpm || true

    echo "🎉 SUCCESS: WordPress is now running on Local MySQL (localhost)!"

else
    echo "❌ Error: Invalid direction '$DIRECTION'. Use 'local-to-rds' or 'rds-to-local'."
    exit 1
fi

rm -f "$BACKUP_FILE"
echo "🧹 Temporary backup file cleaned up."
