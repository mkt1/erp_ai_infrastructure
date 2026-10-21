# 05 — Pruefung gegen die Erfolgskriterien und Retrospektive

> Geprueft am 22.10.2026 nach dem Push beider Repos. Kriterien aus [01_Erfolgskriterien.md](01_Erfolgskriterien.md).
> Was hier **nicht** geprueft werden konnte: ein echter Lauf von `setup-host.sh`, `init,up` und der Jenkins-Jobs —
> dafuer fehlen Server und Domains (Platzhalter). Die Skripte sind syntaxgeprueft (`bash -n`, `py_compile`), die
> Jenkinsfiles auf Klammerbalance; ihr Ablauf ist der der Vorlage, die bei Clean Unit seit 04.10.2026 laeuft.

## Infrastruktur

| Nr. | Ergebnis | Nachweis |
|---|---|---|
| EK-01 | ✅ | fuenf `*.scenario.env` unter `Scenarios/de/matthiaskittner/ki/`: erpai, erpai-stage, erpai-dev, erpai-jenkins, traefik |
| EK-02 | ✅ | `Components/de/erpai/erpnext/16.x/` (17 Dateien); `.gitmodules`: MIMS Branch `mims2` |
| EK-03 | ✅ | `apps.json`: erpai → `main`, erpai-stage → `staging`, erpai-dev → `dev/customer` |
| EK-04 | ✅ | vier Jenkinsfiles; `jenkins-setup.groovy` legt neun Jobs an (3× backup, 3× update, resetStage, resetDev, deploy-customer) |
| EK-05 | ✅ | `grep -ri` ueber Infra und App: nur Teilwort-Treffer (`Usage`, `sagen`, `message`, `Infrastruktur`) und die Herkunftsvermerke in `HERKUNFT.md` / `02_Konzept.md` |
| EK-06 | ✅ | `./scenario.deploy` zeigt die MIMS-Hilfe; alle Pfade in Jenkinsfiles relativ zu `INFRA_DIR = WORKSPACE` |
| EK-07 | ✅ | README §5: ein `sed`-Aufruf; Platzhalter in Szenarien, host.conf, Jenkinsfiles, ssh-config.example, App-Skripten, Badge-Regeln benannt |
| EK-08 | ✅ | nur `BITTE_SETZEN`, Variablen und Hash-Platzhalter; Kennwoerter entstehen auf dem Server |
| EK-09 | ✅ | Namen `erpai*`, `erpai-jenkins`; Ports 8180–8182, 8190; `traefik` optional — gegen `docker ps` beider Server geprueft ([04](04_Servercheck.md)) |
| EK-10 | ✅ | [04_Servercheck.md](04_Servercheck.md): ki.netcup alles, kittner.netcup nichts |

## App

| Nr. | Ergebnis | Nachweis |
|---|---|---|
| EK-11 | ✅ | `modules.txt`: ERP AI App, Site Branding, Customer; einzige DocType-JSON ist `Site Branding Rule`; `fixtures/custom_field.json` = `[]` |
| EK-12 | ✅ | sechs Skripte (`bash -n`, `py_compile` ok; `release.py --dry-run` laeuft), sechs Skills, zwei Workflows, `settings.json` valides JSON |
| EK-13 | ✅ | `grep -rn '\bCU_' erp_ai_app` leer |
| EK-14 | ✅ | `erpai-env.sh`: `case "$ERPAI_DEV"` mit `developer` (kein Branch, Stage, update-stage) und Customer (dev/<name>, Dev, deploy-<name>); `umgebung.sh` wechselt nur als Customer; `pull-request.sh` prueft die Pfadregel nur als Customer |
| EK-15 | ✅ | `grep -rni 'tony\|matthias' erp_ai_app` nur `matthiaskittner.de` (Autor in pyproject/hooks) und `sagen`-Teilwoerter |
| EK-16 | ✅ | `git ls-remote --heads`: `main`, `staging`, `dev/customer` — alle auf dem Release-Commit v0.2.0 |
| EK-17 | ✅ | `gh repo view`: private=true; `git status` in beiden Repos leer nach dem Push |

**Nebenbefund:** Die Release-Action lief beim ersten Push auf `main` sofort und erzeugte **v0.2.0** (Betreff `feat:`
→ Minor von 0.1.0). Das ist das vorgesehene Verhalten; `staging` und `dev/customer` wurden auf diesen Commit
nachgezogen, damit alle Instanzen beim ersten `init,up` dieselbe Version tragen.

## Nachtrag 22.10.2026 — Rollout auf ki.netcup

| Nr. | Ergebnis | Nachweis |
|---|---|---|
| EK-07 | ✅ | Server ki.netcup, Domains `*.ki.matthiaskittner.de`, Namensraum `de/matthiaskittner/ki`; Umzugsbefehl README §5 |
| EK-09 | ✅ | vier Szenarien laufen neben 57 Bestandscontainern, Traefik des Servers mitbenutzt, keine Kollision |
| EK-18 | ✅ | `bench list-apps` auf allen drei Instanzen: erp_ai_app, sut_app_tax 0.8.0, pdf_a_3 0.0.1; Tax-Repo per eigenem Deploy-Key |
| Rollout | ✅ | `erpai`, `erpai-stage`, `erpai-dev` HTTP 200; `erpai-jenkins` mit neun Jobs; `erpai-deploy-customer #1` und `erpai-backup-dev #1` SUCCESS |
| Nicht geprueft | ⚠️ | `erpai-update-*` und `erpai-resetStage/-resetDev` sind noch nicht gelaufen (greifen in laufende Instanzen ein; erster Lauf bewusst von Hand) |

**Retro-Nachtrag:** Der Einrichtungsassistent von Jenkins war in der Vorlage ein Klickweg; hier ersetzt ihn
`setup-jenkins-init.sh` (Plugins per CLI, init-Skript) — damit ist `bootstrap.sh` ohne Browser durchlaufbar.
Zwei Shell-Fallen kosteten je einen Durchlauf: zsh teilt unquotierte Variablen nicht an Leerzeichen (Dateiliste an
`perl` ueber `xargs` geben), und `git mv -k` schweigt bei ungetrackten Dateien.

## Offen (braucht Matthias)

- Customer-Konto in ERPNext (Produktiv und Dev), API-Schluessel, Cloud-Umgebungen „Customer" / „Developer".
- Erster Lauf von `erpai-backup-prod` / `erpai-backup-stage`, damit deren Zeittrigger greifen.

## Retrospektive

**Was gut lief:** Die Vorlage war vollstaendig und sauber getrennt (Komponente ohne Kundenbezug, Namen in wenigen
Dateien). Die Rueckfragen vor dem Bau (acht Entscheidungen in zwei Runden) haben Nacharbeit verhindert — mit einer
Ausnahme, siehe unten. Der Servercheck kam mitten im Bau als Zusatzauftrag und hat eine Entscheidung veraendert
(Szenario-Namen, Platzhalter-Server): gut, dass er vor dem Commit kam.

**Was gefehlt hat:** Die Kollision der Szenario-Namen mit dem Bestand auf den Servern (`erp`, `jenkins`,
`traefik`) war in Schritt 1 kein Kriterium — sie fiel erst beim Servercheck auf. EK-09 wurde nachgetragen. Lehre:
Bei Infrastruktur auf **geteilten** Servern gehoert „kollidiert mit nichts Vorhandenem" von Anfang an in die
Erfolgskriterien, und der Blick auf den Zielserver vor den Namensentscheidungen.

**Abkuerzungen:** Zwei Heredoc-Fehler beim Schreiben der Jenkinsfiles (inneres `EOF` beendete das aeussere) und
ein fehlgeschlagenes `git mv` haben einen Zwischenstand mit falschen Dateinamen erzeugt; beides wurde vor dem
Commit bemerkt, weil nach jedem Schritt `ls`/`grep` gelaufen sind. Nicht abgekuerzt: Schritt 4 wurde gegen alle
17 Kriterien einzeln geprueft, nicht gegen den Eindruck.

**An die fuenf Schritte gehalten?** Ja — mit der Besonderheit, dass Schritt 1 und 2 hier nach den Rueckfragen
als Dateien geschrieben wurden, nicht vor dem Bau der ersten Dateien; die Entscheidungen standen aber vorher fest
(Chat). Fuer das naechste Vorhaben: 01/02 als erstes schreiben, dann bauen.
