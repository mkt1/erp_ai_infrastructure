# 02 — Konzept (Pflichtenheft)

> Entscheidungen fuer die Umsetzung von [01_Erfolgskriterien.md](01_Erfolgskriterien.md). Rueckfragen und
> Antworten von Matthias am 21.10.2026 (Chat).

## Entscheidungen

| Nr. | Frage | Entscheidung | Warum |
|---|---|---|---|
| E-01 | Server | Platzhalter; SSH-Alias `ki.netcup`, Domains `*.example.de` | Matthias wollte zuerst kittner.netcup als Platzhalter; der Servercheck ([04](04_Servercheck.md)) zeigte, dass nur ki.netcup genug Platz hat — der Platzhalter folgt der Empfehlung, ist aber mit einem Befehl aenderbar (README §5) |
| E-02 | Branch des Dev-Servers | `dev/customer` | Schema `dev/<name>` aus der Vorlage bleibt: `ERPAI_DEV=customer` ergibt Branch, Instanz, Job; die Pfadregel greift auf `dev/*` |
| E-03 | Stage-Branch | `staging` | Stage als Vorstufe fuer den Developer; Produktiv zieht `main` |
| E-04 | Variablen-Praefix | `ERPAI_` | eindeutig, lesbar; ersetzt `CU_` eins zu eins |
| E-05 | Sichtbarkeit `erp_ai_app` | privat | wie die Vorlage: Server und Jenkins holen die App per Deploy-Key; was der Customer baut, bleibt nicht oeffentlich |
| E-06 | MIMS | Submodul, Branch `mims2`, Wrapper `scenario.deploy` in der Wurzel | Repo eigenstaendig lauffaehig (wie metralabs_infrastructure) |
| E-07 | Namensraum | `de/erpai` | kurz; Jenkins-Jobs `erpai-*` |
| E-08 | Szenario-Namen | `erpai`, `erpai-stage`, `erpai-dev`, `erpai-jenkins`, `traefik` (optional) | MIMS leitet Container- und Volume-Namen aus dem Szenario-Namen ab, nicht aus dem Namensraum. Auf ki.netcup gibt es schon `erp`, auf beiden Servern `traefik` und auf kittner.netcup `jenkins` — mit den Vorlagen-Namen (`erp`, `erpstage`, `jenkins`) gaebe es Kollisionen |
| E-09 | Traefik | Szenario liegt bei, wird auf ki.netcup/kittner.netcup **nicht** ausgerollt (`SCENARIOS_OPTIONAL`) | beide Server haben einen Traefik, der 80/443 haelt; die ERP-AI-Szenarien haengen sich in dessen Netz `traefik` |
| E-10 | Ports | ERPNext-Frontends 8180/8181/8182 (nur intern), Jenkins Host-Port 8190 | 8080–8082 und 8090 sind auf kittner.netcup belegt |
| E-11 | Developer-Umgebung | `ERPAI_DEV=developer`: kein Branch-Zwang, `umgebung.sh` wechselt keinen Branch, alle Pfade, darf PRs anlegen und mergen | Antwort Matthias: „frei, ohne Standardbranch" |
| E-12 | Customer-Umgebung | `ERPAI_DEV=customer`: nur `dev/customer`, Pfadregel auf `erp_ai_app/customer/`, `fixtures/`, `docs/festlegungen/`, keine PR-Merges, Wuensche an den Developer in `docs/festlegungen/wuensche-an-developer.md` | eins zu eins die Regeln der Vorlage, Namen verallgemeinert |
| E-13 | Inhalt der App | leer: Module `ERP AI App`, `Site Branding` (Badge je Adresse), `Customer` (Bereich des Customers, noch ohne Objekte); Custom-Field-Praefix `customer_` | Auftrag: „erstmal voellig ohne zusaetzliche ERPNext-Funktionalitaet"; Site Branding ist Infrastruktur (Badge STAGE / CUSTOMER), kein Fachinhalt |
| E-14 | Branding | kein Logo, keine Schrift, kein CSS-Bundle | kundenspezifisch; Badge-Regeln bleiben |
| E-15 | Mailpit | kein eigenes Szenario; Reset-Jobs legen Mails still (`mute_emails`), Mailpit optional per Parameter | Auftrag nennt fuenf Szenarien |
| E-16 | Push | beide Repos nach GitHub pushen; `staging` und `dev/customer` auf origin anlegen | Jenkins und `apps.json` brauchen die Branches auf origin |
| E-17 | Aenderungen | nur in `erp_ai_infrastructure` und `erp_ai_app`; cleanunit, kittner.netcup, metralabs bleiben unangetastet | Vorgabe Matthias |

## Abbildung Vorlage → ERP AI

| Vorlage (cleanunit/betrieb, erpnext_cleanunit) | Hier |
|---|---|
| `de/cleanunit/erp`, `erpstage`, `erptony`, `jenkins`, `traefik` | `de/erpai/erpai`, `erpai-stage`, `erpai-dev`, `erpai-jenkins`, `traefik` |
| `cleanunit.struktur`, `struktur*.clean-unit.org` | `ki.netcup`, `erp*.example.de` (Platzhalter) |
| `Kittner-Digital/erpnext_cleanunit`, `main` / `main` / `dev/tony` | `mkt1/erp_ai_app`, `main` / `staging` / `dev/customer` |
| `cleanunit-backup-prod` … `cleanunit-deploy-tony` | `erpai-backup-prod` … `erpai-deploy-customer` |
| `CU_DEV=tony`, `CU_*` | `ERPAI_DEV=customer` oder `developer`, `ERPAI_*` |
| Modul `CU Tony`, `cu_tony_*`, `cu_tony/` | Modul `Customer`, `customer_*`, `customer/` |
| Tony / Matthias | Customer / Developer |
| `wuensche-an-matthias.md` | `wuensche-an-developer.md` |
| Badge `TONY` | Badge `CUSTOMER` |
| Jenkins-Benutzer `tgerstner` | `customer` (`CUSTOMER_JENKINS_USER`) |
| `sage_sync`, Sage-VPN, Branding (Logo, Fonts), `cu_tony`-Berichte, Festlegungen | entfaellt |
