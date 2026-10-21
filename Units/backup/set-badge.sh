#!/bin/bash
# set-badge.sh — sets the badge text of a Site Branding Rule on a remote ERPNext instance.
#
# Vom Deploy-Job (Jenkinsfile.deploy) aufgerufen, damit die Dev-Instanz zeigt, welcher Commit
# gerade ausgerollt ist: "CUSTOMER · 80cd60a · 21.10. 01:05". Kein Release, nur Kennzeichnung.
#
# Usage: set-badge.sh --remote <sshconfig> --backend <container> --site <site> --rule <rule_name> --text <text>
# Exit 0 auch, wenn die Regel fehlt (dann nur Hinweis) — das Badge darf ein Deployment nie scheitern lassen.
set -uo pipefail
REMOTE=""; BACKEND=""; SITE=""; RULE="CUSTOMER"; TEXT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --remote) REMOTE="$2"; shift 2 ;;
        --backend) BACKEND="$2"; shift 2 ;;
        --site) SITE="$2"; shift 2 ;;
        --rule) RULE="$2"; shift 2 ;;
        --text) TEXT="$2"; shift 2 ;;
        *) echo "Unbekannter Parameter: $1" >&2; exit 2 ;;
    esac
done
[ -n "$REMOTE" ] && [ -n "$BACKEND" ] && [ -n "$SITE" ] && [ -n "$TEXT" ] || { echo "set-badge.sh: --remote, --backend, --site, --text sind Pflicht" >&2; exit 2; }

bench_exec() {
    # $1 = Funktion, $2 = kwargs als Python-Dict (einfache Anfuehrungszeichen innen)
    ssh "$REMOTE" "docker exec $BACKEND bench --site $SITE execute $1 --kwargs \"$2\"" 2>/dev/null
}
name="$(bench_exec frappe.client.get_value "{'doctype':'Site Branding Rule','filters':{'rule_name':'$RULE'},'fieldname':'name'}" | grep -o '"name": *"[^"]*"' | cut -d'"' -f4)"
if [ -z "$name" ]; then
    echo "   Keine Badge-Regel '$RULE' gefunden — Badge unveraendert (unkritisch)."
    exit 0
fi
if bench_exec frappe.client.set_value "{'doctype':'Site Branding Rule','name':'$name','fieldname':'badge_text','value':'$TEXT'}" >/dev/null; then
    echo "   Badge '$RULE': $TEXT"
else
    echo "   Badge '$RULE' nicht gesetzt (unkritisch)."
fi
exit 0
