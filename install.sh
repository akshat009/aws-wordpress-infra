#!/bin/bash
# ==============================================================================
# install.sh - first-boot setup for every WordPress server (both modes)
#
# Terraform prepends these exports in user data (compute-alb.tf):
#   DB_NAME, DB_USER      database name and user
#   DB_HOST               "localhost" = standalone (local MySQL); otherwise the RDS endpoint
#   DB_PASSWORD_PARAM     SSM Parameter Store name holding the DB password
#   AWS_REGION            region for SSM / S3 calls
#   DOMAIN_NAME           public domain
#   ARTIFACT_BUCKET       S3 bucket with the latest wp-content release (optional)
#
# No secrets are passed in user data; the password is read from SSM at boot.
# ==============================================================================
set -eo pipefail

log() { echo "[install.sh] $*"; }

# 1. Add 2GB swap (prevents out-of-memory crashes on t3.micro)
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 2. Inputs. Terraform puts these exports in front of this script (compute-alb.tf,
#    local.boot_env). Project-specific values have no default: running by hand
#    needs them exported first, so a server can never boot with someone else's
#    domain, region or password path.
: "${DOMAIN_NAME:?DOMAIN_NAME must be set (Terraform boot_env)}"
: "${AWS_REGION:?AWS_REGION must be set (Terraform boot_env)}"
: "${DB_PASSWORD_PARAM:?DB_PASSWORD_PARAM must be set (Terraform boot_env)}"
DB_NAME="${DB_NAME:-wordpress}"
DB_USER="${DB_USER:-wpuser}"
DB_HOST="${DB_HOST:-localhost}"
ARTIFACT_BUCKET="${ARTIFACT_BUCKET:-}"

STANDALONE=false
if [ "$DB_HOST" = "localhost" ] || [ "$DB_HOST" = "127.0.0.1" ]; then
    STANDALONE=true
fi
# A standalone server always gets local MySQL installed (INSTALL_LOCAL_DB=true from
# Terraform), even when WordPress uses RDS, so rds-to-local migrations keep working.
INSTALL_LOCAL_DB="${INSTALL_LOCAL_DB:-$STANDALONE}"

log "Mode: $([ "$STANDALONE" = true ] && echo 'standalone (local MySQL)' || echo "fleet (RDS at $DB_HOST)")"

# 3. Packages (MySQL server only where the database lives on this machine)
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
PACKAGES="nginx mysql-client php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip php-intl unzip curl ed"
if [ "$INSTALL_LOCAL_DB" = true ]; then
    PACKAGES="$PACKAGES mysql-server"
fi
# shellcheck disable=SC2086
apt-get install -y $PACKAGES

# 4. AWS CLI (not shipped on Ubuntu 24.04 AMIs) - used for SSM and S3
export PATH="$PATH:/snap/bin"
if ! command -v aws >/dev/null 2>&1; then
    snap install aws-cli --classic
fi

# 5. Read the DB password from SSM Parameter Store.
#    The instance role can take a few seconds to become usable after boot, so retry.
DB_PASS="${DB_PASS:-}"
if [ -z "$DB_PASS" ]; then
    for attempt in $(seq 1 30); do
        if DB_PASS=$(aws ssm get-parameter --region "$AWS_REGION" --name "$DB_PASSWORD_PARAM" \
                --with-decryption --query Parameter.Value --output text 2>/dev/null) && [ -n "$DB_PASS" ]; then
            break
        fi
        log "Waiting for access to $DB_PASSWORD_PARAM (attempt $attempt/30)..."
        sleep 10
    done
fi
if [ -z "$DB_PASS" ]; then
    log "ERROR: could not read the DB password from SSM parameter $DB_PASSWORD_PARAM"
    exit 1
fi

# 6. Standalone only: create the local database and user
if [ "$INSTALL_LOCAL_DB" = true ]; then
    log "Configuring local MySQL server..."
    systemctl enable --now mysql
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
fi

# 7. Nginx
systemctl enable --now nginx
PHP_SOCKET=$(ls /run/php/php*-fpm.sock | head -n 1)

# 8. WordPress core
cd /tmp
curl -s -O https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
rm -rf /var/www/html/*
cp -r wordpress/* /var/www/html/

# 9. Health check file (used by the ALB target group)
echo "healthy" > /var/www/html/health.html

# 10. Nginx virtual host
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;

    server_name _;

    location = /health.html {
        access_log off;
        return 200 "healthy\n";
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCKET};
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
nginx -t && systemctl reload nginx

# 11. wp-config.php with database settings
#     (the generated password only uses characters that are safe in sed and PHP)
cd /var/www/html
cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/${DB_NAME}/" wp-config.php
sed -i "s/username_here/${DB_USER}/" wp-config.php
sed -i "s/password_here/${DB_PASS}/" wp-config.php
sed -i "s/localhost/${DB_HOST}/" wp-config.php

# 12. Dynamic domain, reverse proxy (ALB) HTTPS detection, and WP Offload Media
#     using the instance role. Must be placed before wp-settings.php.
sed -i "/require_once.*wp-settings.php/i \\
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {\\
    \$_SERVER['HTTPS'] = 'on';\\
}\\
if (isset(\$_SERVER['HTTP_HOST'])) {\\
    \$proto = (isset(\$_SERVER['HTTPS']) && \$_SERVER['HTTPS'] === 'on') ? 'https://' : 'http://';\\
    define('WP_HOME', \$proto . \$_SERVER['HTTP_HOST']);\\
    define('WP_SITEURL', \$proto . \$_SERVER['HTTP_HOST']);\\
} else {\\
    define('WP_HOME', 'http://${DOMAIN_NAME}');\\
    define('WP_SITEURL', 'http://${DOMAIN_NAME}');\\
}\\
define('AS3CF_SETTINGS', serialize(array(\\
    'provider' => 'aws',\\
    'use-server-roles' => true,\\
)));\\
" /var/www/html/wp-config.php

# 13. Latest app release (theme + plugins) from the artifacts bucket, so servers
#     launched later by the Auto Scaling Group match what deploy-app.yml shipped.
if [ -n "$ARTIFACT_BUCKET" ]; then
    if aws s3 cp --region "$AWS_REGION" "s3://${ARTIFACT_BUCKET}/releases/latest.tar.gz" /tmp/wp-content.tar.gz; then
        tar -xzf /tmp/wp-content.tar.gz -C /var/www/html/wp-content/
        rm -f /tmp/wp-content.tar.gz
        log "Applied latest app release from s3://${ARTIFACT_BUCKET}/releases/latest.tar.gz"
    else
        log "No app release found yet; continuing with stock wp-content."
    fi
fi

# 14. Production permissions
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
chmod 640 /var/www/html/wp-config.php

log "WordPress automated installation complete!"
