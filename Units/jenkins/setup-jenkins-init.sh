#!/bin/bash
################################################################################
# setup-jenkins-init.sh — ersetzt den Einrichtungsassistenten von Jenkins (einmalig, wiederholbar)
#
# Laeuft auf dem eigenen Rechner, arbeitet per SSH auf dem Server. Voraussetzung: Szenario erpai-jenkins laeuft.
# Was passiert:
#   1. Plugins (JENKINS_PLUGINS aus erpai.host.conf) mit jenkins-plugin-cli in das Plugin-Verzeichnis laden
#   2. init-Skript (jenkins-init.groovy) einspielen: Assistent abschliessen, Benutzerdatenbank als
#      Sicherheitsbereich, Benutzer ${DEVELOPER_JENKINS_USER} als Administrator (Kennwort zufaellig, nur auf dem
#      Server), API-Token "ausrollen", Jenkins-URL setzen, CSRF-Schutz an, Anonyme sehen nichts
#   3. Jenkins neu starten, Token abholen
#
# Ergebnis auf dem Server (nur dort, nur root):
#   _secrets/jenkins/<developer>_password    Kennwort fuer die Jenkins-Oberflaeche
#   _secrets/jenkins/<developer>_api_token   Token fuer ERPAI_JENKINS_TOKEN der Developer-Umgebung
#
# Usage: ./setup-jenkins-init.sh [sshconfig]
# Danach: ./setup-jenkins.sh (Credentials, Jobs) und ./setup-jenkins-customer.sh (Customer-Benutzer).
################################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../host/erpai.host.conf"
SSHCONFIG="${1:-$SSHCONFIG_DEFAULT}"
CONTAINER="${JENKINS_CONTAINER}"
USER_NAME="${DEVELOPER_JENKINS_USER}"
rsh() { ssh "${SSHCONFIG}" "$@"; }
RUN_ID="lauf-$(date +%Y%m%d%H%M%S)-$$"

echo "── 1. Plugins: ${JENKINS_PLUGINS}"
rsh "docker exec ${CONTAINER} jenkins-plugin-cli --plugins ${JENKINS_PLUGINS} --plugin-download-directory /var/jenkins_home/plugins --verbose 2>&1 | grep -E 'Downloaded|Skipping|already|Done|ERROR|error' | tail -15 || true"
echo "   geladen: $(rsh "docker exec ${CONTAINER} sh -c 'ls /var/jenkins_home/plugins/*.jpi 2>/dev/null | wc -l'") Plugin-Dateien"

echo "── 2. Kennwort fuer ${USER_NAME} (wird nur beim ersten Mal erzeugt)"
rsh "umask 077; mkdir -p ${JENKINS_SECRETS_DIR}
[ -s ${JENKINS_SECRETS_DIR}/${USER_NAME}_password ] || openssl rand -base64 18 | tr -d '/+=' | cut -c1-20 > ${JENKINS_SECRETS_DIR}/${USER_NAME}_password
chmod 600 ${JENKINS_SECRETS_DIR}/${USER_NAME}_password"

echo "── 3. init-Skript einspielen und Jenkins neu starten"
scp -q "${SCRIPT_DIR}/jenkins-init.groovy" "${SSHCONFIG}:/tmp/erpai-jenkins-init.groovy"
rsh "set -e
docker exec ${CONTAINER} mkdir -p /var/jenkins_home/init.groovy.d /var/jenkins_home/erpai-init
docker cp /tmp/erpai-jenkins-init.groovy ${CONTAINER}:/var/jenkins_home/init.groovy.d/erpai-init.groovy && rm -f /tmp/erpai-jenkins-init.groovy
docker cp ${JENKINS_SECRETS_DIR}/${USER_NAME}_password ${CONTAINER}:/var/jenkins_home/erpai-init/password
docker exec ${CONTAINER} sh -c 'echo ${RUN_ID} > /var/jenkins_home/erpai-init/run-id; echo ${USER_NAME} > /var/jenkins_home/erpai-init/user; echo ${JENKINS_URL} > /var/jenkins_home/erpai-init/url'
docker exec -u root ${CONTAINER} sh -c 'chown -R jenkins:jenkins /var/jenkins_home/init.groovy.d /var/jenkins_home/erpai-init /var/jenkins_home/plugins && chmod 700 /var/jenkins_home/erpai-init'
docker restart ${CONTAINER} >/dev/null"
echo "   Jenkins startet neu (laedt die Plugins)..."
for _ in $(seq 1 90); do
    if rsh "docker logs --since 5m ${CONTAINER} 2>&1 | grep -qF '[erpai-init] fertig (${RUN_ID}).'"; then break; fi
    sleep 4
done
rsh "docker logs --since 5m ${CONTAINER} 2>&1 | grep -F '[erpai-init]' | tail -12 || true"

echo "── 4. Token abholen und aufraeumen"
rsh "umask 077
if docker exec ${CONTAINER} test -s /var/jenkins_home/erpai-init-out/api-token; then
    docker exec ${CONTAINER} cat /var/jenkins_home/erpai-init-out/api-token > ${JENKINS_SECRETS_DIR}/${USER_NAME}_api_token
    chmod 600 ${JENKINS_SECRETS_DIR}/${USER_NAME}_api_token
    echo '   Token gespeichert: ${JENKINS_SECRETS_DIR}/${USER_NAME}_api_token'
else
    echo '   Kein neuer Token (schon vorhanden oder Skript nicht durchgelaufen).'
fi
docker exec ${CONTAINER} sh -c 'rm -f /var/jenkins_home/init.groovy.d/erpai-init.groovy; rm -rf /var/jenkins_home/erpai-init /var/jenkins_home/erpai-init-out'"
if rsh "docker logs --since 5m ${CONTAINER} 2>&1 | grep -qF '[erpai-init] fertig (${RUN_ID}).'"; then
    echo "✅ Jenkins eingerichtet: ${JENKINS_URL} — Benutzer ${USER_NAME}: ssh ${SSHCONFIG} cat ${JENKINS_SECRETS_DIR}/${USER_NAME}_password"
else
    echo "❌ Das init-Skript ist nicht durchgelaufen — Log: ssh ${SSHCONFIG} docker logs --since 5m ${CONTAINER}"
    exit 1
fi
