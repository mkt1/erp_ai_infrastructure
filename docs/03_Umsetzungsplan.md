# 03 — Umsetzungsplan

> Abhakbar; Stand 22.10.2026. Reihenfolge wie gebaut.

## erp_ai_infrastructure
- [x] MIMS als Submodul (`mims2`), Wrapper `scenario.deploy`
- [x] ERPNext-Komponente `de/erpai/erpnext/16.x` (Kopie aus der Vorlage, ohne Kundenbezug)
- [x] Fuenf Szenarien `de/matthiaskittner/ki/*` mit `apps.json` (main / staging / dev/customer), Jenkins-Dockerfile
- [x] Servercheck ki.netcup / kittner.netcup, Namen und Ports kollisionsfrei
- [x] Jenkinsfiles: backup, update, resetStage, deploy
- [x] Jenkins-Setup: Credentials, neun Jobs, Customer-Benutzer mit API-Token
- [x] Host-Setup: `erpai.host.conf`, `setup-host-erpai.sh` (Deploy-Key per `gh`, Platzhalter-DNS, Traefik-Erkennung)
- [x] Units/backup inkl. `set-badge.sh` (Regel CUSTOMER)
- [x] Doku: README, 01–05, HERKUNFT, ssh-config.example, .gitignore
- [x] Submodul `erp_ai_app` auf den neuen Stand
- [x] Commit und Push `main`

## erp_ai_app
- [x] Frappe-App-Rahmen: `hooks.py`, `modules.txt`, `pyproject.toml`, `__init__.py` (Version 0.1.0), `patches.txt`
- [x] Modul Site Branding (DocType `Site Branding Rule`, API, JS, Standardregeln STAGE / CUSTOMER / PROD)
- [x] Modul Customer (leer: README, `setup.py` fuer den Module Def, `fixtures/custom_field.json` leer)
- [x] `scripts/`: erpai-env.sh, umgebung.sh, ausrollen.sh, erp.sh, pull-request.sh, release.py
- [x] `.claude/`: settings.json, Skills ausrollen, daten, nach-main, neuer-bericht, neues-feld, release
- [x] `.github/workflows/`: pfadregel.yml, release.yml
- [x] Doku: CLAUDE.md, README, CHANGELOG, docs/wie-ich-entwickle, einrichtung-customer-cloud, einrichtung-developer-cloud, einrichtung-customer-lokal, site_branding, festlegungen/
- [x] Repo privat; Branches `main`, `staging`, `dev/customer`
- [x] Commit und Push

## Rollout (22.10.2026, nach Entscheidung Matthias: ki.netcup, *.ki.matthiaskittner.de)
- [x] Domain und Namensraum `de/matthiaskittner/ki` eingetragen, Apps `sut_app_tax` und `pdf_a_3` ergaenzt
- [x] `setup-host.sh` auf ki.netcup (zweimal, wiederholbar)
- [x] `erpai`, `erpai-stage`, `erpai-dev`, `erpai-jenkins` mit `init,up` — alle HTTP 200
- [x] Jenkins ohne Browser eingerichtet (`setup-jenkins-init.sh`), Jobs und Benutzer angelegt, zwei Jobs gruen
- [x] `docs/SETUP.md` und `bootstrap.sh`
- [ ] Customer-Konto in ERPNext und Cloud-Umgebungen bei Claude anlegen (Matthias)
- [ ] Erster Lauf von `erpai-backup-prod` und `erpai-backup-stage` (aktiviert die Zeittrigger)
