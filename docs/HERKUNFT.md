# Herkunft der uebernommenen Teile

Stand 22.10.2026. Vorlage: Betrieb und App eines Kundenprojekts (Repo `mkt1/cleanunit`,
`projekte/20260711_Datensynchronisation/betrieb` und Submodul `Kittner-Digital/erpnext_cleanunit`), dort wiederum
aus `schmidtundtoechter/erpnext_infrastructure` (Komponente, Units) und `sut_app_core` (Site Branding).

| Pfad hier | Quelle | Aenderungen |
|---|---|---|
| `Components/de/erpai/erpnext/16.x/` | cleanunit `betrieb/Components/de/cleanunit/erpnext/16.x/` (urspruenglich `erpnext_infrastructure`, Commit `73d78b3`, plus Abweichungen vom 04.10.2026: Admin-Kennwort aus `_secrets`, `bench build` vor `migrate`, DB-Backup vor dem Upgrade, Entwicklermodus je Szenario) | keine — enthaelt nichts Kundenspezifisches |
| `Units/backup/cleanupOldArchives.sh`, `cleanupDockerImages.sh`, `link-backup-files.sh`, `rewire-mail-to-mailpit.sh` | dito `Units/backup/` | keine |
| `Units/backup/set-badge.sh` | dito | Standardregel `CUSTOMER` statt `TONY` |
| `Units/host/setup-host.sh`, `install-docker.sh`, `.bashrc-mkc` | dito `Units/host/` (identisch in `kittner.netcup` und `erpnext_infrastructure`) | keine |
| `Units/host/erpai.host.conf`, `setup-host-erpai.sh` | dito `cleanunit.host.conf`, `setup-host-cleanunit.sh` | Namen, Pfade, Platzhalter; Deploy-Key wird per `gh` eingetragen; Traefik-Erkennung; Pruefung freier Szenario-Namen; Pruefung des **freien** RAM |
| `Units/jenkins/*` | dito `Units/jenkins/` | Namen (`erpai-*`, `customer`), Jenkins liest dieses Repo (voller Checkout statt Sparse), Benutzername aus `erpai.host.conf` |
| `Jenkins/Jenkinsfile.backup`, `.update`, `.resetStage`, `.deploy` | dito `Jenkins/` | Namen, Pfade relativ zur Wurzel (`INFRA_DIR`), gemeinsame `environment`-Werte, Server als Variable (`TARGET_HOSTNAME`), ohne Sage-VPN |
| `Scenarios/de/erpai/*.scenario.env` | dito `Scenarios/de/cleanunit/` | Werte fuer ERP AI (Platzhalter), Ports 8180–8182 / 8190, Volume-Praefixe |
| `Scenarios/de/erpai/erpai-jenkins/Dockerfile` | dito `jenkins/Dockerfile` (MIMS `io/jenkins/2.x.1` plus rsync und yq v4) | Kommentar |
| `scenario.deploy` | `schmidtundtoechter/metralabs_infrastructure` | keine |
| `README.md` | dito `betrieb/README.md` | verallgemeinert, Abschnitte Server (§4) und Platzhalter (§5) neu |
| **nicht uebernommen** | `Jenkinsfile.sageVpnTest`, `withSageVPN.groovy`, `Units/vpn/`, `05_Sage-VPN.md`, Mailpit-Szenario | kundenspezifisch bzw. nicht beauftragt |

Die Komponenten `io/jenkins/2.x.1` und `io/traefik-simple/proxy/3.x` werden **nicht** kopiert, sondern kommen aus dem
Submodul `MIMS/` (`Cerulean-Circle-GmbH/MIMS`, Branch `mims2`), das `scenario.deploy` als Rueckfall nach `./Components`
durchsucht.

**Trennlinie:** Die Komponente und die Backup-Skripte werden hier nicht weiterentwickelt. Korrekturen gehoeren ins
Quell-Repo (`erpnext_infrastructure`) und werden bewusst nachgezogen (Kopie erneuern, Commit hier vermerken).
Eigene Arbeit sind `Scenarios/`, `Jenkins/`, `Units/host/erpai.*`, `Units/jenkins/`, `docs/` und das README.
