#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: scripts/migrate-db.sh
# Description: Two-way WordPress database migration between local MySQL (on the
#              standalone server) and Amazon RDS. Runs ON the standalone server,
#              dispatched by .github/workflows/migrate-database.yml through SSM.
#
# Safety order (nothing is overwritten until both backups are safely in S3):
#   1. dump the SOURCE database                       (the data being moved)
#   2. dump the TARGET database as it is now          (the side that gets overwritten)
#   3. upload both dumps to s3://<BACKUP_BUCKET>/db-backups/<time>-<direction>/
#   4. import the source into the target
#   5. point wp-config.php at the target
# If anything fails in steps 1-3, the script stops and nothing has changed.
# Copies also stay in /root/migration-backups/ (on this server's disk).
#
# Credentials (nothing hard-coded):
#   - Local MySQL: root over the unix socket (Ubuntu auth_socket; runs as root)
#   - RDS:         DB user + password read from SSM Parameter Store
#
# Usage:
#   sudo ./migrate-db.sh local-to-rds <RDS_HOST> <SSM_PARAM> <AWS_REGION> <BACKUP_BUCKET>
#   sudo ./migrate-db.sh rds-to-local <RDS_HOST> <SSM_PARAM> <AWS_REGION> <BACKUP_BUCKET>
#   e.g. SSM_PARAM = /<project>/db/password, BACKUP_BUCKET = <project>-artifacts-<account-id>
#   (migrate-database.yml passes all five)
# ==============================================================================

DIRECTION="${1:-}"
RDS_HOST="${2:-}"
DB_PASSWORD_PARAM="${3:-}"
AWS_REGION="${4:-}"
BACKUP_BUCKET="${5:-}"
DB_NAME="${DB_NAME:-wordpress}"
DB_USER="${DB_USER:-wpuser}"
WP_CONFIG="${WP_CONFIG:-/var/www/html/wp-config.php}"
BACKUP_DIR="${BACKUP_DIR:-/root/migration-backups}"

RDS_HOST=$(echo "$RDS_HOST" | cut -d: -f1) # strip :3306 if present

if [ -z "$DIRECTION" ] || [ -z "$RDS_HOST" ] || [ -z "$DB_PASSWORD_PARAM" ] || [ -z "$AWS_REGION" ] || [ -z "$BACKUP_BUCKET" ]; then
    echo "Usage: sudo $0 <local-to-rds | rds-to-local> <rds-endpoint-hostname> <ssm-param> <region> <backup-bucket>"
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

# mysql / mysqldump against one side: "local" or "rds"
db_dump() { # <side> -> gzip on stdout
    if [ "$1" = "rds" ]; then
        mysqldump --defaults-extra-file="$RDS_CNF" "${DUMP_OPTS[@]}" "$DB_NAME"
    else
        mysqldump "${DUMP_OPTS[@]}" "$DB_NAME"
    fi
}
db_exists() { # <side> -> 0 if the database exists
    local q="SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}'"
    if [ "$1" = "rds" ]; then
        [ "$(mysql --defaults-extra-file="$RDS_CNF" -N -e "$q")" = "1" ]
    else
        [ "$(mysql -N -e "$q")" = "1" ]
    fi
}

DUMP_OPTS=(--single-transaction --quick --routines --triggers --no-tablespaces --set-gtid-purged=OFF)

if [ "$DIRECTION" = "local-to-rds" ]; then
    SOURCE=local; TARGET=rds
else
    SOURCE=rds; TARGET=local
fi

STAMP="$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
SOURCE_FILE="$BACKUP_DIR/${STAMP}_${DIRECTION}_source-${SOURCE}.sql.gz"
TARGET_FILE="$BACKUP_DIR/${STAMP}_${DIRECTION}_target-${TARGET}-before.sql.gz"
S3_PREFIX="s3://${BACKUP_BUCKET}/db-backups/${STAMP}-${DIRECTION}"

echo "=================================================="
echo "  WordPress Database Migration"
echo "  Direction : $DIRECTION  ($SOURCE -> $TARGET)"
echo "  Database  : $DB_NAME"
echo "  RDS host  : $RDS_HOST"
echo "  Backups   : $S3_PREFIX/"
echo "  Time      : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=================================================="

# ---------------------------------------------------------------- 1. source
echo "Step 1: Backing up the SOURCE ($SOURCE)..."
db_dump "$SOURCE" | gzip > "$SOURCE_FILE"
chmod 600 "$SOURCE_FILE"
echo "  $SOURCE_FILE ($(du -h "$SOURCE_FILE" | cut -f1))"

# ---------------------------------------------------------------- 2. target (before)
echo "Step 2: Backing up the TARGET ($TARGET) before it is overwritten..."
if db_exists "$TARGET"; then
    db_dump "$TARGET" | gzip > "$TARGET_FILE"
    chmod 600 "$TARGET_FILE"
    echo "  $TARGET_FILE ($(du -h "$TARGET_FILE" | cut -f1))"
else
    TARGET_FILE=""
    echo "  Target database '$DB_NAME' doesn't exist yet: nothing to back up."
fi

# ---------------------------------------------------------------- 3. off-server copy
echo "Step 3: Uploading the backups to S3 (off this server)..."
for f in "$SOURCE_FILE" ${TARGET_FILE:+"$TARGET_FILE"}; do
    aws s3 cp --region "$AWS_REGION" --only-show-errors "$f" "$S3_PREFIX/$(basename "$f")"
    echo "  uploaded $(basename "$f")"
done
echo "Backups are safe in S3. Nothing has been changed yet."

# ---------------------------------------------------------------- 4. import
echo "Step 4: Importing into the TARGET ($TARGET)..."
if [ "$TARGET" = "rds" ]; then
    gunzip -c "$SOURCE_FILE" | mysql --defaults-extra-file="$RDS_CNF" "$DB_NAME"
else
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    gunzip -c "$SOURCE_FILE" | mysql "$DB_NAME"
    echo "  Syncing the local DB user with the password in SSM..."
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;"
fi

# ---------------------------------------------------------------- 5. switch WordPress
echo "Step 5: Pointing wp-config.php at the target..."
if [ "$TARGET" = "rds" ]; then
    set_define DB_HOST "$RDS_HOST"
else
    set_define DB_HOST "localhost"
fi
set_define DB_USER "$DB_USER"
set_define DB_PASSWORD "$DB_PASS"

echo "Validating PHP syntax..."
php -l "$WP_CONFIG"

echo "Reloading PHP-FPM and Nginx..."
systemctl reload nginx php*-fpm || true

echo "=================================================="
echo "SUCCESS: migration $DIRECTION complete."
echo "Backups (S3, kept by the bucket's lifecycle rule):"
echo "  $S3_PREFIX/$(basename "$SOURCE_FILE")"
[ -n "$TARGET_FILE" ] && echo "  $S3_PREFIX/$(basename "$TARGET_FILE")   <- $TARGET as it was before"
echo "Local copies: $BACKUP_DIR/"
echo "Undo: restore the 'before' file into $TARGET, e.g."
echo "  aws s3 cp $S3_PREFIX/<file>.sql.gz - | gunzip | mysql ...  (then set DB_HOST back)"
echo "=================================================="
