# 01 — Erfolgskriterien (Lastenheft)

> Vorhaben: ERP-AI-Infrastruktur und leere ERP-AI-App, abgeleitet aus dem Betrieb bei einem Kundenprojekt,
> verallgemeinert. Auftrag Matthias, 21.10.2026 (Chat). Gemessen wird in [05_Pruefung.md](05_Pruefung.md).

## Infrastruktur (`erp_ai_infrastructure`)

| Nr. | Kriterium | Pruefbar durch |
|---|---|---|
| EK-01 | Fuenf Szenarien liegen unter `Scenarios/de/matthiaskittner/ki/`: Produktiv, Stage, Dev, Jenkins, Traefik | `ls Scenarios/de/matthiaskittner/ki/*.scenario.env` |
| EK-02 | Die ERPNext-Komponente liegt im Repo; Jenkins und Traefik kommen aus MIMS (Submodul `mims2`) | `Components/de/erpai/erpnext/16.x/`, `.gitmodules` |
| EK-03 | Die App `erp_ai_app` ist in allen drei ERPNext-Instanzen installiert: Produktiv `main`, Stage `staging`, Dev `dev/customer` | `Scenarios/de/matthiaskittner/ki/erpai*/apps.json` |
| EK-04 | Jenkins-Jobs sind vorbereitet: Backup, Update, Reset je Instanz, Deploy fuer die Customer-Umgebung | `Jenkins/Jenkinsfile.*`, `Units/jenkins/jenkins-setup.groovy` |
| EK-05 | Nichts Kundenspezifisches: keine Kunden-, Personen- oder Produktnamen, kein Sage, kein VPN | `grep -ri 'cleanunit\|clean-unit\|tony\|sage\|struktur'` leer (ausser HERKUNFT) |
| EK-06 | Das Repo ist eigenstaendig: Wrapper `scenario.deploy`, MIMS als Submodul, Pfade relativ zur Wurzel | `./scenario.deploy` ohne Argumente zeigt die Hilfe |
| EK-07 | Server und Domains stehen fest (ki.netcup, `*.ki.matthiaskittner.de`); ein Umzug ist mit einem Befehl moeglich | README §5 |
| EK-18 | `sut_app_tax` und `pdf_a_3` sind in allen drei Instanzen installiert; der Server erreicht das private Tax-Repo per eigenem Deploy-Key | `apps.json`, `setup-host.sh` 2.4b |
| EK-08 | Keine Zugangsdaten im Repo | `grep -ri 'password=\|token=' Scenarios Units Jenkins` nur Platzhalter/Hashes |
| EK-09 | Die Szenarien kollidieren nicht mit dem Bestand auf ki.netcup und kittner.netcup (Container-Praefixe, Ports) | [04_Servercheck.md](04_Servercheck.md) |
| EK-10 | Eine Empfehlung, auf welchem Server wie viel davon laeuft, ist dokumentiert | [04_Servercheck.md](04_Servercheck.md) |

## App (`erp_ai_app`)

| Nr. | Kriterium | Pruefbar durch |
|---|---|---|
| EK-11 | Leere Frappe-App: keine fachlichen DocTypes, Berichte oder Felder — nur Rahmen (Site Branding, Modul `Customer`) | `modules.txt`, `find erp_ai_app -name '*.json'` |
| EK-12 | Der Arbeitsprozess mit Claude ist uebernommen: `CLAUDE.md`, `scripts/` (umgebung, ausrollen, erp, pull-request, release), Skills (ausrollen, daten, nach-main, neuer-bericht, neues-feld, release), Workflows (Pfadregel, Release) | Dateien vorhanden, `bash -n` fehlerfrei |
| EK-13 | Alle Umgebungsvariablen beginnen mit `ERPAI_` statt `CU_` | `grep -rn 'CU_' erp_ai_app` leer |
| EK-14 | Zwei Umgebungen: `ERPAI_DEV=customer` (eingeschraenkt wie die Vorlage: ein Branch, Pfadregel, keine PR-Merges) und `ERPAI_DEV=developer` (offen: kein Branch-Zwang, alle Pfade) | `scripts/erpai-env.sh`, `scripts/umgebung.sh`, `CLAUDE.md` |
| EK-15 | Was in der Vorlage „Tony" hiess, heisst „Customer"; was „Matthias" hiess, heisst „Developer" | `grep -rni 'tony\|matthias' erp_ai_app` leer |
| EK-16 | Branches `main`, `staging`, `dev/customer` existieren auf GitHub; die Dev-Instanz zieht `dev/customer` | `git ls-remote --heads`, `apps.json` |
| EK-17 | Alles ist committet und gepusht (beide Repos); `erp_ai_app` ist privat | `git status`, `gh repo view` |
