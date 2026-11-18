#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: scripts/migrate-db.sh
# Description: Two-way WordPress database migration between local MySQL (on the
#              standalone server) and Amazon RDS. Runs ON the standalone server,
#              dispatched by .github/workflows/migrate-database.yml through SSM.
#
# Credentials (nothing hard-coded):
#   - Local MySQL: root over the unix socket (Ubuntu auth_socket; runs as root)
#   - RDS:         DB user + password read from SSM Parameter Store
#
# Usage:
#   sudo ./migrate-db.sh local-to-rds <RDS_HOST> [SSM_PARAM] [AWS_REGION]
#   sudo ./migrate-db.sh rds-to-local <RDS_HOST> [SSM_PARAM] [AWS_REGION]
# ==============================================================================

DIRECTION="${1:-}"
RDS_HOST="${2:-}"
DB_PASSWORD_PARAM="${3:-/wp-lab/db/password}"
AWS_REGION="${4:-ap-south-1}"
DB_NAME="${DB_NAME:-wordpress}"
DB_USER="${DB_USER:-wpuser}"
WP_CONFIG="/var/www/html/wp-config.php"
BACKUP_DIR="/root/migration-backups"

RDS_HOST=$(echo "$RDS_HOST" | cut -d: -f1) # strip :3306 if present

if [ -z "$DIRECTION" ] || [ -z "$RDS_HOST" ]; then
    echo "Usage: sudo $0 <local-to-rds | rds-to-local> <rds-endpoint-hostname> [ssm-param] [region]"
    exit 1
fi
if [ "$DIRECTION" != "local-to-rds" ] && [ "$DIRECTION" != "rds-to-local" ]; then
    echo "Error: invalid direction '$DIRECTION'. Use 'local-to-rds' or 'rds-to-local'."
    exit 1
fi
if ! systemctl is-active --quiet mysql; then
    echo "Error: local MySQL is not running. Run this on the standalone server."
    exit 1
fi

# AWS CLI (installed by install.sh on new servers; older servers may lack it)
export PATH="$PATH:/snap/bin"
if ! command -v aws >/dev/null 2>&1; then
    echo "Installing AWS CLI..."
    snap install aws-cli --classic
fi

DB_PASS=$(aws ssm get-parameter --region "$AWS_REGION" --name "$DB_PASSWORD_PARAM" \
    --with-decryption --query Parameter.Value --output text)

# RDS credentials go in a private option file, not on the command line
# (command-line passwords are visible to other processes via `ps`).
RDS_CNF=$(mktemp)
chmod 600 "$RDS_CNF"
trap 'rm -f "$RDS_CNF"' EXIT
printf '[client]\nhost="%s"\nuser="%s"\npassword="%s"\n' "$RDS_HOST" "$DB_USER" "$DB_PASS" > "$RDS_CNF"

# Replace a define('KEY', '...'); line in wp-config.php
set_define() {
    sed -i "s|define( *['\"]$1['\"] *, *['\"][^'\"]*['\"] *);|define( '$1', '$2' );|" "$WP_CONFIG"
}

DUMP_OPTS=(--single-transaction --quick --routines --triggers --no-tablespaces --set-gtid-purged=OFF)

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/wp_${DIRECTION}_$(date +%Y%m%d_%H%M%S).sql"

echo "=================================================="
echo "  WordPress Database Migration"
echo "  Direction : $DIRECTION"
echo "  Database  : $DB_NAME"
echo "  RDS host  : $RDS_HOST"
echo "  Time      : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=================================================="

if [ "$DIRECTION" = "local-to-rds" ]; then
    echo "Step 1: Exporting local MySQL..."
    mysqldump "${DUMP_OPTS[@]}" "$DB_NAME" > "$BACKUP_FILE"
    echo "Export complete ($(du -h "$BACKUP_FILE" | cut -f1))"

    echo "Step 2: Importing into Amazon RDS..."
    mysql --defaults-extra-file="$RDS_CNF" "$DB_NAME" < "$BACKUP_FILE"

    echo "Step 3: Pointing wp-config.php at RDS..."
    set_define DB_HOST "$RDS_HOST"
    set_define DB_USER "$DB_USER"
    set_define DB_PASSWORD "$DB_PASS"
else
    echo "Step 1: Exporting Amazon RDS..."
    mysqldump --defaults-extra-file="$RDS_CNF" "${DUMP_OPTS[@]}" "$DB_NAME" > "$BACKUP_FILE"
    echo "Export complete ($(du -h "$BACKUP_FILE" | cut -f1))"

    echo "Step 2: Importing into local MySQL..."
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql "$DB_NAME" < "$BACKUP_FILE"

    echo "Step 3: Syncing the local DB user with the password in SSM..."
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;"

    echo "Step 4: Pointing wp-config.php at local MySQL..."
    set_define DB_HOST "localhost"
    set_define DB_USER "$DB_USER"
    set_define DB_PASSWORD "$DB_PASS"
fi

echo "Validating PHP syntax..."
php -l "$WP_CONFIG"

echo "Reloading PHP-FPM and Nginx..."
systemctl reload nginx php*-fpm || true

gzip -f "$BACKUP_FILE"
chmod 600 "$BACKUP_FILE.gz"
echo "Safety copy of the dump kept at $BACKUP_FILE.gz"
echo "SUCCESS: migration $DIRECTION complete."
