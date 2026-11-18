#!/usr/bin/env python3
"""
Runs on every web server during Deploy WordPress Application Code (deploy-app.yml).

NEVER rewrites wp-config.php. It only ADDS a piece that is missing, once:
  1. Dynamic host + reverse-proxy HTTPS detection (WP_HOME / WP_SITEURL from the
     request, HTTPS behind the ALB via X-Forwarded-Proto)
  2. AS3CF_SETTINGS for WP Offload Media using the instance's IAM role (no keys)

Servers built by install.sh already have both, so for them this changes nothing.
Everything else in the file (database settings, salts, anything added by hand,
e.g. extra AS3CF_SETTINGS keys) is left exactly as it is.

Safety:
  - edits in place (keeps the file's owner www-data) after a backup copy
  - if wp-config.php is missing or has no wp-settings.php line, it stops (exit 1)
    and writes nothing; it never creates a config or guesses credentials
"""
import os
import shutil
import sys
import time

CONFIG_PATH = os.environ.get("WP_CONFIG", "/var/www/html/wp-config.php")
ANCHOR = "require_once ABSPATH . 'wp-settings.php';"

DYNAMIC_HOST_BLOCK = """
// Dynamic Host & Reverse-Proxy SSL Configuration (added by configure-domain.py)
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
if (isset($_SERVER['HTTP_HOST'])) {
    $proto = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ? 'https://' : 'http://';
    define('WP_HOME', $proto . $_SERVER['HTTP_HOST']);
    define('WP_SITEURL', $proto . $_SERVER['HTTP_HOST']);
}
"""

OFFLOAD_BLOCK = """
// WP Offload Media - IAM role authentication, no static AWS keys (added by configure-domain.py)
define('AS3CF_SETTINGS', serialize(array(
    'provider' => 'aws',
    'use-server-roles' => true,
)));
"""

if not os.path.exists(CONFIG_PATH):
    print(f"Error: {CONFIG_PATH} not found. It is created once by install.sh; nothing written.")
    sys.exit(1)

with open(CONFIG_PATH, "r") as f:
    config = f.read()

missing = []
if "HTTP_X_FORWARDED_PROTO" not in config:
    missing.append(("dynamic host / reverse-proxy HTTPS", DYNAMIC_HOST_BLOCK))
if "AS3CF_SETTINGS" not in config:
    missing.append(("WP Offload Media IAM-role settings", OFFLOAD_BLOCK))

if not missing:
    print(f"{CONFIG_PATH} already has everything it needs: left untouched.")
    sys.exit(0)

if ANCHOR not in config:
    print(f"Error: '{ANCHOR}' not found in {CONFIG_PATH}; refusing to edit it.")
    sys.exit(1)

backup = f"{CONFIG_PATH}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
shutil.copy2(CONFIG_PATH, backup)
os.chmod(backup, 0o600)

addition = "".join(block for _, block in missing)
config = config.replace(ANCHOR, addition + "\n" + ANCHOR, 1)

# Write in place: the file keeps its owner (www-data) and permissions
with open(CONFIG_PATH, "w") as f:
    f.write(config)

print(f"Added to {CONFIG_PATH}: {', '.join(name for name, _ in missing)}. Backup: {backup}")
print("Nothing else in the file was changed.")
