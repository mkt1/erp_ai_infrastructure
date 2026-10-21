# 04 — Servercheck: wo koennen die Szenarien laufen?

> Messung am 21.10.2026, 23:59 Uhr, nur lesend per SSH (`free -m`, `nproc`, `df -h`, `docker stats`, `docker system df`).
> Frage Matthias: Wie viel Platz haben kittner.netcup und ki.netcup, was davon ist realistisch, ohne den Server flachzulegen?

## Messwerte

| | kittner.netcup (`automate`) | ki.netcup (`ki`) |
|---|---|---|
| CPU | 4 Kerne | 12 Kerne (AMD EPYC Genoa) |
| RAM gesamt | 7,9 GB, kein Swap | 32 GB, kein Swap |
| RAM **verfuegbar** | **2,8 GB** (5,1 GB belegt) | **19,2 GB** (12,9 GB belegt) |
| Last (1/5/15 min) | 0,18 / 0,11 / 0,18 | 0,63 / 1,02 / 1,14 |
| Platte | 251 GB, 203 GB belegt (85 %), **39 GB frei** | 1 TB, 363 GB belegt (38 %), **604 GB frei** |
| davon Backups unter `_backups` | 112 GB | 217 GB |
| Docker | 27.5, 23 Container, Images 15,6 GB, Volumes 40 GB | 28.4, 57 Container, Images 70 GB (36 GB aufraeumbar), Volumes 40 GB |
| Groesste Verbraucher | Prometheus 0,9 GB, agedu 0,8 GB, Jenkins 0,7 GB, Open WebUI 0,7 GB | agedu 3,6 GB, Prometheus 2,2 GB, cimbali 1,1 GB, drei Open WebUI je ~0,8 GB |
| Schon vorhanden, was kollidiert | `traefik_*` (80/443), `jenkins_jenkins_container` | `traefik_*` (80/443), Szenario **`erp`** (ERPNext, `erp_erpnext_*`), `mailpit` |

## Bedarf der ERP-AI-Szenarien

Erfahrungswerte aus der Vorlage (ERPNext v16, Frappe-Stack mit backend, zwei Queues, scheduler, websocket,
frontend, MariaDB, zwei Redis):

| Szenario | RAM im Betrieb | RAM beim Image-Bau (einmalig, kurz) | Platte |
|---|---|---|---|
| ERPNext-Instanz (je) | 1,2–1,8 GB | +2–3 GB | Image ~3 GB, Volumes wachsen mit den Daten, Backups taeglich |
| `erpai-jenkins` | 0,5–0,8 GB | — | ~1 GB |
| `traefik` | 0,1 GB | — | — |
| **Alle drei ERPNext + Jenkins** | **~5–6 GB** | Spitze ~8 GB, wenn nacheinander gebaut wird | ~15 GB plus Daten und Backups |

## Bewertung

**kittner.netcup:** 2,8 GB verfuegbar, 39 GB Platte, davon 112 GB schon Backups. Schon **eine** ERPNext-Instanz
braucht beim Image-Bau mehr, als frei ist; der Bau wuerde den Server in den OOM-Killer treiben (kein Swap). Platte:
drei Instanzen mit taeglichen Backups sind in wenigen Wochen voll. **Realistisch: nichts davon.** Allenfalls Jenkins
allein (0,7 GB), aber es gibt dort schon einen.

**ki.netcup:** 19 GB verfuegbar, 604 GB Platte, 12 Kerne, Last niedrig. **Alle vier Szenarien** (`erpai`,
`erpai-stage`, `erpai-dev`, `erpai-jenkins`) passen mit Reserve; nach dem Ausrollen bleiben etwa 13 GB frei.
Bedingungen:
1. Den **vorhandenen Traefik** mitbenutzen (Szenario `traefik` nicht ausrollen; die ERP-AI-Szenarien haengen sich
   mit `SCENARIO_TRAEFIK_ENABLE="true"` in das Netz `traefik`).
2. **Namen kollisionsfrei** — deshalb `erpai*` statt `erp`/`erpstage`, `erpai-jenkins` statt `jenkins`
   ([02 E-08](02_Konzept.md)).
3. Instanzen **nacheinander** bauen (`init,up` je Szenario abwarten), nicht parallel.
4. Vorher `docker image prune` ueberlegen: 36 GB Images sind dort aufraeumbar (nicht Teil dieses Vorhabens).

**Empfehlung:** ki.netcup fuer alles. kittner.netcup bekommt nichts. Ein eigener Server (ab 16 GB RAM, 4 Kerne,
100 GB) waere die saubere Variante fuer einen Kunden — dann mit eigenem Traefik (`SCENARIOS_OPTIONAL`).
