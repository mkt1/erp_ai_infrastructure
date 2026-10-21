#!/bin/bash
################################################################################
# setup-jenkins-customer.sh — legt in Jenkins den Benutzer der Customer-Umgebung an und erzeugt sein API-Token
#
# Laeuft auf dem eigenen Rechner, arbeitet per SSH auf dem Server. Voraussetzung: setup-jenkins.sh
# ist gelaufen (Job erpai-deploy-customer existiert). Was passiert, steht in jenkins-user-customer.groovy:
# Benutzer ${CUSTOMER_JENKINS_USER} (Kennwort zufaellig, nur auf dem Server), API-Token "ausrollen".
# Die Autorisierung bleibt "jeder Angemeldete darf alles" (wie in der Vorlage; bei Bedarf in Jenkins
# auf Matrix-Rechte umstellen).
#
# Ergebnis auf dem Server (nur dort, nur root):
#   _secrets/jenkins/<user>_password    Kennwort fuer die Jenkins-Oberflaeche
#   _secrets/jenkins/<user>_api_token   Token fuer ERPAI_JENKINS_TOKEN (Cloud-Umgebung oder erpai.env)
#
# Usage: ./setup-jenkins-customer.sh [sshconfig]
# Achtung: Das Skript startet Jenkins neu — laufende Jobs werden dabei abgebrochen.
################################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../host/erpai.host.conf"
SSHCONFIG="${1:-$SSHCONFIG_DEFAULT}"
CONTAINER="${JENKINS_CONTAINER}"
USER_NAME="${CUSTOMER_JENKINS_USER}"
rsh() { ssh "${SSHCONFIG}" "$@"; }
RUN_ID="lauf-$(date +%Y%m%d%H%M%S)-$$"

echo "── Kennwort fuer ${USER_NAME} (wird nur beim ersten Mal erzeugt)"
rsh "umask 077; mkdir -p ${JENKINS_SECRETS_DIR}
[ -s ${JENKINS_SECRETS_DIR}/${USER_NAME}_password ] || openssl rand -base64 18 | tr -d '/+=' | cut -c1-20 > ${JENKINS_SECRETS_DIR}/${USER_NAME}_password
chmod 600 ${JENKINS_SECRETS_DIR}/${USER_NAME}_password"

echo "── init-Skript einspielen und Jenkins neu starten"
scp -q "${SCRIPT_DIR}/jenkins-user-customer.groovy" "${SSHCONFIG}:/tmp/erpai-jenkins-user.groovy"
rsh "set -e
docker exec ${CONTAINER} mkdir -p /var/jenkins_home/init.groovy.d /var/jenkins_home/erpai-setup-user
docker cp /tmp/erpai-jenkins-user.groovy ${CONTAINER}:/var/jenkins_home/init.groovy.d/erpai-user.groovy && rm -f /tmp/erpai-jenkins-user.groovy
docker cp ${JENKINS_SECRETS_DIR}/${USER_NAME}_password ${CONTAINER}:/var/jenkins_home/erpai-setup-user/password
docker exec ${CONTAINER} sh -c 'echo ${RUN_ID} > /var/jenkins_home/erpai-setup-user/run-id; echo ${USER_NAME} > /var/jenkins_home/erpai-setup-user/user'
docker exec -u root ${CONTAINER} sh -c 'chown -R jenkins:jenkins /var/jenkins_home/init.groovy.d /var/jenkins_home/erpai-setup-user && chmod 700 /var/jenkins_home/erpai-setup-user'
docker restart ${CONTAINER} >/dev/null"
echo "   Jenkins startet neu..."
for _ in $(seq 1 60); do
    if rsh "docker logs --since 3m ${CONTAINER} 2>&1 | grep -qF '[erpai-user] fertig (${RUN_ID}).'"; then break; fi
    sleep 3
done
rsh "docker logs --since 3m ${CONTAINER} 2>&1 | grep -F '[erpai-user]' | tail -10 || true"

echo "── Token abholen und aufraeumen"
rsh "umask 077
if docker exec ${CONTAINER} test -s /var/jenkins_home/erpai-setup-user-out/api-token; then
    docker exec ${CONTAINER} cat /var/jenkins_home/erpai-setup-user-out/api-token > ${JENKINS_SECRETS_DIR}/${USER_NAME}_api_token
    chmod 600 ${JENKINS_SECRETS_DIR}/${USER_NAME}_api_token
    echo '   Token gespeichert: ${JENKINS_SECRETS_DIR}/${USER_NAME}_api_token'
else
    echo '   Kein neuer Token (schon vorhanden oder Skript nicht durchgelaufen).'
fi
docker exec ${CONTAINER} sh -c 'rm -f /var/jenkins_home/init.groovy.d/erpai-user.groovy; rm -rf /var/jenkins_home/erpai-setup-user /var/jenkins_home/erpai-setup-user-out'"
if rsh "docker logs --since 3m ${CONTAINER} 2>&1 | grep -qF '[erpai-user] fertig (${RUN_ID}).'"; then
    echo "✅ Benutzer ${USER_NAME} eingerichtet. Zugangsdaten: ssh ${SSHCONFIG} cat ${JENKINS_SECRETS_DIR}/${USER_NAME}_password ${JENKINS_SECRETS_DIR}/${USER_NAME}_api_token"
else
    echo "❌ Das Skript ist nicht durchgelaufen — Log: ssh ${SSHCONFIG} docker logs --since 5m ${CONTAINER}"
    exit 1
fi
