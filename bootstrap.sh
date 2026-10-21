#!/usr/bin/env bash
# bootstrap.sh — richtet das komplette ERP-AI-Setup aus diesem Repo ein (oder bringt es auf Stand).
#
# Liest Units/host/erpai.host.conf (Server, Namensraum, Szenarien) und arbeitet die Schritte aus
# docs/SETUP.md in Reihenfolge ab. Jeder Schritt ist wiederholbar; was schon da ist, bleibt.
#
# Usage: ./bootstrap.sh [--skip-host] [--no-scenarios] [--only <szenario>[,<szenario>]] [--jenkins] [--dry-run]
#   (ohne Optionen)   Submodule, Host-Setup, alle Szenarien aus SCENARIOS mit init,up
#   --skip-host       Host-Setup ueberspringen (schon gelaufen)
#   --jenkins         zusaetzlich Jenkins einrichten: setup-jenkins-init.sh (Plugins, Assistent, Benutzer
#                     developer), setup-jenkins.sh (Credentials, Jobs), setup-jenkins-customer.sh — kein Browser noetig
#   --only a,b        nur diese Szenarien ausrollen
#   --no-scenarios    keine Szenarien anfassen (z. B. nur --jenkins)
#   --dry-run         nur zeigen, was laufen wuerde
# Voraussetzungen auf dem eigenen Rechner: ssh-Alias aus ssh-config.example in ~/.ssh/config, gh angemeldet,
# dig. Server-Vorbedingungen (Docker, Traefik) prueft setup-host.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
. Units/host/erpai.host.conf

SKIP_HOST=0; DO_JENKINS=0; ONLY=""; NO_SCEN=0; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-host) SKIP_HOST=1; shift ;;
        --jenkins) DO_JENKINS=1; shift ;;
        --only) ONLY="${2//,/ }"; shift 2 ;;
        --no-scenarios) NO_SCEN=1; shift ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
done
run() { echo "▶ $*"; [ "$DRY" = 1 ] || "$@"; }

echo "════ 1. Submodule (MIMS, erp_ai_app)"
run git submodule update --init

if [ "$SKIP_HOST" = 0 ]; then
    echo "════ 2. Host vorbereiten: ${SSHCONFIG_DEFAULT}"
    run bash -c "cd Units/host && ./setup-host.sh </dev/null"
else
    echo "════ 2. Host-Setup uebersprungen (--skip-host)"
fi

echo "════ 3. Szenarien ausrollen (Namensraum ${SCENARIO_NAMESPACE})"
[ "$NO_SCEN" = 1 ] && echo "   uebersprungen (--no-scenarios)"
for s in $([ "$NO_SCEN" = 1 ] || echo "${ONLY:-$SCENARIOS}"); do
    if [ "$DRY" = 0 ] && ./scenario.deploy "${SCENARIO_NAMESPACE}/${s}" test -s >/dev/null 2>&1 \
        && ssh "${SSHCONFIG_DEFAULT}" "docker ps --format '{{.Names}}' | grep -q '^${s}_'" ; then
        echo "   ${s}: laeuft schon — init,down,up nur bei Aenderungen an Szenario oder Komponente (README §7)"
        continue
    fi
    run ./scenario.deploy "${SCENARIO_NAMESPACE}/${s}" init,up -v
done

if [ "$DO_JENKINS" = 1 ]; then
    echo "════ 4. Jenkins: Plugins und Benutzer developer, Credentials und Jobs, Benutzer customer"
    run bash -c "cd Units/jenkins && ./setup-jenkins-init.sh"
    run bash -c "cd Units/jenkins && ./setup-jenkins.sh"
    run bash -c "cd Units/jenkins && ./setup-jenkins-customer.sh"
else
    echo "════ 4. Jenkins uebersprungen — einrichten mit: ./bootstrap.sh --skip-host --no-scenarios --jenkins"
fi
echo "✅ bootstrap durch. Stand und Pruefung: docs/SETUP.md"
