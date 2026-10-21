#!/bin/bash
################################################################################
# rewire-mail-to-mailpit.sh
#
# Redirects ALL outgoing mail of an ERPNext/Frappe stage instance to a Mailpit
# SMTP sink, so a freshly restored stage can never send real mail to real
# customers. Meant to run from the "reset stage" Jenkins jobs AFTER the
# restore/update of the stage scenario has finished.
#
# On the stage site (via the ERPNext backend container) it points every
# outgoing "Email Account", every "Email Domain" and the site_config mail
# defaults at Mailpit. Changes are written with frappe.db.set_value (bypasses
# the SMTP connection test a normal doc.save() would run) and committed in one
# transaction, so the rewire is atomic and always persists.
################################################################################

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
err()   { echo -e "${RED}✗${NC} $1" >&2; }
b64()   { printf '%s' "$1" | base64 | tr -d '\n'; }

usage() {
    cat <<'EOF'
Usage: rewire-mail-to-mailpit.sh --remote <ssh-config> --scenario-dir <path> [options]

  --remote <ssh-config>   SSH config/host of the stage server (required)
  --scenario-dir <path>   Absolute path of the stage scenario dir on the remote
                          host (contains .env). Derives the backend container
                          name (SCENARIO_NAME) and default site.
  --container <name>      Backend container name (skips --scenario-dir lookup)
  --site <site>           Frappe site (skips auto-detection)
  --smtp-host <host>      Mailpit host (default: mailpit.test.schmidtundtoechter.com)
  --smtp-port <port>      Mailpit port (default: 1025)
  --smtp-user <user>      Mailpit user (default: admin)
  --smtp-password <pw>    Mailpit password (default: env MAILPIT_SMTP_PASSWORD)
  --bench-path <path>     Bench path in container (default: /home/frappe/frappe-bench)
  --dry-run               List targets only, change nothing
  --help                  Show this help
EOF
}

# ── Defaults & arguments ─────────────────────────────────────────────────────
REMOTE="" SCENARIO_DIR="" CONTAINER="" SITE=""
SMTP_HOST="mailpit.test.schmidtundtoechter.com" SMTP_PORT="1025" SMTP_USER="admin"
SMTP_PASSWORD="${MAILPIT_SMTP_PASSWORD:-}"
BENCH_PATH="/home/frappe/frappe-bench" DRY_RUN="0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote)        REMOTE="$2"; shift 2 ;;
        --scenario-dir)  SCENARIO_DIR="$2"; shift 2 ;;
        --container)     CONTAINER="$2"; shift 2 ;;
        --site)          SITE="$2"; shift 2 ;;
        --smtp-host)     SMTP_HOST="$2"; shift 2 ;;
        --smtp-port)     SMTP_PORT="$2"; shift 2 ;;
        --smtp-user)     SMTP_USER="$2"; shift 2 ;;
        --smtp-password) SMTP_PASSWORD="$2"; shift 2 ;;
        --bench-path)    BENCH_PATH="$2"; shift 2 ;;
        --dry-run)       DRY_RUN="1"; shift ;;
        --help|-h)       usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

[[ -n "$REMOTE" ]]        || { err "--remote is required"; exit 1; }
[[ -n "$SMTP_HOST" ]]     || { err "--smtp-host must not be empty"; exit 1; }
[[ -n "$SMTP_USER" ]]     || { err "--smtp-user must not be empty"; exit 1; }
[[ -n "$SMTP_PASSWORD" ]] || { err "SMTP password missing (use --smtp-password or env MAILPIT_SMTP_PASSWORD)"; exit 1; }
[[ -n "$CONTAINER" || -n "$SCENARIO_DIR" ]] || { err "either --container or --scenario-dir is required"; exit 1; }

info "Testing SSH connection to ${REMOTE}..."
ssh "$REMOTE" "echo ok" >/dev/null 2>&1 || { err "Cannot reach '${REMOTE}' via SSH"; exit 1; }

# ── Resolve backend container + default site from the stage scenario .env ────
SCENARIO_SERVER_NAME=""
if [[ -z "$CONTAINER" ]]; then
    env_file="${SCENARIO_DIR%/}/.env"
    info "Reading scenario env: ${REMOTE}:${env_file}"
    _env="$(ssh "$REMOTE" "sh -c '. \"$env_file\" >/dev/null 2>&1; printf \"%s\\n%s\\n\" \"\$SCENARIO_NAME\" \"\$SCENARIO_SERVER_NAME\"'")" \
        || { err "Failed to read ${env_file} on ${REMOTE}"; exit 1; }
    SCENARIO_NAME="$(sed -n '1p' <<<"$_env")"
    SCENARIO_SERVER_NAME="$(sed -n '2p' <<<"$_env")"
    [[ -n "$SCENARIO_NAME" ]] || { err "SCENARIO_NAME not found in ${env_file}"; exit 1; }
    CONTAINER="${SCENARIO_NAME}_erpnext_backend_container"
fi
info "Backend container: ${CONTAINER}"

running="$(ssh "$REMOTE" "docker inspect -f '{{.State.Running}}' $CONTAINER 2>/dev/null || echo missing")"
[[ "$running" == "true" ]] || { err "Container '${CONTAINER}' is not running on ${REMOTE} (state: ${running})"; exit 1; }

# ── Resolve the Frappe site ──────────────────────────────────────────────────
# Only directories in sites/ that actually contain a site_config.json count, so
# a stale "default_site" pointer can never select a non-existent site.
real_sites="$(ssh "$REMOTE" "docker exec -i $CONTAINER bash -lc 'cd $BENCH_PATH/sites 2>/dev/null && ls -1 */site_config.json 2>/dev/null'" | sed 's#/site_config.json##; /^$/d')" || true
[[ -n "$real_sites" ]] || { err "No Frappe sites found in ${CONTAINER}:${BENCH_PATH}/sites"; exit 1; }
site_exists() { grep -qxF "$1" <<<"$real_sites"; }

if [[ -n "$SITE" ]]; then
    site_exists "$SITE" || { err "Given --site '$SITE' not found. Available: $(echo $real_sites)"; exit 1; }
else
    default_site="$(ssh "$REMOTE" "docker exec -i $CONTAINER cat ${BENCH_PATH}/sites/common_site_config.json" 2>/dev/null \
        | sed -n 's/.*"default_site"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    if   [[ -n "$default_site" ]] && site_exists "$default_site"; then SITE="$default_site"
    elif [[ -n "$SCENARIO_SERVER_NAME" ]] && site_exists "$SCENARIO_SERVER_NAME"; then SITE="$SCENARIO_SERVER_NAME"
    elif [[ "$(wc -l <<<"$real_sites")" == "1" ]]; then SITE="$real_sites"
    else err "Multiple sites found, please pass --site. Available: $(echo $real_sites)"; exit 1
    fi
fi
info "Target site: ${SITE}  (available: $(echo $real_sites))"
info "Outgoing mail target: ${SMTP_HOST}:${SMTP_PORT} (user: ${SMTP_USER})"
[[ "$DRY_RUN" == "1" ]] && warn "DRY-RUN: no changes will be written"

# ── Run the rewire inside the container ──────────────────────────────────────
# Config travels as base64 env vars (safe through ssh/docker quoting); the
# Python body is fully static. It runs from sites/ so Frappe's ../logs path
# resolves correctly.
tmp_py="/tmp/rewire_mail_$$.py"
ssh "$REMOTE" "docker exec -i \
    -e RW_SITE_B64=$(b64 "$SITE") \
    -e RW_HOST_B64=$(b64 "$SMTP_HOST") \
    -e RW_USER_B64=$(b64 "$SMTP_USER") \
    -e RW_PASS_B64=$(b64 "$SMTP_PASSWORD") \
    -e RW_SITESPATH_B64=$(b64 "${BENCH_PATH}/sites") \
    -e RW_PORT=$SMTP_PORT -e RW_DRYRUN=$DRY_RUN \
    $CONTAINER bash -lc 'cat > $tmp_py && cd $BENCH_PATH/sites && $BENCH_PATH/env/bin/python $tmp_py; rc=\$?; rm -f $tmp_py; exit \$rc'" <<'PYEOF'
import os, base64, frappe
from frappe.utils.password import set_encrypted_password
from frappe.installer import update_site_config

d = lambda k: base64.b64decode(os.environ[k]).decode()
SITE, HOST, USER, PASS, SITES = (d("RW_SITE_B64"), d("RW_HOST_B64"),
                                 d("RW_USER_B64"), d("RW_PASS_B64"), d("RW_SITESPATH_B64"))
PORT = int(os.environ["RW_PORT"])
DRY = os.environ["RW_DRYRUN"] == "1"

OUT = {"smtp_server": HOST, "smtp_port": PORT, "use_tls": 0, "use_ssl_for_outgoing": 0}

frappe.init(site=SITE, sites_path=SITES)
frappe.connect()
try:
    targets = []
    for name in frappe.get_all("Email Domain", pluck="name"):
        if not DRY:
            frappe.db.set_value("Email Domain", name, dict(OUT), update_modified=True)
        targets.append("Domain:" + name)

    for name in frappe.get_all("Email Account", filters={"enable_outgoing": 1}, pluck="name"):
        if not DRY:
            frappe.db.set_value("Email Account", name, {**OUT,
                "no_smtp_authentication": 0, "login_id_is_different": 1,
                "login_id": USER, "awaiting_password": 0}, update_modified=True)
            set_encrypted_password("Email Account", name, PASS, "password")
        targets.append("Account:" + name)

    if not DRY:
        for key, val in {"mail_server": HOST, "mail_port": PORT, "use_tls": 0,
                         "use_ssl": 0, "mail_login": USER, "mail_password": PASS}.items():
            update_site_config(key, val)
        targets.append("site_config:defaults")
        frappe.db.commit()

    print("Rewired %d outgoing mail target(s) to %s:%s on site %s" % (len(targets), HOST, PORT, SITE))
    for t in targets:
        print("  -", t)
finally:
    frappe.destroy()
PYEOF

if [[ "$DRY_RUN" == "1" ]]; then
    ok "Dry-run complete — no changes written."
else
    ok "All outgoing mail on '${SITE}' now routes to ${SMTP_HOST}:${SMTP_PORT}."
fi
