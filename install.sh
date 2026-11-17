#!/bin/bash
set -e

# 1. Add 2GB Swap Memory (Prevent OOM crashes on t3.micro)
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 2. Database Environment Variables (Passed from Terraform or defaults)
DB_NAME="${DB_NAME:-wordpress}"
DB_USER="${DB_USER:-wpuser}"
DB_PASS="${DB_PASS:-SecureLabPass2026!}"
DB_HOST="${DB_HOST:-localhost}"

# 3. System update and package installation
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx mysql-server mysql-client php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip php-intl unzip curl ed

# 4. If Standalone mode (DB_HOST is localhost or 127.0.0.1), configure local MySQL
if [ "$DB_HOST" = "localhost" ] || [ "$DB_HOST" = "127.0.0.1" ]; then
    echo "Configuring local MySQL server for Standalone mode..."
    systemctl enable --now mysql
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
fi

# 5. Enable & start Nginx
systemctl enable --now nginx

# 6. Automatically locate active PHP-FPM socket path
PHP_SOCKET=$(ls /run/php/php*-fpm.sock | head -n 1)

# 7. Download and deploy WordPress core files
cd /tmp
curl -s -O https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
rm -rf /var/www/html/*
cp -r wordpress/* /var/www/html/

# 8. Create dedicated Health Check file
echo "healthy" > /var/www/html/health.html

# 9. Configure Nginx Virtual Host for WordPress
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

# 10. Verify syntax and reload Nginx
nginx -t && systemctl reload nginx

# 11. Configure wp-config.php with database credentials
cd /var/www/html
cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/${DB_NAME}/" wp-config.php
sed -i "s/username_here/${DB_USER}/" wp-config.php
sed -i "s/password_here/${DB_PASS}/" wp-config.php
sed -i "s/localhost/${DB_HOST}/" wp-config.php

# 12. Enable Dynamic Domain, Reverse Proxy & IP Access (Must be placed before wp-settings.php)
DOMAIN_NAME="${DOMAIN_NAME:-lab.asaxenadev.com}"
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

# Apply production permissions
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
chmod 640 /var/www/html/wp-config.php

echo "WordPress automated installation complete!"
