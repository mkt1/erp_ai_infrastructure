# setup-host-erpai.sh — Teil 2 von setup-host.sh, wird von dort eingebunden (source).
# Bereitet auf dem Server vor, was die Szenarien erpai, erpai-stage, erpai-dev und erpai-jenkins
# (und optional traefik) brauchen.
# Erwartet: SSHCONFIG, HAS_SUDO, SCRIPT_DIR, erpai.host.conf geladen (macht setup-host.sh),
#           mark_failure/mark_warning, TODOS.

INFRA_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "▶ Teil 2: Vorbereitung fuer die ERP-AI-Szenarien (${SCENARIO_NAMESPACE})"
echo "════════════════════════════════════════════════════════════════"

SCENARIO_DIR_LOCAL="${INFRA_DIR}/Scenarios/${SCENARIO_NAMESPACE}"
# Befehle auf dem Server laufen als root; ohne root-Login mit sudo.
if [ "$(ssh "${SSHCONFIG}" id -u)" = "0" ]; then RSUDO=""; else RSUDO="sudo -n"; fi
rsh() { ssh "${SSHCONFIG}" "$@"; }

# ── 2.1 Lokale Voraussetzungen ────────────────────────────────────────────────
echo "── 2.1 Lokal: scenario.deploy (MIMS-Submodul), Komponenten, Szenarien"
if [ -f "${INFRA_DIR}/MIMS/scenario.deploy" ]; then
    MIMS_ROOT_LOCAL="${INFRA_DIR}/MIMS"
    echo "✅ MIMS-Submodul vorhanden (${MIMS_ROOT_LOCAL})."
else
    echo "❌ MIMS-Submodul fehlt — git submodule update --init MIMS"
    mark_failure
    MIMS_ROOT_LOCAL=""
fi
for s in $SCENARIOS $SCENARIOS_OPTIONAL; do
    envf="${SCENARIO_DIR_LOCAL}/${s}.scenario.env"
    if [ ! -f "$envf" ]; then
        echo "❌ Szenario fehlt: ${envf}"; mark_failure; continue
    fi
    comp="$(sed -n 's/^SCENARIO_SRC_COMPONENT="\(.*\)"/\1/p' "$envf")"
    if [ -d "${INFRA_DIR}/Components/${comp}" ] || { [ -n "$MIMS_ROOT_LOCAL" ] && [ -d "${MIMS_ROOT_LOCAL}/Components/${comp}" ]; }; then
        echo "✅ ${SCENARIO_NAMESPACE}/${s} → Komponente ${comp}"
    else
        echo "❌ ${SCENARIO_NAMESPACE}/${s}: Komponente ${comp} nicht gefunden (weder im Repo noch in MIMS)."
        mark_failure
    fi
    # Der SSH-Config-Name im Szenario muss auf denselben Server zeigen
    sc="$(sed -n 's/^SCENARIO_SERVER_SSHCONFIG="\(.*\)"/\1/p' "$envf")"
    if ! grep -qE "^Host (.* )?${sc//./\\.}( |\$)" ~/.ssh/config; then
        echo "❌ ${s}: SSH-Config '${sc}' aus dem Szenario fehlt in ~/.ssh/config (Alias ergaenzen: 'Host ${SSHCONFIG} ${sc}')."
        mark_failure
    fi
done

# ── 2.2 Groesse des Servers ───────────────────────────────────────────────────
echo "── 2.2 Groesse des Servers (noetig: ${MIN_RAM_MB} MB RAM, ${MIN_CPUS} Kerne, ${MIN_DISK_GB} GB frei)"
RAM_MB="$(rsh "free -m | awk '/^Mem:/{print \$2}'")"
RAM_AVAIL_MB="$(rsh "free -m | awk '/^Mem:/{print \$7}'")"
CPUS="$(rsh nproc)"
DISK_GB="$(rsh "mkdir -p ${BASE_DIR} 2>/dev/null; df -BG --output=avail ${BASE_DIR} 2>/dev/null | tail -1 | tr -dc '0-9'")"
echo "   RAM ${RAM_MB:-?} MB (davon verfuegbar ${RAM_AVAIL_MB:-?} MB) · ${CPUS:-?} Kerne · ${DISK_GB:-?} GB frei unter ${BASE_DIR}"
if [ "${RAM_MB:-0}" -lt "$MIN_RAM_MB" ] || [ "${CPUS:-0}" -lt "$MIN_CPUS" ]; then
    echo "❌ Server zu klein fuer Jenkins + drei ERPNext. Der Image-Bau scheitert unter ~2 GB freiem RAM."
    mark_failure
    TODOS+=("Server vergroessern: mindestens ${MIN_RAM_MB} MB RAM / ${MIN_CPUS} Kerne")
else
    echo "✅ RAM und Kerne reichen."
fi
# Auf einem geteilten Server zaehlt der freie Speicher, nicht der eingebaute (README §4)
if [ "${RAM_AVAIL_MB:-0}" -lt 6000 ]; then
    echo "⚠️ Nur ${RAM_AVAIL_MB:-?} MB RAM verfuegbar — drei ERPNext-Instanzen brauchen im Betrieb ~5 GB, beim Image-Bau mehr."; mark_warning
fi
if [ "${DISK_GB:-0}" -lt "$MIN_DISK_GB" ]; then
    echo "⚠️ Wenig Plattenplatz (Images, drei Datenbanken, Backups)."; mark_warning
fi

# ── 2.3 Verzeichnisse ─────────────────────────────────────────────────────────
echo "── 2.3 Verzeichnisse unter ${BASE_DIR}"
# Das Backup-Verzeichnis gehoert frappe (uid ${FRAPPE_UID}): 'bench backup' schreibt als dieser Benutzer hinein.
if rsh "$RSUDO mkdir -p ${BACKUP_DIR} ${FRAPPE_SECRETS_DIR}/.ssh ${TRAEFIK_SECRETS_DIR} ${JENKINS_SECRETS_DIR} \
        && $RSUDO chmod 700 ${SECRETS_DIR} ${TRAEFIK_SECRETS_DIR} ${JENKINS_SECRETS_DIR} \
        && $RSUDO chmod 711 ${SECRETS_DIR} \
        && $RSUDO chown ${FRAPPE_UID}:${FRAPPE_UID} ${BACKUP_DIR}"; then
    echo "✅ ${BACKUP_DIR}, ${FRAPPE_SECRETS_DIR}/.ssh, ${TRAEFIK_SECRETS_DIR}, ${JENKINS_SECRETS_DIR}"
else
    echo "❌ Verzeichnisse konnten nicht angelegt werden."; mark_failure
fi

# ── 2.4 Deploy-Key fuer die private App ───────────────────────────────────────
echo "── 2.4 Deploy-Key fuer ${APP_REPO_SSH}"
KEY="${FRAPPE_SECRETS_DIR}/.ssh/${DEPLOY_KEY_NAME}"
rsh "set -e
if [ ! -f ${KEY} ]; then
    $RSUDO ssh-keygen -q -t ed25519 -N '' -C 'deploy-key-erp_ai_app@${SSHCONFIG}' -f ${KEY}
    echo '   Neuer Deploy-Key erzeugt.'
else
    echo '   Deploy-Key vorhanden, wird nicht ueberschrieben.'
fi
# SSH-Konfiguration fuer den Container: github.com mit genau diesem Schluessel
printf 'Host github.com\n    User git\n    IdentityFile ~/.ssh/${DEPLOY_KEY_NAME}\n    IdentitiesOnly yes\n    StrictHostKeyChecking yes\n' | $RSUDO tee ${FRAPPE_SECRETS_DIR}/.ssh/config >/dev/null
# Host-Schluessel von GitHub fest hinterlegen statt blind zu vertrauen
if ! grep -qs '^github.com ' ${FRAPPE_SECRETS_DIR}/.ssh/known_hosts; then
    ssh-keyscan -t ed25519,rsa,ecdsa github.com 2>/dev/null | $RSUDO tee ${FRAPPE_SECRETS_DIR}/.ssh/known_hosts >/dev/null
fi
$RSUDO chown -R ${FRAPPE_UID}:${FRAPPE_UID} ${FRAPPE_SECRETS_DIR}
$RSUDO chmod 700 ${FRAPPE_SECRETS_DIR} ${FRAPPE_SECRETS_DIR}/.ssh
$RSUDO chmod 600 ${KEY} ${FRAPPE_SECRETS_DIR}/.ssh/config
$RSUDO chmod 644 ${KEY}.pub ${FRAPPE_SECRETS_DIR}/.ssh/known_hosts
" || { echo "❌ Deploy-Key konnte nicht eingerichtet werden."; mark_failure; }

# Fingerabdruck von GitHub gegen den veroeffentlichten Wert pruefen (ed25519)
GH_FP="$(rsh "ssh-keygen -lf ${FRAPPE_SECRETS_DIR}/.ssh/known_hosts 2>/dev/null | awk '/ED25519/{print \$2}'")"
if [ "$GH_FP" = "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU" ]; then
    echo "✅ GitHub-Host-Schluessel stimmt mit dem veroeffentlichten Fingerabdruck ueberein."
else
    echo "❌ GitHub-Host-Schluessel weicht ab oder fehlt (${GH_FP:-leer}) — nicht fortfahren."; mark_failure
fi

# Hat der Schluessel Lesezugriff auf das Repo? Mit gh wird er sonst direkt eingetragen.
if rsh "$RSUDO env GIT_SSH_COMMAND='ssh -i ${KEY} -o IdentitiesOnly=yes -o UserKnownHostsFile=${FRAPPE_SECRETS_DIR}/.ssh/known_hosts -o StrictHostKeyChecking=yes' git ls-remote --heads ${APP_REPO_SSH} >/dev/null 2>&1"; then
    echo "✅ Deploy-Key hat Zugriff auf ${APP_REPO_SSH}."
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    tmp="$(mktemp)"; rsh "cat ${KEY}.pub" > "$tmp"
    if gh repo deploy-key add "$tmp" -R "${APP_REPO}" -t "ERPNext-Server ${SSHCONFIG} (nur lesend)"; then
        echo "✅ Deploy-Key per gh bei GitHub eingetragen (nur lesend)."
    else
        echo "⚠️ Deploy-Key konnte nicht per gh eingetragen werden — von Hand: ${APP_REPO_KEYS_URL}"; mark_warning
        TODOS+=("Deploy-Key bei GitHub eintragen: ${APP_REPO_KEYS_URL} — danach dieses Skript erneut laufen lassen")
    fi
    rm -f "$tmp"
else
    echo "⚠️ Deploy-Key ist bei GitHub noch nicht hinterlegt. Oeffentlicher Schluessel:"
    echo ""
    rsh "cat ${KEY}.pub" | sed 's/^/      /'
    echo ""
    echo "   Eintragen unter ${APP_REPO_KEYS_URL} (Add deploy key, OHNE Schreibzugriff)."
    mark_warning
    TODOS+=("Deploy-Key bei GitHub eintragen: ${APP_REPO_KEYS_URL} — danach dieses Skript erneut laufen lassen")
fi

# ── 2.5 Administrator-Kennwort der ERPNext-Sites ──────────────────────────────
echo "── 2.5 Administrator-Kennwort fuer ERPNext (${FRAPPE_SECRETS_DIR}/admin_password)"
rsh "set -e
f=${FRAPPE_SECRETS_DIR}/admin_password
if [ ! -s \$f ]; then
    umask 077
    openssl rand -base64 24 | tr -d '\n=+/' | cut -c1-28 | $RSUDO tee \$f >/dev/null
    echo '   Neues Kennwort erzeugt (28 Zeichen, zufaellig).'
else
    echo '   Kennwort vorhanden, wird nicht ueberschrieben.'
fi
$RSUDO chown ${FRAPPE_UID}:${FRAPPE_UID} \$f; $RSUDO chmod 600 \$f
" && echo "✅ Wird beim Anlegen der Site gesetzt. Anzeigen: ssh ${SSHCONFIG} cat ${FRAPPE_SECRETS_DIR}/admin_password" \
  || { echo "❌ Administrator-Kennwort konnte nicht angelegt werden."; mark_failure; }

# ── 2.6 Kennwort fuer das Traefik-Dashboard (nur wenn das Szenario traefik genutzt wird) ─
echo "── 2.6 Traefik-Dashboard (Benutzer admin) — nur fuer das optionale Szenario traefik"
TRAEFIK_ENV="${SCENARIO_DIR_LOCAL}/traefik.scenario.env"
if rsh "docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^traefik_'"; then
    echo "ℹ️  Auf dem Server laeuft bereits ein Traefik — das Szenario traefik wird NICHT ausgerollt, die ERP-AI-Szenarien haengen sich in dessen Netz 'traefik' (README §4)."
elif grep -q "^SCENARIO_BASICAUTH_PASSWORD='BITTE_SETZEN'" "$TRAEFIK_ENV"; then
    # Klartext bleibt auf dem Server (nur root); ins Szenario kommt nur der apr1-Hash.
    TRAEFIK_HASH="$(rsh "set -e
f=${TRAEFIK_SECRETS_DIR}/dashboard_password
if [ ! -s \$f ]; then umask 077; openssl rand -base64 24 | tr -d '\n=+/' | cut -c1-24 | $RSUDO tee \$f >/dev/null; fi
$RSUDO chmod 600 \$f
$RSUDO cat \$f | openssl passwd -apr1 -stdin")"
    if [[ "$TRAEFIK_HASH" == \$apr1\$* ]]; then
        TRAEFIK_HASH="$TRAEFIK_HASH" awk '
            /^SCENARIO_BASICAUTH_PASSWORD=/ { print "SCENARIO_BASICAUTH_PASSWORD=\x27" ENVIRON["TRAEFIK_HASH"] "\x27"; next }
            { print }' "$TRAEFIK_ENV" > "${TRAEFIK_ENV}.tmp" && mv "${TRAEFIK_ENV}.tmp" "$TRAEFIK_ENV"
        echo "✅ Hash in traefik.scenario.env eingetragen. Klartext: ssh ${SSHCONFIG} cat ${TRAEFIK_SECRETS_DIR}/dashboard_password"
    else
        echo "❌ Hash fuer das Traefik-Dashboard konnte nicht erzeugt werden."; mark_failure
    fi
else
    echo "✅ traefik.scenario.env traegt bereits einen Hash."
fi

# ── 2.7 Schluessel, mit dem Jenkins sich am Host anmeldet ─────────────────────
echo "── 2.7 Jenkins → Host (Credential 'host-ssh-key')"
JKEY="${JENKINS_SECRETS_DIR}/host-ssh-key"
rsh "set -e
if [ ! -f ${JKEY} ]; then
    $RSUDO ssh-keygen -q -t ed25519 -N '' -C 'jenkins-erpai@${SSHCONFIG}' -f ${JKEY}
    echo '   Neuer Schluessel erzeugt.'
else
    echo '   Schluessel vorhanden, wird nicht ueberschrieben.'
fi
$RSUDO chmod 600 ${JKEY}
mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
if ! grep -qF \"\$($RSUDO cat ${JKEY}.pub | awk '{print \$2}')\" ~/.ssh/authorized_keys; then
    $RSUDO cat ${JKEY}.pub >> ~/.ssh/authorized_keys
    echo '   Oeffentlicher Schluessel in authorized_keys eingetragen.'
fi
" && echo "✅ Privater Schluessel fuer die Jenkins-Credential: ssh ${SSHCONFIG} cat ${JKEY}" \
  || { echo "❌ Jenkins-Schluessel konnte nicht eingerichtet werden."; mark_failure; }
TODOS+=("Nach dem Start von erpai-jenkins und dem Einrichtungsassistenten: ../jenkins/setup-jenkins.sh ausfuehren (legt Credentials und Jobs an), dann ../jenkins/setup-jenkins-customer.sh")

# ── 2.8 DNS ───────────────────────────────────────────────────────────────────
echo "── 2.8 DNS: zeigen die Namen auf diesen Server?"
PUBLIC_IP="$(rsh "curl -4 -s --max-time 8 https://api.ipify.org || true")"
echo "   Oeffentliche Adresse des Servers: ${PUBLIC_IP:-unbekannt}"
for d in $DOMAINS; do
    case "$d" in *example.de) echo "⚠️ ${d}: PLATZHALTER — Domain noch festlegen (README §4)"; mark_warning; continue ;; esac
    ip="$(dig +short A "$d" | tail -1)"
    if [ -z "$ip" ]; then
        echo "❌ ${d}: kein DNS-Eintrag"; mark_failure
        TODOS+=("DNS-Eintrag fuer ${d} anlegen")
    elif [ -n "$PUBLIC_IP" ] && [ "$ip" != "$PUBLIC_IP" ]; then
        echo "❌ ${d} → ${ip}, erwartet ${PUBLIC_IP}"; mark_failure
    else
        echo "✅ ${d} → ${ip}"
    fi
done

# ── 2.9 Namenskollisionen mit vorhandenen Szenarien ───────────────────────────
echo "── 2.9 Belegte Namen auf dem Server (Container-Praefixe der Szenarien)"
for s in $SCENARIOS; do
    if rsh "docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^${s}_'"; then
        echo "ℹ️  ${s}: Container mit diesem Praefix existieren schon — vermutlich ein frueherer Stand dieses Szenarios."
    else
        echo "✅ ${s}: Name frei."
    fi
done

# ── 2.10 SSH-Anmeldung (nur Bericht, es wird nichts umgestellt) ───────────────
echo "── 2.10 SSH-Anmeldung"
PWAUTH="$(rsh "$RSUDO sshd -T 2>/dev/null | awk '/^passwordauthentication/{print \$2}'")"
if [ "$PWAUTH" = "yes" ]; then
    echo "⚠️ Kennwort-Anmeldung per SSH ist erlaubt."
    mark_warning
    TODOS+=("Kennwort-Anmeldung abschalten (PasswordAuthentication no) — bewusst nicht automatisiert")
else
    echo "✅ Kennwort-Anmeldung per SSH ist abgeschaltet."
fi

echo ""
echo "▶ Naechster Schritt, wenn oben keine Fehler stehen (in der Repo-Wurzel):"
for s in $SCENARIOS; do echo "   ./scenario.deploy ${SCENARIO_NAMESPACE}/${s} init,up -v"; done
