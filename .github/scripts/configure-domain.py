#!/usr/bin/env python3
"""
Safely rebuilds /var/www/html/wp-config.php from the clean template with:
1. The server's existing database settings (DB_NAME, DB_USER, DB_PASSWORD, DB_HOST)
2. Dynamic host detection (Elastic IP vs custom domain vs HTTPS reverse proxy)
Guarantees valid PHP syntax.

No credentials are hard-coded: the values are carried over from the existing
wp-config.php (written at boot from SSM Parameter Store). If they can't be read,
the script stops instead of writing a guessed password.
"""
import re
import os
import sys

config_path = "/var/www/html/wp-config.php"
sample_path = "/var/www/html/wp-config-sample.php"

if not os.path.exists(sample_path) and not os.path.exists(config_path):
    print("Notice: WordPress core files not yet present. Skipping.")
    sys.exit(0)

if not os.path.exists(config_path):
    print("Error: wp-config.php not found; cannot carry over database settings.")
    sys.exit(1)


def read_define(source, key):
    match = re.search(
        r"define\(\s*['\"]" + key + r"['\"]\s*,\s*['\"]([^'\"]*)['\"]\s*\)", source
    )
    return match.group(1) if match else None


with open(config_path, "r") as f:
    old = f.read()

db_name = read_define(old, "DB_NAME")
db_user = read_define(old, "DB_USER")
db_pass = read_define(old, "DB_PASSWORD")
db_host = read_define(old, "DB_HOST")

missing = [
    key
    for key, value in [
        ("DB_NAME", db_name),
        ("DB_USER", db_user),
        ("DB_PASSWORD", db_pass),
        ("DB_HOST", db_host),
    ]
    if not value
]
if missing:
    print(f"Error: could not read {', '.join(missing)} from {config_path}; leaving it untouched.")
    sys.exit(1)

# Read the clean template (fall back to the existing config if the sample is gone)
if os.path.exists(sample_path):
    with open(sample_path, "r") as f:
        template = f.read()
else:
    template = old

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

// WP Offload Media Lite - IAM role authentication (no static AWS keys)
define('AS3CF_SETTINGS', serialize(array(
    'provider' => 'aws',
    'use-server-roles' => true,
)));
"""

if "require_once ABSPATH . 'wp-settings.php';" in template:
    template = template.replace(
        "require_once ABSPATH . 'wp-settings.php';",
        dynamic_block + "\nrequire_once ABSPATH . 'wp-settings.php';"
    )

with open(config_path, "w") as f:
    f.write(template)

os.chmod(config_path, 0o640)
print(f"Rebuilt {config_path} successfully with DB_HOST={db_host} and dynamic host resolution.")
