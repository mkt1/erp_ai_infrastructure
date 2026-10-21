# 03 — Umsetzungsplan

> Abhakbar; Stand 22.10.2026. Reihenfolge wie gebaut.

## erp_ai_infrastructure
- [x] MIMS als Submodul (`mims2`), Wrapper `scenario.deploy`
- [x] ERPNext-Komponente `de/erpai/erpnext/16.x` (Kopie aus der Vorlage, ohne Kundenbezug)
- [x] Fuenf Szenarien `de/erpai/*` mit `apps.json` (main / staging / dev/customer), Jenkins-Dockerfile
- [x] Servercheck ki.netcup / kittner.netcup, Namen und Ports kollisionsfrei
- [x] Jenkinsfiles: backup, update, resetStage, deploy
- [x] Jenkins-Setup: Credentials, neun Jobs, Customer-Benutzer mit API-Token
- [x] Host-Setup: `erpai.host.conf`, `setup-host-erpai.sh` (Deploy-Key per `gh`, Platzhalter-DNS, Traefik-Erkennung)
- [x] Units/backup inkl. `set-badge.sh` (Regel CUSTOMER)
- [x] Doku: README, 01–05, HERKUNFT, ssh-config.example, .gitignore
- [x] Submodul `erp_ai_app` auf den neuen Stand
- [ ] Commit und Push `main`

## erp_ai_app
- [x] Frappe-App-Rahmen: `hooks.py`, `modules.txt`, `pyproject.toml`, `__init__.py` (Version 0.1.0), `patches.txt`
- [x] Modul Site Branding (DocType `Site Branding Rule`, API, JS, Standardregeln STAGE / CUSTOMER / PROD)
- [x] Modul Customer (leer: README, `setup.py` fuer den Module Def, `fixtures/custom_field.json` leer)
- [x] `scripts/`: erpai-env.sh, umgebung.sh, ausrollen.sh, erp.sh, pull-request.sh, release.py
- [x] `.claude/`: settings.json, Skills ausrollen, daten, nach-main, neuer-bericht, neues-feld, release
- [x] `.github/workflows/`: pfadregel.yml, release.yml
- [x] Doku: CLAUDE.md, README, CHANGELOG, docs/wie-ich-entwickle, einrichtung-customer-cloud, einrichtung-developer-cloud, einrichtung-customer-lokal, site_branding, festlegungen/
- [x] Repo privat; Branches `main`, `staging`, `dev/customer`
- [ ] Commit und Push

## Offen (nach diesem Vorhaben, braucht Matthias)
- [ ] Server und Domains festlegen, Platzhalter ersetzen (README §5)
- [ ] `setup-host.sh` auf dem Zielserver laufen lassen, Szenarien `init,up`
- [ ] Jenkins einrichten (`setup-jenkins.sh`, `setup-jenkins-customer.sh`), ersten Lauf der Jobs
- [ ] Customer-Konto in ERPNext und Cloud-Umgebung „Customer" bei Claude anlegen
