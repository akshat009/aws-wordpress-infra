#!/bin/bash
# ==============================================================================
# File: .github/scripts/nginx-site.sh
# Runs ON the single (standalone) web server, sent by install-ssl.yml via SSM.
#
# Writes ONE Nginx site that works both directly on the Elastic IP and behind
# the Application Load Balancer (enable_alb = true):
#
#   request                                         result
#   /health.html (ALB health check) or ACME check   always served on port 80
#   came through the ALB (X-Forwarded-Proto https)  served on port 80
#   plain HTTP straight to the server               301 -> https  (only if a cert exists)
#   HTTPS straight to the server                    served with the Let's Encrypt cert
#
# Why: "certbot --nginx --redirect" makes port 80 answer 301 for everything.
# The ALB always talks to the server on port 80, so its health check failed and
# visitors looped HTTPS -> HTTP -> HTTPS. This site keeps the redirect for direct
# visitors but never for the ALB.
#
# Safe to run any number of times. Backs up the old config and restores it if
# the new one fails "nginx -t" or the local health check.
#
# Usage: nginx-site.sh <domain>
# ==============================================================================
set -euo pipefail

DOMAIN="${1:?usage: nginx-site.sh <domain>}"
SITE=/etc/nginx/sites-available/default
LINK=/etc/nginx/sites-enabled/default
CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"
WEB_ROOT=/var/www/html

PHP_SOCKET=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n 1 || true)
if [ -z "$PHP_SOCKET" ]; then
    echo "ERROR: no PHP-FPM socket found in /run/php/" >&2
    exit 1
fi

# 1. Backup of the current site config
BACKUP="/root/nginx-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
[ -e "$SITE" ] && cp -a "$SITE" "$BACKUP/sites-available-default"
[ -e "$LINK" ] && cp -a "$LINK" "$BACKUP/sites-enabled-default"
echo "Backup of the old config: $BACKUP"

restore() {
    echo "Restoring the previous Nginx config from $BACKUP" >&2
    rm -f "$LINK"
    [ -e "$BACKUP/sites-available-default" ] && cp -a "$BACKUP/sites-available-default" "$SITE"
    [ -e "$BACKUP/sites-enabled-default" ] && cp -a "$BACKUP/sites-enabled-default" "$LINK"
    nginx -t && systemctl reload nginx || true
}

# 2. HTTPS part, only when a Let's Encrypt certificate exists for this domain
SSL_BLOCK=""
REDIRECT_BLOCK=""
if [ -s "$CERT_DIR/fullchain.pem" ] && [ -s "$CERT_DIR/privkey.pem" ]; then
    echo "Certificate found for $DOMAIN: enabling HTTPS on 443 + redirect for direct HTTP visitors"
    SSL_OPTIONS=""
    [ -f /etc/letsencrypt/options-ssl-nginx.conf ] && SSL_OPTIONS="    include /etc/letsencrypt/options-ssl-nginx.conf;"
    [ -f /etc/letsencrypt/ssl-dhparams.pem ] && SSL_OPTIONS="${SSL_OPTIONS}
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;"
    SSL_BLOCK="    listen 443 ssl;
    listen [::]:443 ssl;
    ssl_certificate ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;
${SSL_OPTIONS}"
    # Redirect only when ALL three are true: plain HTTP, not from the ALB,
    # not the health check / Let's Encrypt challenge. ("if" can't combine
    # conditions, so each one adds a letter and only "HXU" redirects.)
    # $request_uri (the original path), not $uri: WordPress's try_files
    # fallback rewrites $uri to /index.php, and these rules run again after it.
    REDIRECT_BLOCK='    set $redirect_to_https "";
    if ($scheme = http) { set $redirect_to_https "H"; }
    if ($http_x_forwarded_proto != "https") { set $redirect_to_https "${redirect_to_https}X"; }
    if ($request_uri !~ "^/(health\.html|\.well-known/acme-challenge/)") { set $redirect_to_https "${redirect_to_https}U"; }
    if ($redirect_to_https = "HXU") { return 301 https://$host$request_uri; }'
else
    echo "No certificate for $DOMAIN: plain HTTP site (the ALB or nothing handles HTTPS)"
fi

# 3. Write the site (same locations as install.sh step 10)
cat > "$SITE" <<EOF
# Managed by .github/scripts/nginx-site.sh (install-ssl.yml). Works with and without the ALB.
server {
    listen 80 default_server;
    listen [::]:80 default_server;
${SSL_BLOCK}
    server_name _ ${DOMAIN};

    root ${WEB_ROOT};
    index index.php index.html index.htm;

${REDIRECT_BLOCK}

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
ln -sf "$SITE" "$LINK"

# 4. Validate, reload, and prove the health check answers 200 on port 80
if ! nginx -t; then
    echo "ERROR: new config failed nginx -t" >&2
    restore
    exit 1
fi
systemctl reload nginx
sleep 1

HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/health.html || echo 000)
if [ "$HEALTH" != "200" ]; then
    echo "ERROR: http://127.0.0.1/health.html returned $HEALTH (expected 200)" >&2
    restore
    exit 1
fi
echo "Nginx site written: port 80 health check = 200, ALB-ready."
