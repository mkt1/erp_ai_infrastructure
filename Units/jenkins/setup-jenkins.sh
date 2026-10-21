#!/bin/bash
################################################################################
# setup-jenkins.sh — richtet im laufenden Jenkins Credentials und Jobs fuer ERP AI ein
#
# Laeuft auf dem eigenen Rechner, arbeitet per SSH auf dem Server. Voraussetzung:
# Szenario erpai-jenkins laeuft, der Einrichtungsassistent ist durchlaufen (Plugins
# installiert), ../host/setup-host.sh ist gelaufen, gh (GitHub-CLI) ist angemeldet.
#
# Was passiert:
#   1. Deploy-Key (nur lesend) fuer dieses Repo (INFRA_REPO, Jenkinsfiles) erzeugen und bei
#      GitHub eintragen
#   2. GitHub-Host-Schluessel fuer Jenkins hinterlegen (geprueft gegen den Fingerabdruck)
#   3. Credentials 'host-ssh-key', 'infra-repo-key' und 'app-repo-key' (Deploy-Key der App,
#      liegt seit setup-host.sh unter _secrets/frappe/.ssh/) sowie die Jobs anlegen —
#      ueber ein einmaliges init-Skript (jenkins-setup.groovy), danach Neustart von Jenkins
#
# Usage: ./setup-jenkins.sh [--run <job>]... [sshconfig]
#   --run <job>    startet den genannten Job einmal (mehrfach angebbar). Der erste Lauf
#                  eines Backup-Jobs aktiviert dessen Zeit-Trigger.
#   Jobs: erpai-backup-prod, erpai-backup-stage, erpai-backup-dev,
#         erpai-update-prod, erpai-update-stage, erpai-update-dev,
#         erpai-resetStage, erpai-resetDev, erpai-deploy-customer
#   Der erste Lauf von erpai-deploy-customer aktiviert dessen Polling auf dev/customer.
# Achtung: Das Skript startet Jenkins neu — laufende Jobs werden dabei abgebrochen.
# Wiederholbar. Konten werden nicht angelegt, Kennwoerter nicht veraendert.
################################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../host/erpai.host.conf"

RUN_JOBS=""
while [ "${1:-}" = "--run" ]; do
    [ -n "${2:-}" ] || { echo "--run braucht einen Jobnamen"; exit 1; }
    RUN_JOBS="${RUN_JOBS}${2}"$'\n'; shift 2
done
SSHCONFIG="${1:-$SSHCONFIG_DEFAULT}"
CONTAINER="${JENKINS_CONTAINER}"
REPO="${INFRA_REPO}"
REPO_KEY="${JENKINS_SECRETS_DIR}/infra-repo-key"
rsh() { ssh "${SSHCONFIG}" "$@"; }
# Kennung dieses Laufs: Das Ende wird im Jenkins-Log an genau dieser Kennung erkannt,
# nicht an der Meldung eines frueheren Laufs.
RUN_ID="lauf-$(date +%Y%m%d%H%M%S)-$$"

echo "── 1. Deploy-Key fuer ${REPO}"
rsh "set -e
if [ ! -f ${REPO_KEY} ]; then
    ssh-keygen -q -t ed25519 -N '' -C 'jenkins-erpai@${SSHCONFIG}' -f ${REPO_KEY}
    echo '   Neuer Schluessel erzeugt.'
else
    echo '   Schluessel vorhanden, wird nicht ueberschrieben.'
fi
chmod 600 ${REPO_KEY}"
PUB="$(rsh "cat ${REPO_KEY}.pub")"
if gh repo deploy-key list -R "$REPO" | grep -qF "$(awk '{print $2}' <<<"$PUB")"; then
    echo "✅ Deploy-Key ist bei GitHub bereits eingetragen."
else
    tmp="$(mktemp)"; printf '%s\n' "$PUB" > "$tmp"
    gh repo deploy-key add "$tmp" -R "$REPO" -t "Jenkins ERP AI auf ${SSHCONFIG} (nur lesend)"
    rm -f "$tmp"
    echo "✅ Deploy-Key bei GitHub eingetragen (nur lesend)."
fi

echo "── 2. GitHub-Host-Schluessel fuer Jenkins"
FP="$(rsh "ssh-keygen -lf ${FRAPPE_SECRETS_DIR}/.ssh/known_hosts | awk '/ED25519/{print \$2}'")"
[ "$FP" = "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU" ] \
    || { echo "❌ GitHub-Host-Schluessel auf dem Server weicht ab (${FP:-leer}) — erst ../host/setup-host.sh."; exit 1; }
rsh "docker exec ${CONTAINER} mkdir -p /var/jenkins_home/.ssh \
  && docker cp ${FRAPPE_SECRETS_DIR}/.ssh/known_hosts ${CONTAINER}:/var/jenkins_home/.ssh/known_hosts \
  && docker exec -u root ${CONTAINER} sh -c 'chown -R jenkins:jenkins /var/jenkins_home/.ssh && chmod 700 /var/jenkins_home/.ssh && chmod 644 /var/jenkins_home/.ssh/known_hosts'"
echo "✅ known_hosts hinterlegt."

echo "── 3. Credentials und Jobs"
rsh "docker exec ${CONTAINER} mkdir -p /var/jenkins_home/init.groovy.d /var/jenkins_home/erpai-setup"
scp -q "${SCRIPT_DIR}/jenkins-setup.groovy" "${SSHCONFIG}:/tmp/erpai-jenkins-setup.groovy"
rsh "set -e
docker cp /tmp/erpai-jenkins-setup.groovy ${CONTAINER}:/var/jenkins_home/init.groovy.d/erpai-setup.groovy && rm -f /tmp/erpai-jenkins-setup.groovy
docker cp ${JENKINS_SECRETS_DIR}/host-ssh-key ${CONTAINER}:/var/jenkins_home/erpai-setup/host-ssh-key
docker cp ${REPO_KEY} ${CONTAINER}:/var/jenkins_home/erpai-setup/infra-repo-key
docker cp ${FRAPPE_SECRETS_DIR}/.ssh/${DEPLOY_KEY_NAME} ${CONTAINER}:/var/jenkins_home/erpai-setup/app-repo-key
docker exec ${CONTAINER} sh -c 'echo ${RUN_ID} > /var/jenkins_home/erpai-setup/run-id'
docker exec -u root ${CONTAINER} sh -c 'chown -R jenkins:jenkins /var/jenkins_home/init.groovy.d /var/jenkins_home/erpai-setup && chmod 700 /var/jenkins_home/erpai-setup'
true"
# Zu startende Jobs uebergeben (leer = keiner), dann Neustart
printf '%s' "$RUN_JOBS" | rsh "docker exec -i ${CONTAINER} sh -c 'cat > /var/jenkins_home/erpai-setup/run-jobs && chown jenkins:jenkins /var/jenkins_home/erpai-setup/run-jobs' 2>/dev/null || docker exec -i -u root ${CONTAINER} sh -c 'cat > /var/jenkins_home/erpai-setup/run-jobs; chown jenkins:jenkins /var/jenkins_home/erpai-setup/run-jobs'"
rsh "docker restart ${CONTAINER} >/dev/null"
echo "   Jenkins startet neu..."
for _ in $(seq 1 60); do
    if rsh "docker logs --since 3m ${CONTAINER} 2>&1 | grep -qF '[erpai-setup] fertig (${RUN_ID}).'"; then break; fi
    sleep 3
done
rsh "docker logs --since 3m ${CONTAINER} 2>&1 | grep -F '[erpai-setup]' | tail -8 || true"
# Das init-Skript darf nicht bei jedem Start erneut laufen; die Schluessel-Kopien loescht es selbst.
rsh "docker exec ${CONTAINER} sh -c 'rm -f /var/jenkins_home/init.groovy.d/erpai-setup.groovy; rm -rf /var/jenkins_home/erpai-setup; ls /var/jenkins_home/jobs'"
if rsh "docker logs --since 3m ${CONTAINER} 2>&1 | grep -qF '[erpai-setup] fertig (${RUN_ID}).'"; then
    echo "✅ Jenkins eingerichtet: ${JENKINS_URL}"
else
    echo "❌ Das Einrichtungsskript ist nicht durchgelaufen — Log: ssh ${SSHCONFIG} docker logs --since 5m ${CONTAINER}"
    exit 1
fi
