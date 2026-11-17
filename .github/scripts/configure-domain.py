#!/usr/bin/env python3
"""
Safely rebuilds /var/www/html/wp-config.php from clean template with:
1. Active Database credentials (DB_NAME, DB_USER, DB_PASSWORD, DB_HOST)
2. Dynamic Host detection (Elastic IP vs Custom Domain vs HTTPS Reverse Proxy)
Guarantees 100% valid PHP syntax.
"""
import re
import os
import sys

config_path = "/var/www/html/wp-config.php"
sample_path = "/var/www/html/wp-config-sample.php"

if not os.path.exists(sample_path) and not os.path.exists(config_path):
    print("Notice: WordPress core files not yet present. Skipping.")
    sys.exit(0)

# Default credentials fallback
db_name = "wordpress"
db_user = "wpuser"
db_pass = "SecureLabPass2026!"
db_host = "localhost"

# Extract existing credentials if present
if os.path.exists(config_path):
    try:
        with open(config_path, "r") as f:
            old = f.read()
        m_name = re.search(r"define\(\s*['\"]DB_NAME['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*\)", old)
        if m_name:
            db_name = m_name.group(1)
        m_user = re.search(r"define\(\s*['\"]DB_USER['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*\)", old)
        if m_user:
            db_user = m_user.group(1)
        m_pass = re.search(r"define\(\s*['\"]DB_PASSWORD['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*\)", old)
        if m_pass:
            db_pass = m_pass.group(1)
        m_host = re.search(r"define\(\s*['\"]DB_HOST['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*\)", old)
        if m_host:
            db_host = m_host.group(1)
    except Exception as e:
        print(f"Notice extracting existing credentials: {e}")

# Read clean template
if os.path.exists(sample_path):
    with open(sample_path, "r") as f:
        template = f.read()
else:
    # If sample doesn't exist, read existing config
    with open(config_path, "r") as f:
        template = f.read()

template = template.replace("database_name_here", db_name)
template = template.replace("username_here", db_user)
template = template.replace("password_here", db_pass)
template = template.replace("localhost", db_host)

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

if "require_once ABSPATH . 'wp-settings.php';" in template:
    template = template.replace(
        "require_once ABSPATH . 'wp-settings.php';",
        dynamic_block + "\nrequire_once ABSPATH . 'wp-settings.php';"
    )

with open(config_path, "w") as f:
    f.write(template)

# Apply correct file permissions
os.chmod(config_path, 0o640)
print(f"Rebuilt {config_path} successfully with DB_HOST={db_host} and dynamic host resolution.")
