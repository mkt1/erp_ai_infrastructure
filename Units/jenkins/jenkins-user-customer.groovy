// jenkins-user-customer.groovy — legt den Jenkins-Benutzer der Customer-Umgebung an und erzeugt sein API-Token.
//
// Laeuft einmalig als init-Skript (init.groovy.d), eingespielt von setup-jenkins-customer.sh.
// Der Benutzername kommt aus der Inbox-Datei "user" (CUSTOMER_JENKINS_USER in erpai.host.conf).
// Was passiert:
//   1. Benutzer anlegen (Kennwort aus der Inbox-Datei password; wird nicht geaendert, wenn der Benutzer existiert).
//   2. API-Token "ausrollen" erzeugen und den Klartext in die Outbox schreiben — nur dort, nur einmal.
// Die Autorisierung bleibt unveraendert. Wiederholbar: vorhandener Benutzer wird nicht angefasst,
// ein vorhandenes Token nicht neu erzeugt.

import jenkins.model.Jenkins
import hudson.security.HudsonPrivateSecurityRealm
import hudson.model.User
import jenkins.security.ApiTokenProperty

def j = Jenkins.get()
def home = j.rootDir.absolutePath
def inbox = new File(home, 'erpai-setup-user')
def outbox = new File(home, 'erpai-setup-user-out'); outbox.mkdirs()
def log = { msg -> println "[erpai-user] ${msg}" }
def runId = new File(inbox, 'run-id').exists() ? new File(inbox, 'run-id').text.trim() : 'ohne-kennung'

def USER = new File(inbox, 'user').exists() ? new File(inbox, 'user').text.trim() : 'customer'
def JOB  = 'erpai-deploy-customer'

def realm = j.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm)) {
    log "Sicherheitsbereich ist nicht die Jenkins-Benutzerdatenbank (${realm?.class?.simpleName}) — abgebrochen."
    return
}
if (j.getItem(JOB) == null) { log "Hinweis: Job ${JOB} fehlt noch — erst setup-jenkins.sh ausfuehren." }

// ── 1. Benutzer ──────────────────────────────────────────────────────────────
def pwFile = new File(inbox, 'password')
def user = User.getById(USER, false)
if (user == null) {
    if (!pwFile.exists()) { log "Kennwortdatei fehlt: ${pwFile} — Benutzer nicht angelegt."; return }
    user = realm.createAccount(USER, pwFile.text.trim())
    user.setFullName('Customer (ERP AI Dev)')
    user.save()
    log "Benutzer ${USER} angelegt."
} else {
    log "Benutzer ${USER} existiert, Kennwort unveraendert."
}

// ── 2. API-Token ─────────────────────────────────────────────────────────────
def tokenName = 'ausrollen'
def prop = user.getProperty(ApiTokenProperty)
if (prop == null) { prop = new ApiTokenProperty(); user.addProperty(prop) }
if (prop.getTokenList().any { it.name == tokenName }) {
    log "API-Token '${tokenName}' existiert schon — nicht neu erzeugt (Klartext ist nur beim Anlegen sichtbar)."
} else {
    def t = prop.tokenStore.generateNewToken(tokenName)
    user.save()
    def out = new File(outbox, 'api-token'); out.text = t.plainValue + "\n"
    log "API-Token '${tokenName}' erzeugt → ${out}"
}

inbox.deleteDir()
j.save()
log "fertig (${runId})."
