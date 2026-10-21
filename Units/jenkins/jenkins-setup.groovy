// jenkins-setup.groovy — legt Credentials und Jobs fuer ERP AI an.
// Wird von setup-jenkins.sh einmalig als init-Skript in den Jenkins-Container gelegt,
// laeuft beim Neustart mit vollen Rechten und wird danach wieder entfernt.
// Wiederholbar: vorhandene Credentials und Jobs werden aktualisiert, nicht verdoppelt.
// Konten legt das Skript NICHT an.

import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.GitSCM
import hudson.plugins.git.BranchSpec
import hudson.plugins.git.extensions.impl.CloneOption

def j = Jenkins.get()
def home = j.rootDir.absolutePath
def inbox = new File(home, 'erpai-setup')      // von setup-jenkins.sh befuellt, wird am Ende geloescht
def log = { msg -> println "[erpai-setup] ${msg}" }
// Kennung dieses Laufs — damit setup-jenkins.sh das Ende genau dieses Laufs im Log erkennt
def runId = new File(inbox, 'run-id').exists() ? new File(inbox, 'run-id').text.trim() : 'ohne-kennung'

def REPO_URL = 'git@github.com:mkt1/erp_ai_infrastructure.git'
def BRANCH   = '*/main'

// ── Credentials ──────────────────────────────────────────────────────────────
def store = SystemCredentialsProvider.getInstance().getStore()
def upsertKey = { String id, String user, String file, String desc ->
    def f = new File(inbox, file)
    if (!f.exists()) { log "Schluesseldatei fehlt: ${file} — Credential '${id}' unveraendert"; return }
    def cred = new BasicSSHUserPrivateKey(CredentialsScope.GLOBAL, id, user,
        new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(f.text), '', desc)
    def existing = CredentialsProvider.lookupCredentials(BasicSSHUserPrivateKey, j, null, null).find { it.id == id }
    if (existing) { store.updateCredentials(Domain.global(), existing, cred); log "Credential aktualisiert: ${id}" }
    else          { store.addCredentials(Domain.global(), cred);              log "Credential angelegt: ${id}" }
}
upsertKey('host-ssh-key',   'root', 'host-ssh-key',   'Jenkins → Zielserver (root)')
upsertKey('infra-repo-key', 'git',  'infra-repo-key', 'Deploy-Key mkt1/erp_ai_infrastructure (nur lesend)')
upsertKey('app-repo-key',   'git',  'app-repo-key',   'Deploy-Key mkt1/erp_ai_app (nur lesend) — fuer erpai-deploy-customer')

// ── Jobs ─────────────────────────────────────────────────────────────────────
// Dieses Repo ist klein und eigenstaendig: voller, flacher Checkout (kein Sparse-Checkout noetig).
def upsertJob = { String name, String jenkinsfile, String desc ->
    def scm = new GitSCM(
        GitSCM.createRepoList(REPO_URL, 'infra-repo-key'),
        [new BranchSpec(BRANCH)], null, null,
        [new CloneOption(true, true, null, 10)])
    def job = j.getItem(name)
    if (job == null) { job = j.createProject(WorkflowJob, name); log "Job angelegt: ${name}" }
    else             { log "Job aktualisiert: ${name}" }
    def defn = new CpsScmFlowDefinition(scm, "Jenkins/${jenkinsfile}")
    defn.setLightweight(false)
    job.setDefinition(defn)
    job.setDescription(desc)
    job.save()
}
upsertJob('erpai-backup-prod',     'Jenkinsfile.backup',
          'Naechtliches Backup der PRODUKTIV-Instanz (Szenario erpai) samt Aufraeumen alter Sicherungen.')
upsertJob('erpai-backup-stage',    'Jenkinsfile.backup',
          'Naechtliches Backup der STAGE-Instanz (Szenario erpai-stage) samt Aufraeumen alter Sicherungen.')
upsertJob('erpai-backup-dev',      'Jenkinsfile.backup',
          'Naechtliches Backup der DEV-Instanz (Szenario erpai-dev) samt Aufraeumen alter Sicherungen.')
upsertJob('erpai-update-prod',     'Jenkinsfile.update',
          'Spielt den Stand aus dem App-Repo (main) auf die PRODUKTIV-Instanz (erpai): Sicherung, init, update, Neustart mit Upgrade. Einige Minuten nicht erreichbar. Nur von Hand.')
upsertJob('erpai-update-stage',    'Jenkinsfile.update',
          'Spielt den Stand aus dem App-Repo (staging) auf die STAGE-Instanz (erpai-stage): Sicherung, init, update, Neustart mit Upgrade. Nur von Hand.')
upsertJob('erpai-update-dev',      'Jenkinsfile.update',
          'Volles Upgrade der DEV-Instanz (erpai-dev) auf den Branch dev/customer: Sicherung, init, update, Neustart. Fuer den Alltag erpai-deploy-customer nehmen.')
upsertJob('erpai-resetStage',      'Jenkinsfile.resetStage',
          'Setzt die STAGE (erpai-stage) auf den Stand der Produktion und die App wieder auf staging. ACHTUNG: ueberschreibt die Stage. Nur von Hand starten.')
upsertJob('erpai-resetDev',        'Jenkinsfile.resetStage',
          'Setzt die DEV-Instanz (erpai-dev) auf den Stand der Produktion und die App wieder auf dev/customer. ACHTUNG: ueberschreibt die Daten der Customer-Umgebung dort. Nur von Hand starten.')
upsertJob('erpai-deploy-customer', 'Jenkinsfile.deploy',
          'Leichtes Ausrollen von dev/customer auf DEV (erpai-dev): fix-git-refs, migrate, Neustart, 1-2 Minuten. Laeuft bei jedem Push (Polling) und auf Anstoss des Skills /ausrollen der Customer-Umgebung.')

// Jobs einmal starten (Datei run-jobs, ein Name je Zeile). Der Zeit-Trigger aus dem
// Jenkinsfile (cron) wird erst nach dem ersten Lauf eines Jobs aktiv.
def runFile = new File(inbox, 'run-jobs')
if (runFile.exists()) {
    runFile.readLines().collect { it.trim() }.findAll { it }.each { name ->
        def job = j.getItem(name)
        if (job == null) { log "Job zum Starten nicht gefunden: ${name}" }
        else { job.scheduleBuild2(0); log "Lauf eingeplant: ${name}" }
    }
}

inbox.deleteDir()
j.save()
log "fertig (${runId})."
