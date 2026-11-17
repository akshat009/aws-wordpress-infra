#!/usr/bin/env python3
"""
Configures dynamic domain and SSL reverse proxy headers in /var/www/html/wp-config.php.
Ensures WordPress works interchangeably on:
1. Standalone Direct Elastic IP (http://16.4.164.224)
2. Custom Domain (http://lab.asaxenadev.com)
3. Production HTTPS Load Balancer (https://lab.asaxenadev.com)
"""
import sys

config_path = "/var/www/html/wp-config.php"

try:
    with open(config_path, "r") as f:
        lines = f.readlines()
except FileNotFoundError:
    print(f"Notice: {config_path} not found. Skipping dynamic domain configuration.")
    sys.exit(0)

# Filter out old or duplicated dynamic host configurations
filtered = []
for line in lines:
    if any(k in line for k in ["WP_HOME", "WP_SITEURL", "HTTP_X_FORWARDED_PROTO", "HTTP_HOST", "$proto ="]):
        continue
    filtered.append(line)

content = "".join(filtered)

dynamic_block = """
// Dynamic Host & Reverse-Proxy SSL Configuration
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
if (isset($_SERVER['HTTP_HOST'])) {
    $proto = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ? 'https://' : 'http://';
    define('WP_HOME', $proto . $_SERVER['HTTP_HOST']);
    define('WP_SITEURL', $proto . $_SERVER['HTTP_HOST']);
}
"""

if "wp-settings.php" in content:
    content = content.replace(
        "require_once ABSPATH . 'wp-settings.php';",
        dynamic_block + "\nrequire_once ABSPATH . 'wp-settings.php';"
    )

with open(config_path, "w") as f:
    f.write(content)

print("Dynamic domain configuration applied successfully to wp-config.php")
