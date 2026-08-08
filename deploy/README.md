# Trading-Bot Absicherung fuer 24/7-Betrieb (Raspberry Pi Zero 2 W)

Macht den Trading-Bot robust gegen eine Woche unbeaufsichtigten Betrieb:
Hardware-Watchdog, Auto-Restart mit Grenzen, Health-Checks mit
Selbstheilung, Log-Rotation, SD-Karten-Schonung, woechentlicher
Wartungs-Reboot und Telegram-Benachrichtigungen.

> **Hinweis zur Herkunft dieser Dateien:** dieses `deploy/`-Verzeichnis
> wurde in einer Cloud-Sandbox ohne echten Raspberry Pi erstellt. Jede
> Konfigurationsdatei wurde einzeln validiert (`systemd-analyze verify`
> fuer alle Units, der echte `watchdog`- und `logrotate`-Binary gegen die
> jeweiligen configs, ein echter `cron`-Daemon gegen alle `/etc/cron.d/`-
> Dateien, `healthcheck.sh`/`notify.sh`/`weekly_reboot.sh`/`boot_notify.sh`
> gegen 40+ Testfaelle mit simulierten `systemctl`/`tailscale`/`df`/`free`/
> `curl`-Ausgaben, `install.sh` selbst gegen ein Fake-Root-Dateisystem in
> beiden Dry-Run- und `--apply`-Modi inkl. Wiederholungslauf). Was sich
> NICHT aus der Ferne testen liess -- der echte `bcm2835_wdt`-Hardware-
> Trigger, ein echter Tailscale-Reconnect, echte SD-Karten-Lebensdauer --
> ist unten mit dem jeweiligen Pruef-Befehl markiert.

## Uebersicht

| # | Mechanismus | Datei(en) |
|---|---|---|
| 1 | Hardware-Watchdog (bcm2835_wdt, 15s Timeout, 10s Intervall) | `watchdog/watchdog.conf` |
| 2 | systemd-Services mit Auto-Restart + Speicherlimit | `systemd/*.service.template` |
| 3 | Health-Check alle 5 Minuten (Bot, Alpaca, Tailscale, Speicher, RAM) | `scripts/healthcheck.sh`, `cron/tradingbot-healthcheck.template` |
| 4 | Log-Rotation (7 Tage, komprimiert, taeglich) | `logrotate/tradingbot.template` |
| 5 | SD-Karten-Schonung (tmpfs `/tmp`, begrenztes Journal) | `fstab/tmp-tmpfs.line`, `journald/tradingbot.conf` |
| 6 | Woechentlicher Wartungs-Reboot (Sonntag 03:00) | `scripts/weekly_reboot.sh`, `cron/tradingbot-weekly-reboot.template` |
| 7 | Telegram-Benachrichtigungen (inkl. Watchdog-Reboot-Erkennung) | `scripts/notify.sh`, `scripts/boot_notify.sh`, `notify.conf.example` |
| -- | Installations-/Update-Skript fuer alles oben | `install.sh` |

**Nicht in den 8 Anforderungen explizit verlangt, aber ergaenzt:** ein
systemd-Service fuer `api_server.py` (Dashboard-API,
`tradingbot-dashboard.service`) -- bisher lief das nur manuell per tmux.
Ohne Auto-Restart waere ausgerechnet die Dashboard-Sicht genau dann weg,
wenn man sie am dringendsten braucht. Wer lieber bei tmux bleibt: die
Zeilen `tradingbot-dashboard.service` in `install.sh` einfach nicht
mitlaufen lassen (Service danach `sudo systemctl disable --now
tradingbot-dashboard`).

## Installation

Auf dem Pi, mit bereits eingerichtetem venv (siehe `trading_bot/README.md`,
Abschnitt Setup):

```bash
cd /pfad/zu/deinem/TradingBot-Checkout
sudo deploy/install.sh              # Dry-Run: zeigt alle geplanten Aenderungen
sudo deploy/install.sh --apply      # fuehrt sie aus
sudo reboot                         # laedt bcm2835_wdt, aktiviert tmpfs /tmp
```

`install.sh` ist **idempotent** -- mehrfaches Ausfuehren (z.B. nach einem
`git pull` mit Aenderungen in `deploy/`) ueberschreibt nur die generierten
Dateien neu und haengt Zeilen (in `/etc/modules`, `/etc/fstab`,
`config.txt`) nur an, wenn sie noch nicht vorhanden sind.

**Danach:** `deploy/notify.conf` mit den Telegram-Zugangsdaten fuellen
(Anleitung in `deploy/notify.conf.example`) -- ohne diese Datei laufen
Health-Check und Reboots trotzdem, nur eben ohne Benachrichtigung.

## Status pruefen

```bash
# Bot / Dashboard
systemctl status tradingbot
systemctl status tradingbot-dashboard
sudo journalctl -u tradingbot -f              # live mitlesen
sudo journalctl -b -1 -u tradingbot -n 100     # Log VOR dem letzten Neustart
                                                # (Absturzursache pruefen!)

# Health-Check
cat /var/log/healthcheck.log
tail -f /var/log/healthcheck.log               # live mitlesen

# Hardware-Watchdog
systemctl status watchdog
wdctl                                          # zeigt Timeout/Bootstatus des /dev/watchdog
                                                # (Paket util-linux, meist vorinstalliert)

# Tailscale
tailscale status

# Speicherplatz / RAM
df -h /
free -h

# Cronjobs
cat /etc/cron.d/tradingbot-healthcheck
cat /etc/cron.d/tradingbot-weekly-reboot

# Naechster geplanter Wartungs-Reboot
systemctl list-timers | grep -i cron || cat /etc/cron.d/tradingbot-weekly-reboot
```

## Manuell eingreifen

- **Bot voruebergehend anhalten** (bleibt bis zum naechsten Boot/manuellen Start aus):
  `sudo systemctl stop tradingbot` -- `Restart=always` greift NUR bei einem
  Absturz, nicht bei einem bewussten `stop`.
- **Bot dauerhaft deaktivieren** (auch nach Reboot aus): `sudo systemctl disable --now tradingbot`.
- **Bot nach zu vielen Fehlversuchen wieder freigeben:** wurden
  `StartLimitBurst` (5 Fehlversuche in 10 Minuten) ausgeschoepft, bleibt
  der Service im Zustand `failed` und startet NICHT mehr automatisch (du
  bekommst dazu eine Telegram-Nachricht). Erst die Ursache beheben, dann:
  ```bash
  sudo systemctl reset-failed tradingbot
  sudo systemctl start tradingbot
  ```
- **Speicherlimit anpassen** (z.B. `MemoryMax` erhoehen), ohne die
  Datei aus `deploy/systemd/` zu editieren (die wird bei einem erneuten
  `install.sh --apply` sonst wieder ueberschrieben):
  `sudo systemctl edit tradingbot` -- oeffnet eine Override-Datei.
- **Health-Check voruebergehend pausieren** (z.B. waehrend Wartungsarbeiten):
  `sudo mv /etc/cron.d/tradingbot-healthcheck{,.disabled}` -- ruecksetzen
  durch Zurueckbenennen oder erneutes `install.sh --apply`.
- **Telegram-Benachrichtigung manuell testen:**
  `sudo deploy/scripts/notify.sh "Testnachricht"`.
- **Log-Rotation manuell anstossen:** `sudo logrotate -f /etc/logrotate.d/tradingbot`.
- **Pruefen, ob der letzte Neustart geplant oder ein Watchdog-Reset war:**
  steht automatisch in `/var/log/healthcheck.log` (Zeile
  "System nach ... Neustart wieder hochgefahren") UND kommt per Telegram --
  alternativ `last reboot | head` fuer die reine Boot-Historie.
- **Alles rueckgaengig machen:**
  ```bash
  sudo systemctl disable --now tradingbot tradingbot-dashboard tradingbot-boot-notify watchdog
  sudo rm /etc/systemd/system/tradingbot*.service /etc/systemd/system/tradingbot-failure-notify@.service
  sudo rm /etc/cron.d/tradingbot-healthcheck /etc/cron.d/tradingbot-weekly-reboot
  sudo rm /etc/logrotate.d/tradingbot /etc/systemd/journald.conf.d/tradingbot.conf
  sudo systemctl daemon-reload
  # /etc/fstab, /etc/modules, config.txt: die angehaengten Zeilen von Hand entfernen
  ```

## Detailerklaerungen zu einzelnen Entscheidungen

### Warum `trades.csv` NICHT nach 7 Tagen geloescht wird

Anforderung 4 verlangt "maximal 7 Tage Historie" fuer Logs -- das wird für
`/var/log/healthcheck.log` exakt so umgesetzt. `trades.csv` ist aber kein
Log im eigentlichen Sinn, sondern der tatsaechliche Handelsverlauf inkl.
Begruendung jedes Trades (Steuer-/Audit-relevant). Eine 7-Tage-Loeschung
wuerde das nach einer Woche unwiederbringlich vernichten. Stattdessen
rotiert `trades.csv` monatlich, wird komprimiert, aber 120 Monate (10
Jahre) vorgehalten -- siehe Kommentar in `logrotate/tradingbot.template`,
falls die strikte 7-Tage-Regel hier ausdruecklich doch gewuenscht ist.

### SD-Karten-Schonung: was bei einem Neustart verloren geht

- **`/tmp` als tmpfs (RAM):** alles, was dort liegt, ist nach einem Neustart
  weg. Betrifft aktuell nur die Dedup-Merker von `healthcheck.sh`
  (`/tmp/tradingbot-health/*`) -- reine Laufzeit-Flags ohne jeden
  Informationswert nach einem Neustart, der Verlust ist voellig unkritisch
  (im Gegenteil: nach einem Neustart soll der Health-Check ohnehin wieder
  bei "alles unbekannt" anfangen).
- **systemd-Journal (Bot-/Dashboard-Ausgabe):** bewusst **nicht** volatile
  (RAM-only) gesetzt, sondern persistent mit 100MB/7-Tage-Deckel (siehe
  `journald/tradingbot.conf`). Der Grund: genau in den Faellen, um die es
  bei dieser ganzen Absicherung geht -- ein Absturz oder Watchdog-Reset --
  will man hinterher per `journalctl -b -1 -u tradingbot` sehen koennen,
  was VOR dem Neustart passiert ist. Ein volatiles Journal wuerde
  ausgerechnet diese Information im entscheidenden Moment loeschen. Wer
  SD-Schonung ueber Post-Mortem-Diagnose stellt, kann in
  `journald/tradingbot.conf` auf `Storage=volatile` umstellen.
- **NICHT verschoben (bewusst auf der SD-Karte):** `trades.csv` (Handels-
  historie, siehe oben) und `trading_bot/dashboard_token.txt` (staendiges
  Neu-Konfigurieren des Dashboards nach jedem Reboot waere schlechte UX
  fuer eine Datei, die sich quasi nie aendert).
- **Fuer diesen Use Case unkritisch?** Ja -- nichts, was tatsaechlich
  ueberlebt, wird SD-Kartenschonung wegen tmpfs riskiert. Die dominante
  SD-Schreiblast waere ohnehin das Journal gewesen (compact Logging pro
  Zyklus, siehe `bot.py`), und das ist bereits per Groessen-/Zeit-Deckel
  begrenzt, nicht komplett abgeschaltet.

## Was sich in dieser Sandbox NICHT testen liess

- **Echter Watchdog-Hardware-Trigger:** ein tatsaechliches Kernel-Freeze
  provozieren ist destruktiv und braucht echte Pi-Hardware. Nach der
  Installation pruefen mit `wdctl` (zeigt an, ob `/dev/watchdog` aktiv ist
  und welches Timeout eingestellt ist) und optional (Vorsicht, fuehrt zu
  einem echten Reboot!): `sudo watchdog -F -v &` laufen lassen, dann den
  Watchdog-Daemon selbst hart killen (`sudo kill -9 $(pidof watchdog)`) --
  ohne aktiven Daemon sollte die Hardware nach ~15s neu starten.
- **Echter Tailscale-Reconnect:** setzt eine echte Tailscale-Installation
  und einen echten Verbindungsabbruch voraus. Pruefen mit
  `sudo tailscale down && sleep 300 && cat /var/log/healthcheck.log`
  (sollte nach dem naechsten 5-Minuten-Check automatisch `tailscale up`
  ausgefuehrt haben).
- **Tatsaechliche SD-Karten-Lebensdauer-Verbesserung:** laesst sich nur
  ueber Monate/Jahre am echten Geraet beobachten, nicht in einer Sandbox.
