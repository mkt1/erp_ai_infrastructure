# SETUP — das aktuelle Setup und wie man es neu aufbaut

> Stand 22.10.2026. Diese Datei beschreibt **konkret**, was wo laeuft, und ist die Vorlage fuer `./bootstrap.sh`.
> Hintergruende und Alltag: [README.md](../README.md). Entscheidungen: [02_Konzept.md](02_Konzept.md).

## 1. Der Server

| | Wert |
|---|---|
| Server | `ki.netcup` (SSH-Alias, `~/.ssh/config`; Vorlage [ssh-config.example](../ssh-config.example)), oeffentlich `ki.matthiaskittner.de` = 152.53.253.108 |
| Betriebssystem | Debian 12, Docker 28.4, 12 Kerne, 32 GB RAM, 1 TB |
| Ablage | `/var/dev/MIMS-Scenarios` — Szenarien unter `de/matthiaskittner/ki/<name>/`, Backups `_backups/`, Geheimnisse `_secrets/` |
| Reverse Proxy | der **vorhandene** Traefik 3.4 des Servers (Szenario `de/matthiaskittner/ki/traefik`, Netz `traefik`, Resolver `letsencrypt`, Entrypoint `websecure`). Das Szenario `traefik` dieses Repos wird hier **nicht** ausgerollt |
| DNS | Wildcard `*.ki.matthiaskittner.de` → Server |
| Geteilt mit | ~57 weiteren Containern (Authentik, n8n, Open WebUI, ein ERPNext `erp`, Monitoring …) — Namen `erpai*` sind deshalb eindeutig |

## 2. Die Szenarien (Namensraum `de/matthiaskittner/ki`)

| Szenario | Adresse | Komponente | Apps (Branch) | Entwicklermodus | Port intern |
|---|---|---|---|---|---|
| `erpai` | https://erpai.ki.matthiaskittner.de | `de/erpai/erpnext/16.x` (Frappe/ERPNext `version-16`) | erp_ai_app `main`, sut_app_tax `main`, pdf_a_3 `main` | aus | 8180 |
| `erpai-stage` | https://erpai-stage.ki.matthiaskittner.de | dito | erp_ai_app `staging`, sut_app_tax `main`, pdf_a_3 `main` | an | 8181 |
| `erpai-dev` | https://erpai-dev.ki.matthiaskittner.de | dito | erp_ai_app `dev/customer`, sut_app_tax `main`, pdf_a_3 `main` | an | 8182 |
| `erpai-jenkins` | https://erpai-jenkins.ki.matthiaskittner.de/jenkins/ | MIMS `io/jenkins/2.x.1` + eigenes Dockerfile (rsync, yq) | — | — | Host-Port 8190 |

- Site-Name in allen drei ERPNext-Instanzen: **`erpai.ki.matthiaskittner.de`** (Reset kopiert den Site-Ordner der Produktion).
- Volumes: `erpai_*`, `erpai-stage_*`, `erpai-dev_*`, `erpai-jenkins_data-volume` (extern, bleiben bei `down`).
- Container: `<szenario>_erpnext_{backend,frontend,db,redis-cache,redis-queue,queue-short,queue-long,scheduler,websocket,create-site}_container`, `erpai-jenkins_jenkins_container`.

## 3. Geheimnisse auf dem Server (`/var/dev/MIMS-Scenarios/_secrets/`, nur root)

| Datei | Zweck | Erzeugt von |
|---|---|---|
| `frappe/admin_password` | ERPNext `Administrator`, alle drei Instanzen (beim Anlegen der Site gesetzt) | `setup-host.sh` 2.5 |
| `frappe/.ssh/id_ed25519_erp_ai_app` | Deploy-Key `mkt1/erp_ai_app` (bei GitHub, nur lesend) | 2.4 |
| `frappe/.ssh/id_ed25519_sut_app_tax` + Alias `github_sut_app_tax` in `frappe/.ssh/config` | Deploy-Key `schmidtundtoechter/sut_app_tax` (GitHub laesst einen Key nur an einem Repo zu) | 2.4b |
| `frappe/.ssh/known_hosts` | GitHub-Host-Schluessel, gegen den veroeffentlichten Fingerabdruck geprueft | 2.4 |
| `jenkins/host-ssh-key` | Jenkins → Host als `root` (Credential `host-ssh-key`); oeffentlicher Teil in `~root/.ssh/authorized_keys` | 2.7 |
| `jenkins/infra-repo-key` | Deploy-Key `mkt1/erp_ai_infrastructure` (Credential `infra-repo-key`) | `setup-jenkins.sh` |
| `jenkins/developer_password`, `jenkins/developer_api_token` | Jenkins-Administrator `developer` (Developer-Umgebung, `ERPAI_JENKINS_USER`) | `setup-jenkins-init.sh` |
| `jenkins/customer_password`, `jenkins/customer_api_token` | Jenkins-Benutzer `customer` fuer `/ausrollen` | `setup-jenkins-customer.sh` |

Der Ordner `_secrets/` wird von anderen Szenarien mitbenutzt; seine Rechte werden nicht veraendert, nur die
Unterordner `frappe/`, `jenkins/`, `traefik/` gehoeren diesem Setup.

## 4. Jenkins (`erpai-jenkins`)

Eingerichtet ohne Browser durch `Units/jenkins/setup-jenkins-init.sh` (Plugins per `jenkins-plugin-cli`, Assistent
abgeschlossen, Benutzerdatenbank, Benutzer **`developer`** als Administrator mit API-Token `ausrollen`, CSRF an,
Anonyme sehen nichts, Jenkins-URL gesetzt). Credentials `host-ssh-key`, `infra-repo-key`, `app-repo-key`; neun Jobs,
alle lesen `Jenkins/Jenkinsfile.*` aus `mkt1/erp_ai_infrastructure`, Branch `main`:

| Job | Trigger | Ziel |
|---|---|---|
| `erpai-backup-prod` / `-stage` / `-dev` | taeglich 2 / 3 / 4 Uhr | Volumes + `bench backup`, Aufraeumen |
| `erpai-update-prod` / `-stage` / `-dev` | von Hand | Sicherung, `init`, `update,down,up`, Pruefung |
| `erpai-resetStage` / `erpai-resetDev` | von Hand | Ziel auf Produktivstand, Apps auf `staging` bzw. `dev/customer`, Mails stumm |
| `erpai-deploy-customer` | Polling alle 2 min auf `dev/customer`, REST per `/ausrollen` | leichtes Ausrollen auf `erpai-dev`, Badge `CUSTOMER · <commit> · <Datum>` |

## 5. Die App-Repos

| Repo | Sichtbarkeit | Branches | Zugriff vom Server |
|---|---|---|---|
| `mkt1/erp_ai_app` | privat | `main` (Produktiv, Release-Action), `staging` (Stage), `dev/customer` (Dev) | Deploy-Key `id_ed25519_erp_ai_app` |
| `schmidtundtoechter/sut_app_tax` | privat | `main` | Deploy-Key `id_ed25519_sut_app_tax`, Alias `github_sut_app_tax` |
| `schmidtundtoechter/pdf_a_3` | oeffentlich | `main` | https |
| `mkt1/erp_ai_infrastructure` | oeffentlich | `main` | Jenkins: `infra-repo-key` |

## 6. Von Null aufbauen — `./bootstrap.sh`

Voraussetzungen auf dem eigenen Rechner: Repo geklont, `~/.ssh/config` mit dem Alias `ki.netcup` (Schluessel auf
dem Server bei `root`), `gh` angemeldet (Konto mit Admin auf den privaten App-Repos), `dig`.

```bash
./bootstrap.sh
```

macht in dieser Reihenfolge, jeder Schritt wiederholbar:

1. `git submodule update --init` — MIMS (`mims2`) und `erp_ai_app`.
2. `Units/host/setup-host.sh` — Docker und Pakete, Verzeichnisse, Deploy-Keys (traegt sie per `gh` bei GitHub ein),
   Administrator-Kennwort, Jenkins-Schluessel, DNS-Pruefung, freie Namen, Traefik-Erkennung.
3. `./scenario.deploy de/matthiaskittner/ki/<s> init,up -v` fuer `erpai`, `erpai-stage`, `erpai-dev`, `erpai-jenkins` —
   nacheinander; ein laufendes Szenario wird uebersprungen. Der erste Start einer ERPNext-Instanz baut das Image
   und legt die Site an (einige Minuten).
4. Jenkins, ohne Browser (Jenkins startet dabei dreimal neu):

```bash
./bootstrap.sh --skip-host --no-scenarios --jenkins
```

   `setup-jenkins-init.sh` (Plugins, Assistent, Benutzer `developer`), `setup-jenkins.sh` (Credentials, neun Jobs),
   `setup-jenkins-customer.sh` (Benutzer `customer`). Kennwoerter: `ssh ki.netcup cat /var/dev/MIMS-Scenarios/_secrets/jenkins/developer_password`.

5. Customer-Umgebung ausstatten (nicht automatisiert): ERPNext-Benutzer des Customers in Produktiv und Dev,
   API-Schluessel, Werte in die Cloud-Umgebung „Customer" (`erp_ai_app/docs/einrichtung-customer-cloud.md`);
   einmal `erpai-resetDev`, damit Dev den Produktivstand traegt; ersten Lauf von `erpai-deploy-customer`
   (`setup-jenkins.sh --run erpai-deploy-customer`), damit das Polling greift.

## 7. Pruefen, ob alles steht

```bash
for s in erpai erpai-stage erpai-dev erpai-jenkins; do ./scenario.deploy de/matthiaskittner/ki/$s test -v; done
```
```bash
for h in erpai erpai-stage erpai-dev; do curl -s -o /dev/null -w "$h %{http_code}\n" https://$h.ki.matthiaskittner.de/api/method/ping; done
```
```bash
ssh ki.netcup docker exec erpai_erpnext_backend_container bench --site erpai.ki.matthiaskittner.de list-apps
```

Erwartet: `test` gruen, dreimal HTTP 200, `list-apps` nennt frappe, erpnext, erp_ai_app, sut_app_tax, pdf_a_3.

## 8. Stand der Umsetzung

| Schritt | Stand 22.10.2026, 00:55 |
|---|---|
| Host-Setup | ✅ gelaufen (Deploy-Keys fuer erp_ai_app und sut_app_tax bei GitHub, Admin-Kennwort, Jenkins-Schluessel) |
| `erpai` | ✅ laeuft, HTTP 200, Apps erp_ai_app 0.2.1 (`main`), sut_app_tax 0.8.0, pdf_a_3 0.0.1, Badge-Regeln angelegt |
| `erpai-stage` | ✅ laeuft, HTTP 200, erp_ai_app aus `staging`, Entwicklermodus an |
| `erpai-dev` | ✅ laeuft, HTTP 200, erp_ai_app aus `dev/customer`, Badge `CUSTOMER · 3c45d99 · …` vom Deploy-Job |
| `erpai-jenkins` | ✅ laeuft, ohne Assistent eingerichtet; Benutzer `developer` und `customer` mit Tokens; neun Jobs |
| Jenkins-Jobs geprueft | ✅ `erpai-deploy-customer #1` und `erpai-backup-dev #1` SUCCESS — Polling und Zeittrigger damit aktiv |
| Offen | Customer-Konto in ERPNext (Benutzer, API-Schluessel), Cloud-Umgebungen „Customer" und „Developer" bei Claude; erster Lauf von `erpai-backup-prod` / `-stage` (aktiviert deren Zeittrigger: `Units/jenkins/setup-jenkins.sh --run erpai-backup-prod --run erpai-backup-stage` oder in Jenkins „Jetzt bauen") |
