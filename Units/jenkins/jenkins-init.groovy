// jenkins-init.groovy — schliesst die Ersteinrichtung von Jenkins ab, ohne den Assistenten im Browser.
//
// Laeuft einmalig als init-Skript (init.groovy.d), eingespielt von setup-jenkins-init.sh. Wiederholbar:
// ein vorhandener Benutzer bleibt (Kennwort unveraendert), ein vorhandenes Token wird nicht neu erzeugt.
// Inbox (vom Skript befuellt): password, user, url, run-id. Outbox: api-token (Klartext, nur einmal).

import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration
import jenkins.install.InstallState
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.csrf.DefaultCrumbIssuer
import hudson.model.User
import jenkins.security.ApiTokenProperty

def j = Jenkins.get()
def home = j.rootDir.absolutePath
def inbox = new File(home, 'erpai-init')
def outbox = new File(home, 'erpai-init-out'); outbox.mkdirs()
def log = { msg -> println "[erpai-init] ${msg}" }
def read = { String f -> new File(inbox, f).exists() ? new File(inbox, f).text.trim() : '' }
def runId = read('run-id') ?: 'ohne-kennung'
def USER = read('user') ?: 'developer'
def URL  = read('url')
def pw   = read('password')

// ── 1. Sicherheitsbereich: Jenkins-Benutzerdatenbank, keine Selbstregistrierung ──
def realm = j.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm)) {
    realm = new HudsonPrivateSecurityRealm(false)
    j.setSecurityRealm(realm)
    log "Sicherheitsbereich: Jenkins-Benutzerdatenbank."
}

// ── 2. Administrator ──
def user = User.getById(USER, false)
if (user == null) {
    if (!pw) { log "Kennwort fehlt — Benutzer nicht angelegt."; return }
    user = realm.createAccount(USER, pw)
    user.setFullName('Developer (ERP AI)')
    user.save()
    log "Benutzer ${USER} angelegt."
} else {
    log "Benutzer ${USER} existiert, Kennwort unveraendert."
}

// ── 3. Rechte: jeder Angemeldete darf alles, Anonyme sehen nichts ──
if (!(j.getAuthorizationStrategy() instanceof FullControlOnceLoggedInAuthorizationStrategy)) {
    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    j.setAuthorizationStrategy(strategy)
    log "Autorisierung: angemeldet = Vollzugriff, anonym = nichts."
}

// ── 4. CSRF-Schutz, Jenkins-URL, Assistent abschliessen ──
if (j.getCrumbIssuer() == null) { j.setCrumbIssuer(new DefaultCrumbIssuer(true)); log "CSRF-Schutz an." }
if (URL) {
    def loc = JenkinsLocationConfiguration.get()
    if (loc.getUrl() != URL) { loc.setUrl(URL); loc.save(); log "Jenkins-URL: ${URL}" }
}
if (j.getInstallState() != InstallState.RUNNING) {
    j.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
    log "Einrichtungsassistent abgeschlossen."
}

// ── 5. API-Token fuer die Developer-Umgebung ──
def tokenName = 'ausrollen'
def prop = user.getProperty(ApiTokenProperty)
if (prop == null) { prop = new ApiTokenProperty(); user.addProperty(prop) }
if (prop.getTokenList().any { it.name == tokenName }) {
    log "API-Token '${tokenName}' existiert schon — nicht neu erzeugt."
} else {
    def t = prop.tokenStore.generateNewToken(tokenName)
    user.save()
    new File(outbox, 'api-token').text = t.plainValue + "\n"
    log "API-Token '${tokenName}' erzeugt."
}

inbox.deleteDir()
j.save()
log "fertig (${runId})."
