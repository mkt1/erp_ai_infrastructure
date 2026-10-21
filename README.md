# ERP AI Infrastructure — Betriebshandbuch

> **Stand 22.10.2026** · Erstellt von Matthias Kittner Consulting
> **Zweck:** Infrastruktur fuer eine ERPNext-Umgebung, die mit KI (Claude) erweitert wird: drei
> ERPNext-Instanzen (Produktiv, Stage, Dev), ein Jenkins, optional ein Traefik — ausgerollt mit MIMS.
> Die dazugehoerige Frappe-App ist [`erp_ai_app`](https://github.com/mkt1/erp_ai_app) (Submodul `erp_ai_app/`).
> Vorlage war der Betrieb bei einem Kundenprojekt; alles Kundenspezifische ist entfernt
> ([docs/HERKUNFT.md](docs/HERKUNFT.md)).
>
> **Keine Zugangsdaten in diesem Repo.** Kennwoerter und Schluessel liegen nur auf dem Server (§3).
>
> **Server:** `ki.netcup` (Entscheidung nach Servercheck, §4), Domains `*.ki.matthiaskittner.de`, Namensraum
> `de/matthiaskittner/ki` wie die anderen Szenarien dort. Umzug auf einen anderen Server: §5.

## Dokumentation

| Dokument | Inhalt |
|---|---|
| README.md (diese Datei) | Was laeuft, wie es zusammenhaengt, Aufsetzen, Alltag, Jenkins-Jobs |
| [docs/SETUP.md](docs/SETUP.md) | **Das aktuelle Setup konkret** (Server, Szenarien, Apps, Geheimnisse, Jobs) und der Neuaufbau mit `./bootstrap.sh` |
| [docs/01_Erfolgskriterien.md](docs/01_Erfolgskriterien.md) | Was dieses Repo leisten muss (Messlatte) |
| [docs/02_Konzept.md](docs/02_Konzept.md) | Entscheidungen: Namen, Branches, Umgebungen, Server |
| [docs/03_Umsetzungsplan.md](docs/03_Umsetzungsplan.md) | Abhakbarer Plan, Stand der Umsetzung |
| [docs/04_Servercheck.md](docs/04_Servercheck.md) | Messung kittner.netcup / ki.netcup vom 21.10.2026 und Empfehlung |
| [docs/05_Pruefung.md](docs/05_Pruefung.md) | Pruefung gegen die Erfolgskriterien und Retrospektive |
| [docs/HERKUNFT.md](docs/HERKUNFT.md) | Was woher uebernommen ist, was geaendert wurde |
| [Components/de/erpai/erpnext/16.x/DEPLOYMENT_FLOW.md](Components/de/erpai/erpnext/16.x/DEPLOYMENT_FLOW.md) | Was bei `init`, `update`, `down`, `up` im ERPNext-Stack genau passiert |
| `erp_ai_app/CLAUDE.md`, `erp_ai_app/docs/` | Die App: Arbeitsweise mit Claude, Customer- und Developer-Umgebung |

## 1. Was laeuft

| Dienst (Szenario) | Adresse | Branch der App | Zweck |
|---|---|---|---|
| **ERPNext Produktiv** (`erpai`) | https://erpai.ki.matthiaskittner.de | `main` | Produktivsystem |
| **ERPNext Stage** (`erpai-stage`) | https://erpai-stage.ki.matthiaskittner.de | `staging` | Vorstufe: hier prueft der Developer, bevor es produktiv geht |
| **ERPNext Dev** (`erpai-dev`) | https://erpai-dev.ki.matthiaskittner.de (Badge CUSTOMER) | `dev/customer` | Entwicklungsinstanz der **Customer-Umgebung** — hier baut der Kunde mit Claude |
| **Jenkins** (`erpai-jenkins`) | https://erpai-jenkins.ki.matthiaskittner.de/jenkins/ | — | naechtliches Backup, Updates, Reset, Deploy auf Dev |
| Traefik (`traefik`) | — | — | **optional**, nur auf einem eigenen Server; auf ki.netcup wird der vorhandene Traefik (`ki.matthiaskittner.de`) mitbenutzt |

Die Jenkins-Adresse braucht den Pfad `/jenkins/` — ohne ihn kommt 404.

## 2. Wie es zusammenhaengt

```
Internet ──80/443──▶ Traefik ──┬─▶ erpai.ki.matthiaskittner.de        ▶ ERPNext Produktiv  (Volumes erpai_*)
                               ├─▶ erpai-stage.ki.matthiaskittner.de  ▶ ERPNext Stage      (Volumes erpai-stage_*)
                               ├─▶ erpai-dev.ki.matthiaskittner.de    ▶ ERPNext Dev        (Volumes erpai-dev_*)
                               └─▶ erpai-jenkins.ki.matthiaskittner.de    ▶ Jenkins ──SSH──▶ Host (Backup, Reset, Deploy)

Claude (Customer-Umgebung) ──push dev/customer──▶ GitHub mkt1/erp_ai_app ──Polling / REST──▶ Jenkins erpai-deploy-customer ──▶ Dev
Claude (Developer-Umgebung) ──PR merge──▶ staging / main ──▶ Jenkins erpai-update-stage / -prod ──▶ Stage / Produktiv
```

- Alle Dienste laufen als Docker-Container und haengen im Docker-Netz `traefik`. Nach aussen offen sind nur 80 und 443.
- Ausgerollt wird mit **MIMS** (`./scenario.deploy`, Submodul `MIMS/`, Branch `mims2`) vom eigenen Rechner aus, per SSH.
  Ein **Szenario** ist eine Konfigurationsdatei unter `Scenarios/de/matthiaskittner/ki/`, eine **Komponente** die Bauanleitung
  dahinter (ERPNext: hier im Repo unter `Components/`; Traefik und Jenkins: aus MIMS).
- ERPNext ist Frappe/ERPNext **Version 16** plus die App **`erp_ai_app`** (privates Repo `mkt1/erp_ai_app`).
  Welche Instanz welchen Branch zieht, steht in `Scenarios/de/matthiaskittner/ki/<szenario>/apps.json`.
- **Alle drei Sites heissen intern gleich** (`SCENARIO_SITE_NAME`, heute `erpai.ki.matthiaskittner.de`). Das ist Absicht: Beim
  Zuruecksetzen wird der Bestand der Produktion kopiert, samt Site-Ordner. Unterschieden wird ueber die Adresse.
- **Entwicklermodus:** Produktiv aus, Stage und Dev an (`SCENARIO_ERPNEXT_DEVELOPERMODE`).

### Zwei Umgebungen fuer Claude

| | Customer-Umgebung | Developer-Umgebung |
|---|---|---|
| Variable | `ERPAI_DEV=customer` | `ERPAI_DEV=developer` |
| Branch | nur `dev/customer` | frei (`staging`, Feature-Branches, `main` per PR) |
| Instanz | Dev (`erpai-dev`) | Stage (`erpai-stage`), Produktiv nach Merge |
| Ausrollen | `/ausrollen` → `erpai-deploy-customer`, 1–2 Minuten | Merge nach `staging`/`main`, dann `erpai-update-stage` / `-prod` |
| Darf aendern | nur `erp_ai_app/customer/`, `fixtures/`, `docs/festlegungen/` (Pfadregel) | alles |
| Nach Produktiv | Pull Request an den Developer | mergt und rollt aus |

Die Regeln dazu stehen in `erp_ai_app/CLAUDE.md`; die Skripte in `erp_ai_app/scripts/` leiten alles aus `ERPAI_DEV` ab.

## 3. Rahmenbedingungen und Zugangsdaten

Alle Werte stehen in [Units/host/erpai.host.conf](Units/host/erpai.host.conf) und in den Szenarien.

| Was | Wert |
|---|---|
| SSH-Config-Name | `ki.netcup` (Vorlage: [ssh-config.example](ssh-config.example)) |
| Ablage auf dem Server | `/var/dev/MIMS-Scenarios` |
| Szenarien auf dem Server | `/var/dev/MIMS-Scenarios/de/matthiaskittner/ki/<name>/` |
| Backups | `/var/dev/MIMS-Scenarios/_backups` |
| Namen (DNS) | `erpai`, `erpai-stage`, `erpai-dev`, `erpai-jenkins` — jeweils `.ki.matthiaskittner.de` (Wildcard zeigt auf den Server) |
| Apps | `erp_ai_app` (`main` / `staging` / `dev/customer`), `sut_app_tax` (`main`, privat, eigener Deploy-Key, Alias `github_sut_app_tax`), `pdf_a_3` (`main`, oeffentlich) — je Instanz in `apps.json` |

**Kennwoerter und Schluessel — nur auf dem Server**, unter `/var/dev/MIMS-Scenarios/_secrets/`. Erzeugt vom
Host-Skript, zufaellig, bei erneutem Lauf nie ueberschrieben:

| Zweck | Datei |
|---|---|
| ERPNext, Benutzer `Administrator` (alle drei Instanzen) | `frappe/admin_password` |
| Deploy-Keys fuer die privaten Apps (bei GitHub nur lesend eingetragen) | `frappe/.ssh/id_ed25519_erp_ai_app`, `frappe/.ssh/id_ed25519_sut_app_tax` |
| Schluessel Jenkins → Host (Credential `host-ssh-key`) | `jenkins/host-ssh-key` |
| Deploy-Key fuer dieses Repo (Credential `infra-repo-key`) | `jenkins/infra-repo-key` |
| Jenkins-Benutzer der Customer-Umgebung (Kennwort, API-Token) | `jenkins/customer_password`, `jenkins/customer_api_token` |
| Traefik-Dashboard (nur mit eigenem Traefik) | `traefik/dashboard_password` |
| Jenkins, erstes Administrator-Kennwort | im Container: `docker exec erpai-jenkins_jenkins_container cat /var/jenkins_home/secrets/initialAdminPassword` |

Das Administrator-Kennwort wird **nur beim Anlegen** einer Site gesetzt. Wird es spaeter in ERPNext
geaendert, stimmt die Datei nicht mehr — dann dort nachtragen.

## 4. Server: was realistisch ist (Messung 21.10.2026)

Details in [docs/04_Servercheck.md](docs/04_Servercheck.md). Kurzfassung:

| | kittner.netcup | ki.netcup |
|---|---|---|
| CPU / RAM | 4 Kerne, 7,9 GB — **2,8 GB frei** | 12 Kerne, 32 GB — **19 GB frei** |
| Platte | 251 GB, **39 GB frei** (112 GB Backups) | 1 TB, **604 GB frei** |
| Laeuft schon | 23 Container, Traefik, Jenkins | 57 Container, Traefik, ein Szenario `erp` |
| Platz fuer ERP AI | **keine ERPNext-Instanz** ohne Risiko | **alle vier Szenarien** (erpai, -stage, -dev, -jenkins) |

Drei ERPNext-v16-Instanzen brauchen im Betrieb zusammen etwa 5 GB RAM, der Image-Bau kurzzeitig 2–3 GB mehr,
Jenkins ~0,7 GB. **Empfehlung: ki.netcup**, vorhandenen Traefik mitbenutzen, Szenario `traefik` nicht ausrollen.
Deshalb sind die Szenarien so benannt, dass sie mit dem Bestand dort nicht kollidieren (`erpai*` statt `erp`,
`erpai-jenkins` statt `jenkins`), und `traefik` ist optional (`SCENARIOS_OPTIONAL` in `erpai.host.conf`).

## 5. Umzug auf einen anderen Server oder eine andere Domain

Server-Alias (Beispiel: `ki.netcup` → `erpai.server`) und Domain (`ki.matthiaskittner.de` → `meine-domain.de`):

```bash
grep -rl --exclude-dir=.git --exclude-dir=MIMS -E 'ki\.netcup|ki\.matthiaskittner\.de' . | xargs sed -i '' -e 's/ki\.netcup/erpai.server/g' -e 's/ki\.matthiaskittner\.de/meine-domain.de/g'
```

Danach pruefen: `Scenarios/de/matthiaskittner/ki/*.scenario.env` (`SCENARIO_SERVER_SSHCONFIG`, `SCENARIO_SITE_NAME`, `SCENARIO_TRAEFIK_URL`),
`Units/host/erpai.host.conf` (`SSHCONFIG_DEFAULT`, `DOMAINS`, `JENKINS_URL`), `Jenkins/Jenkinsfile.*`
(`TARGET_HOST`, `TARGET_HOSTNAME`, `*_URL`, `SITE`), `ssh-config.example` — und in der App
`erp_ai_app/scripts/erpai-env.sh` (`ERPAI_PROD_URL`, `ERPAI_STAGE_URL`, `ERPAI_DEV_URL`, `ERPAI_JENKINS_URL`) sowie
die Badge-Regeln in `erp_ai_app/erp_ai_app/site_branding/setup.py`.
Der Namensraum (`de/matthiaskittner/ki`) folgt dem Zielserver und steht in `erpai.host.conf`, den Szenarien und den Jenkinsfiles (`TARGET_BASE_PATH`).
**Der Site-Name ist nach dem ersten `init,up` fest** (Site-Ordner, Datenbank) — vorher festlegen.

## 6. Einen Server von Null aufsetzen

Voraussetzungen auf dem eigenen Rechner: dieses Repo mit Submodulen (`git submodule update --init`), der Eintrag
aus [ssh-config.example](ssh-config.example) in `~/.ssh/config`, der eigene SSH-Schluessel auf dem Server, `gh` angemeldet.

**Schritt 1 — Host vorbereiten** (wiederholbar):

```bash
cd Units/host && ./setup-host.sh
```

Prueft und richtet ein: Betriebssystem, Docker, Pakete · Groesse des Servers (eingebaut und frei) · Verzeichnisse ·
Deploy-Key fuer die App samt geprueftem GitHub-Host-Schluessel (traegt ihn per `gh` bei GitHub ein) ·
Administrator-Kennwort · Schluessel fuer Jenkins · DNS · freie Szenario-Namen · ob schon ein Traefik laeuft.
Am Ende steht eine Liste, was von Hand bleibt.

**Schritt 2 — Dienste starten**, in der Repo-Wurzel, in dieser Reihenfolge (nur auf einem eigenen Server zuerst `traefik`; auf ki.netcup laeuft er schon):

```bash
./scenario.deploy de/matthiaskittner/ki/erpai init,up -v
```
```bash
./scenario.deploy de/matthiaskittner/ki/erpai-stage init,up -v
```
```bash
./scenario.deploy de/matthiaskittner/ki/erpai-dev init,up -v
```
```bash
./scenario.deploy de/matthiaskittner/ki/erpai-jenkins init,up -v
```

Der erste Start einer ERPNext-Instanz baut das Image und legt die Site an — das dauert einige Minuten.
Die Instanzen nacheinander starten, nicht parallel (Image-Bau braucht RAM).

**Schritt 3 — Jenkins einrichten**

1. Einmalig im Browser: Einrichtungsassistenten mit dem ersten Administrator-Kennwort (§3) durchlaufen
   (vorgeschlagene Plugins installieren, eigenes Konto anlegen).
2. Credentials und Jobs anlegen — per Skript, wiederholbar:

```bash
cd Units/jenkins && ./setup-jenkins.sh
```

| Art | Name | Inhalt |
|---|---|---|
| Credential | `host-ssh-key` | Schluessel, mit dem Jenkins sich als `root` am Host anmeldet |
| Credential | `infra-repo-key` | Deploy-Key fuer `mkt1/erp_ai_infrastructure` (Jenkinsfiles) |
| Credential | `app-repo-key` | Deploy-Key fuer `mkt1/erp_ai_app` (fuer den Deploy-Job) |
| Job | `erpai-backup-prod` / `-stage` / `-dev` | Sicherung — taeglich gegen 2 / 3 / 4 Uhr |
| Job | `erpai-update-prod` / `-stage` / `-dev` | Stand aus dem App-Repo auf die Instanz spielen — nur von Hand |
| Job | `erpai-resetStage` / `erpai-resetDev` | Stage bzw. Dev auf den Stand der Produktion zuruecksetzen — nur von Hand; **ueberschreibt die Instanz** |
| Job | `erpai-deploy-customer` | Leichtes Ausrollen von `dev/customer` auf Dev — bei jedem Push (Polling) und per `/ausrollen` |

   Mit `./setup-jenkins.sh --run <jobname>` wird ein Job gleich einmal gestartet. Der Zeit-Trigger eines
   Backup-Jobs und das Polling des Deploy-Jobs greifen erst nach dem ersten Lauf. **Achtung:** Das Skript startet
   Jenkins neu — laufende Jobs werden dabei abgebrochen. Die Jobs lesen ihr Jenkinsfile aus `Jenkins/` im Branch `main`
   dieses Repos — **was nicht gepusht ist, kennt Jenkins nicht.**
3. Benutzer der Customer-Umgebung (Jenkins-Konto `customer` mit API-Token fuer `/ausrollen`):

```bash
cd Units/jenkins && ./setup-jenkins-customer.sh
```

4. Optional: Mailversand einrichten (Jenkins verwalten → System → E-Mail) und in den Jenkinsfiles
   `NOTIFY_RECIPIENTS` setzen. Solange das Feld leer ist, verschicken die Jobs keine Mail.

**Schritt 4 — Customer-Umgebung ausstatten:** ERPNext-Benutzer fuer den Customer in Produktiv und Dev anlegen,
API-Schluessel erzeugen; die Werte zusammen mit dem Jenkins-Token in die Cloud-Umgebung eintragen
(`erp_ai_app/docs/einrichtung-customer-cloud.md`).

## 7. Alltag

Alle Befehle in der Repo-Wurzel, `<name>` ist `erpai`, `erpai-stage`, `erpai-dev` oder `erpai-jenkins`.

| Aufgabe | Befehl |
|---|---|
| Welche Szenarien gibt es? | `./scenario.deploy "de/matthiaskittner/ki/*" inspect` |
| Laeuft der Dienst? | `./scenario.deploy de/matthiaskittner/ki/<name> test -v` |
| Neu starten | `./scenario.deploy de/matthiaskittner/ki/<name> stop,start` |
| Nach Aenderung am Szenario oder an der Komponente | `./scenario.deploy de/matthiaskittner/ki/<name> init,down,up -v` |
| Neue App-Version einspielen | Jenkins-Job `erpai-update-stage` bzw. `-prod` — oder von Hand: `./scenario.deploy de/matthiaskittner/ki/<name> init,update,down,up -v` |
| Logs einsammeln | `./scenario.deploy de/matthiaskittner/ki/<name> logs` |
| Was laeuft auf dem Server? | `ssh ki.netcup docker ps` |
| Bench-Befehl in ERPNext | `ssh ki.netcup docker exec erpai_erpnext_backend_container bench --site erpai.ki.matthiaskittner.de <befehl>` |

**Regel:** Nach jeder Aenderung an Dateien einer Komponente oder eines Szenarios zuerst `init` — erst das
uebertraegt sie auf den Server. Ein normales `down,up` ohne `update` zieht **keinen** neuen Code.

### Die Jenkins-Jobs

| Job | Jenkinsfile | Was er tut | Dauer, Wirkung |
|---|---|---|---|
| `erpai-backup-prod` · `-stage` · `-dev` | `Jenkinsfile.backup` | Sichert alle Volumes der Instanz plus `bench backup`, raeumt alte Sicherungen auf (7 Tage alle, danach 51 Wochen je eine), raeumt Docker-Images auf. Welche Instanz, entscheidet der Jobname. | wenige Minuten, Instanz bleibt erreichbar |
| `erpai-update-prod` · `-stage` · `-dev` | `Jenkinsfile.update` | 1. volle Sicherung · 2. `init` · 3. `update,down,up` mit Upgrade (Datenbank-Backup, Apps laut `apps.json`, Abhaengigkeiten, `bench build`, `migrate`) · 4. Pruefung | 5–10 Minuten, **Instanz nicht erreichbar** |
| `erpai-resetStage` · `erpai-resetDev` | `Jenkinsfile.resetStage` | Sichert Produktiv, spielt den Stand ins Ziel, hebt dessen Apps auf ihren Branch (`staging` bzw. `dev/customer`), legt den Mailversand still. | 10–15 Minuten, **alles nur im Ziel Vorhandene ist danach weg** |
| `erpai-deploy-customer` | `Jenkinsfile.deploy` | Alltagsweg der Customer-Umgebung: holt `dev/customer` in die Dev-Instanz (fix-git-refs), `pip install -e` und `bench build` nur bei Bedarf, migrate, Cache, App-Container neu starten, Badge `CUSTOMER · <commit> · <Datum>`. | 1–2 Minuten |

**Der Weg einer neuen App-Version:** Customer baut auf `dev/customer` (`/ausrollen` → Dev) → Pull Request an den
Developer (`/nach-main`) → Developer mergt nach `staging`, `erpai-update-stage`, prueft → mergt nach `main` (Release
entsteht automatisch, Skill `/release` in der App) → `erpai-update-prod`.

## 8. Sichern und wiederherstellen

- **Automatisch:** die drei Backup-Jobs, naechtlich, nach `/var/dev/MIMS-Scenarios/_backups/<szenario>_<zeitstempel>_*`.
- **Von Hand:** `./scenario.deploy de/matthiaskittner/ki/<name> backup -v`.
- **Wiederherstellen** (Instanz steht danach auf dem Backup-Stand): `./scenario.deploy de/matthiaskittner/ki/<name> down,restore,up -v`
  — welcher Zeitstempel, steht in `SCENARIO_DATA_BACKUPTIMESTAMP` (`latest` = der neueste).
- **Stage oder Dev auf Produktivstand:** Jobs `erpai-resetStage` / `erpai-resetDev` (§7).

## 9. Aufbau dieses Repos

```
erp_ai_infrastructure/
├── README.md                          dieses Handbuch
├── bootstrap.sh                       Neuaufbau in Reihenfolge (docs/SETUP.md §6)
├── docs/                              01–05 (Erfolgskriterien, Konzept, Plan, Servercheck, Pruefung), HERKUNFT
├── scenario.deploy                    Stub → MIMS/scenario.deploy (Submodul)
├── MIMS/                              Submodul Cerulean-Circle-GmbH/MIMS, Branch mims2
├── erp_ai_app/                        Submodul mkt1/erp_ai_app (die App; Stand = main)
├── Scenarios/de/matthiaskittner/ki/                erpai, erpai-stage, erpai-dev, erpai-jenkins, traefik (optional)
│   ├── *.scenario.env                 je Dienst: Server, Pfade, Adresse, Volumes
│   ├── erpai*/apps.json               welche App in welchem Branch installiert wird
│   └── erpai-jenkins/Dockerfile       Jenkins-Image mit rsync und yq (ueberlagert die MIMS-Komponente)
├── Components/de/erpai/erpnext/16.x/  ERPNext-Komponente (Kopie, siehe HERKUNFT)
├── Units/host/                        setup-host.sh, setup-host-erpai.sh, erpai.host.conf, install-docker.sh
├── Units/jenkins/                     setup-jenkins.sh, jenkins-setup.groovy, setup-jenkins-customer.sh, jenkins-user-customer.groovy
├── Units/backup/                      Hilfsskripte fuer Backup, Aufraeumen, Reset, Badge
├── Jenkins/                           Jenkinsfile.backup, .update, .resetStage, .deploy
└── ssh-config.example                 Eintrag fuer ~/.ssh/config
```
