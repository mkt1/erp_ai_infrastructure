# Jenkins fuer ERP AI — ueberlagert das Dockerfile der MIMS-Komponente io/jenkins/2.x.1
# (MIMS kopiert Dateien aus Scenarios/<namespace>/<name>/ ueber die der Komponente).
#
# Abweichung von der Vorlage: Die Vorlage installiert 'yq' aus den Debian-Paketen — das ist
# der Python-Wrapper um jq. scenario.deploy braucht fuer 'init' aber das yq von Mike Farah (v4)
# und rsync. Ohne beides uebertraegt ein Job zwar nichts, meldet aber trotzdem Erfolg
# (aufgefallen am 04.10.2026 in einem Update-Job).
FROM jenkins/jenkins:lts
USER root
RUN apt-get update && apt-get install -y docker.io docker-compose acl sudo openvpn rsync curl \
    && rm -rf /var/lib/apt/lists/*

# yq (mikefarah), feste Version
ARG YQ_VERSION=v4.44.3
RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}" -o /usr/local/bin/yq \
    && chmod 0755 /usr/local/bin/yq \
    && yq --version

RUN usermod -aG docker jenkins

# Passwordless sudo fuer jenkins, aber nur fuer die zwei Befehle, die withOpenVPN braucht
RUN echo "jenkins ALL=(root) NOPASSWD: /usr/sbin/openvpn, /bin/kill" \
        > /etc/sudoers.d/jenkins-openvpn \
    && chmod 0440 /etc/sudoers.d/jenkins-openvpn \
    && visudo -cf /etc/sudoers.d/jenkins-openvpn

USER jenkins
