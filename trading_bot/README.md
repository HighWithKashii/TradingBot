# Alpaca Trading Bot

Vollautomatischer, modularer Trading-Bot fuer Alpaca (Paper-Trading zuerst).

> **Disclaimer:** Dies ist keine Finanzberatung. Nutze ausschliesslich das
> Paper-Trading-Konto zum Testen, bevor du (falls ueberhaupt) live handelst.
> Handel mit Wertpapieren ist mit Verlustrisiko verbunden — auch mit diesem Bot.

## Module

| Datei | Verantwortlichkeit |
|---|---|
| `config.py` | Laedt alle Parameter aus `.env` (Keys, Watchlist, Strategie- und Risikoparameter). |
| `nasdaq100.py` | Statische Nasdaq-100-Tickerliste (manuell pflegen, siehe unten). |
| `indicators.py` | Reine SMA/EMA/RSI/MACD-Berechnung (pandas, keine externen TA-Libs). |
| `strategy.py` | Kombiniert Trendfilter (SMA-Crossover), MACD-Crossover und RSI zu BUY/SELL/HOLD inkl. Begruendung. |
| `risk_manager.py` | Positionsgroesse (% des Kapitals), Stop-Loss/Take-Profit-Preise, Tagesverlust-Limit. |
| `data_feed.py` | Alpaca Marktdaten (historische Bars per Batch-Requests, Market Clock). |
| `order_executor.py` | Alpaca Order-Ausfuehrung (Bracket-Orders mit SL/TP, Positionen schliessen). |
| `trade_logger.py` | Schreibt jede Entscheidung (inkl. HOLD/Begruendung) in eine CSV-Datei. |
| `patterns.py` | Trendlinien-/Chartmuster-Erkennung (Pivots, Trendlinien, Breakouts) -- komplett eigenstaendig, kennt weder Config noch Alpaca. |
| `backtest.py` | Backtest-Modul: spielt die Strategie (inkl. Pattern-Modul) auf historischen Daten durch. |
| `bot.py` | Haupt-Loop: Marktzeiten pruefen, Watchlist durchgehen, Fehlerbehandlung pro Symbol. |
| `main.py` | Einstiegspunkt (`python -m trading_bot.main`). |
| `api_server.py` | Read-only Status-API fuers Mobile-Dashboard (`python -m trading_bot.api_server`), siehe unten. |
| `index.html` (im Projekt-Root, eine Ebene ueber `trading_bot/`) | Statische Dashboard-Seite fuers Handy (GitHub Pages), siehe unten. |

Jedes Modul laesst sich unabhaengig austauschen — z. B. eine andere Strategie
in `strategy.py`, ein anderes Sizing-Modell in `risk_manager.py`, oder ein
anderer Broker in `data_feed.py`/`order_executor.py`.

## Setup

Alle Befehle unten gehen vom **Projekt-Root** aus (dem Verzeichnis, das den
Ordner `trading_bot/` enthaelt) -- `python -m trading_bot.xxx` findet das
Package nur von dort aus, nicht von innerhalb von `trading_bot/` selbst.

```bash
python -m venv trading_bot/.venv
source trading_bot/.venv/bin/activate  # Windows: trading_bot\.venv\Scripts\activate
pip install -r trading_bot/requirements.txt
cp trading_bot/.env.example trading_bot/.env
```

Trage in `trading_bot/.env` deine **Paper-Trading**-API-Keys ein
(https://app.alpaca.markets, "Paper Trading" Bereich). `ALPACA_PAPER=true`
sorgt dafuer, dass ausschliesslich der Paper-Endpunkt
(`paper-api.alpaca.markets`) verwendet wird. Keys stehen ausschliesslich in
`.env` (nicht eingecheckt, siehe `.gitignore`) — niemals im Code.

`ALPACA_DATA_FEED=iex` (Default) legt fest, welcher Markt-Daten-Feed fuer
historische Bars angefragt wird. Kostenlose/Paper-Accounts haben nur Zugriff
auf `iex` -- ohne dieses explizite `feed=` in der Anfrage faellt Alpaca still
auf `sip` (Consolidated Feed) zurueck und liefert dann **leere Ergebnisse
ohne Fehlermeldung**, wenn der Account dafuer nicht freigeschaltet ist. Nur
mit einem bezahlten Markt-Daten-Abo auf `sip` umstellen.

## Start

```bash
python -m trading_bot.main
```

Der Bot laeuft in einer Endlosschleife, prueft alle `CHECK_INTERVAL_MINUTES`
Minuten die Watchlist, verlangt aber, dass die Boerse laut Alpaca-Clock
geoeffnet ist. Mit `Strg+C` sauber beenden.

Direkt beim Start laedt der Bot per Backfill (siehe `data_feed.backfill_bars`)
fuer jedes Watchlist-Symbol genug historische Bars nach, damit SMA/EMA/RSI/MACD
schon im allerersten Zyklus vollstaendig berechenbar sind -- kein tage-/
wochenlanges "nicht genug Historie" mehr nach einem Neustart. Wie viele Bars
das sind, ergibt sich automatisch aus der laengsten konfigurierten Periode
(v.a. `SMA_SLOW`); Aenderungen an den `.env`-Parametern erfordern keine
Anpassung. Ein einzelnes Symbol, das beim Backfill fehlschlaegt (z.B.
kurzzeitiger Alpaca-Ausfall, nach 3 Versuchen), blockiert nicht die anderen --
es sammelt dann wie zuvor ueber die naechsten Live-Zyklen auf. Zusammenfassung
direkt im Log nach dem Start sichtbar ("Backfill abgeschlossen in ...").

## Strategie (Standardparameter)

- **Trendfilter:** SMA 50 vs. SMA 200 (Golden Cross = Aufwaertstrend).
- **Einstiegstrigger:** MACD(12,26,9)-Linie kreuzt die Signallinie von unten (bullisches Crossover) -- der Crossover selbst darf bis zu `MACD_CROSS_LOOKBACK_BARS` Bars (Standard: 5) zurueckliegen, muss also nicht exakt auf derselben Bar wie die SMA-Trendbestaetigung passieren, solange MACD seitdem nicht wieder unter die Signallinie gefallen ist.
- **Bestaetigung:** RSI(14) zwischen 30 und 70 (kein ueberkaufter/ueberverkaufter Extremzustand).
- **Einstieg (BUY):** nur wenn Trendfilter, (rueckblickender) Einstiegstrigger und RSI-Bestaetigung auf der aktuellen Bar gleichzeitig erfuellt sind, sonst HOLD.
- **Ausstieg (SELL) einer offenen Position:** Death Cross, MACD-Bear-Crossover, RSI ueberkauft (>= 70) -- mindestens `EXIT_CONFIRMATIONS_REQUIRED` davon (Standard: 2 von 3) muessen gleichzeitig zutreffen, sonst HOLD. Tradeoff: mit 1 (altes Verhalten) reicht jede Bedingung allein und schneidet laufende Aufwaertstrends oft zu frueh ab; mit 2 wird mehr vom Trend mitgenommen, waehrend der Schutz vor echten Abwaertstrends (mehrere Bedingungen treffen dort typischerweise gemeinsam zu) erhalten bleibt.
- Der Bot handelt **long-only** (keine Leerverkaeufe).
- Bei unvollstaendigen/uneindeutigen Signalen wird **keine** Order platziert (HOLD), das wird trotzdem geloggt.

Alle Parameter (SMA/RSI/MACD-Perioden, Timeframe, Intervall) sind ueber `.env` anpassbar.

## Trading-Modus: standard oder fast

Ueber `TRADING_MODE` in `.env` laesst sich zwischen zwei vordefinierten
Parametersaetzen umschalten (Strategie- und Risikologik selbst bleiben
identisch — es aendern sich nur die Zahlenwerte):

| Parameter | `standard` (Default) | `fast` |
|---|---|---|
| `TIMEFRAME` | 15Min | 5Min |
| `CHECK_INTERVAL_MINUTES` | 15 | 5 |
| `SMA_FAST` / `SMA_SLOW` | 50 / 200 | 9 / 21 |
| `RSI_PERIOD`, MACD-Parameter | unveraendert (14 / 12,26,9) | unveraendert |
| `POSITION_SIZE_PCT` | 2.0 | 1.0 |
| `STOP_LOSS_PCT` / `TAKE_PROFIT_PCT` | 2.0 / 4.0 | 1.0 / 2.0 |
| `MAX_DAILY_LOSS_PCT` | 3.0 (hartes Limit) | 3.0 (hartes Limit, **nicht** gelockert) |

Jeder einzelne Wert kann trotzdem explizit in `.env` gesetzt werden — ein
gesetzter Wert gewinnt immer gegen den Modus-Default (siehe `.env.example`).

**Wichtig:** `fast` bedeutet mehr, aber kleinere und kuerzere Trades — nicht
automatisch mehr Gewinn. Kuerzere Zeitrahmen (5Min statt 15Min) und ein
engerer SMA-Crossover (9/21 statt 50/200) reagieren auf mehr Marktrauschen,
erzeugen also mehr Fehlsignale und mehr Ein-/Ausstiege. Engere Stop-Loss-
Abstaende (1.0% statt 2.0%) werden entsprechend haeufiger ausgeloest, und
jeder Trade zahlt (anteilig haeufiger) Spread/Slippage. Die kleinere
Positionsgroesse (1.0% statt 2.0%) kompensiert das kumulierte Risiko durch
mehr gleichzeitige/aufeinanderfolgende Trades, aendert aber nichts an der
grundsaetzlich hoeheren Handelsfrequenz und damit hoeherem operativem Risiko.
Das Tagesverlust-Limit (`MAX_DAILY_LOSS_PCT`) gilt unveraendert in beiden
Modi und wird durch `fast` nicht gelockert.

Beim Start loggt der Bot den aktiven Modus und die Kernparameter, z. B.:

```
Trading mode: FAST | timeframe=5Min SMA=9/21 RSI=14 | position_size=1.0% stop_loss=1.0% take_profit=2.0% max_daily_loss=3.0%
```

## Watchlist: feste Liste oder Nasdaq-100

Standardmaessig nutzt der Bot die feste `WATCHLIST` aus `.env`. Mit
`USE_NASDAQ100=true` scannt er stattdessen die komplette Nasdaq-100-Liste aus
`nasdaq100.py` (WATCHLIST wird in dem Fall ignoriert). Die Liste ist bewusst
statisch (kein Web-Scraping zur Laufzeit) und sollte gelegentlich manuell
gegen eine aktuelle, offizielle Quelle abgeglichen werden, da sich die
Zusammensetzung durch die jaehrliche Reconstitution im Dezember sowie durch
Uebernahmen/Delistings aendert — Details dazu stehen im Docstring der Datei.

### Effizienz bei ~100 Symbolen

Bei aktivem `USE_NASDAQ100` waeren pro Zyklus naiv ~200 einzelne API-Calls
noetig (Bars + Position pro Symbol). Stattdessen:

- **Positionen:** ein einziger `get_all_positions()`-Call statt einem pro Symbol.
- **Kursdaten:** `get_bars_batch()` fasst mehrere Symbole in einer einzigen
  Anfrage zusammen (Anzahl steuerbar ueber `DATA_BATCH_SIZE`, Standard 30) und
  pausiert zwischen den Batches (`DATA_BATCH_PAUSE_SECONDS`), um Alpacas
  Rate-Limits nicht zu sprengen. Da Alpacas `limit`-Parameter bei Multi-Symbol-Requests
  die Gesamtzahl der Bars *ueber alle Symbole* im Request begrenzt (nicht pro
  Symbol), skaliert `get_bars_batch()` den angefragten Limit-Wert intern
  entsprechend der Batch-Groesse hoch und kuerzt danach pro Symbol wieder auf
  die benoetigte Anzahl.
- Damit sinkt ein voller Nasdaq-100-Durchlauf auf ca. 4-7 HTTP-Requests pro
  Zyklus (1x Clock, 1x Account, 1x Positionen, ~3-4x Kursdaten-Batches) und
  bleibt damit weit unter jedem sinnvollen `CHECK_INTERVAL_MINUTES`.

## Pattern-Erkennung (Trendlinien & Chartmuster)

Zusaetzlich zur Indikator-Strategie (SMA/MACD/RSI) gibt es ein **komplett
eigenstaendiges** Modul (`patterns.py`), das automatisch Trendlinien und
einfache Chartmuster aus den Kursdaten berechnet -- quantitativ und
deterministisch, kein manuelles Einzeichnen:

- **Swing-Highs/-Lows:** lokale Hoch-/Tiefpunkte ueber ein Fenster von
  `PATTERN_PIVOT_WINDOW` Kerzen links/rechts (Standard 4).
- **Trendlinien:** lineare Regression durch die juengsten `PATTERN_MIN_TRENDLINE_PIVOTS`
  bis `PATTERN_MAX_TRENDLINE_PIVOTS` Swing-Lows (Support/Aufwaertstrend) bzw.
  Swing-Highs (Resistance/Abwaertstrend). Wird bei jedem Aufruf komplett neu
  aus den aktuell vorliegenden Kerzen berechnet, keine gespeicherte Linie.
- **Signale:** signifikanter Trendlinienbruch (Schlusskurs bricht um mehr als
  `PATTERN_BREAKOUT_THRESHOLD_PCT` % durch die extrapolierte Linie), hoehere
  Tiefs/tiefere Hochs als Trendbestaetigung ohne Bruch, sowie eine einfache
  Double-Top/Bottom-Erkennung und Support-/Resistance-Zonen aus gehaeuften
  Pivots. Jedes Signal hat einen **Konfidenzwert** (0-1) aus Anzahl
  bestaetigender Pivots, Guete der Regression (R²), Winkel der Linie und
  (falls vorhanden) Volumenbestaetigung.

**An-/Ausschalten:** `PATTERN_ENABLED=true|false` in `.env` (Standard: `false`,
also aus -- ohne diese Variable aendert sich am Verhalten des Bots nichts).

**Kombination mit der bestehenden Strategie** (`PATTERN_COMBINE_MODE`):
Das Pattern-Modul **ersetzt** die Indikator-Strategie nicht und kann von sich
aus **keinen** Trade ausloesen -- ist das Indikator-Signal HOLD, bleibt es
HOLD, unabhaengig davon, wie stark das Pattern-Signal ist. Es kann nur ein
bereits vorhandenes BUY/SELL bestaetigen (durchlassen) oder verwerfen
(zurueck auf HOLD):

- `confirm` (Standard): Pattern-Signal muss dem Indikator-Signal in Richtung
  UND Mindest-Konfidenz (`PATTERN_MIN_CONFIDENCE`) zustimmen, sonst HOLD.
- `weighted`: gewichtete Kombination aus Indikator-Richtung (±1) und
  Pattern-Score (`PatternSignal.score`, zwischen -1 und +1), Gewicht des
  Pattern-Anteils ueber `PATTERN_WEIGHT` (0-1). Rein rechnerisch kann ein
  `PATTERN_WEIGHT <= 0.5` die Indikator-Richtung NIE umkehren (der
  Pattern-Score ist auf ±1 begrenzt, das reicht dann nicht aus) -- bei den
  Standardeinstellungen wirkt `weighted` also eher als leichte Bestaetigung
  im Log/in trades.csv, veraendert das Ergebnis gegenueber "kein Pattern-Modul"
  aber selten. Erst mit `PATTERN_WEIGHT > 0.5` kann das Pattern-Signal ein
  Indikator-Signal tatsaechlich auf HOLD zuruecksetzen.

**Wichtig:** Da ein SELL-Signal im `confirm`-Modus ebenfalls die Zustimmung
des Pattern-Moduls braucht, kann eine offene Position bei aktivem
Pattern-Modul laenger offen bleiben, als es der reine Indikator-Exit vorsehen
wuerde -- der Stop-Loss aus der Bracket-Order greift trotzdem immer
unveraendert (siehe Risikomanagement). Vor dem Live-/Paper-Einsatz mit
`PATTERN_ENABLED=true` unbedingt zuerst `backtest.py` nutzen (siehe unten).

**Logging:** eine kompakte Zeile pro tatsaechlich erkanntem Pattern (nicht
pro gescanntem Symbol), z. B.:

```
PATTERN AAPL: BULLISH conf=0.79 (trendline_breakout_up) — Ausbruch ueber Abwaertstrendlinie (4 Hochs, Winkel -16.6°, R²=1.00)
```

## Risikomanagement

- **Positionsgroesse:** `POSITION_SIZE_PCT` % des Account-Equity pro Trade (nach oben durch verfuegbare Buying Power begrenzt).
- **Stop-Loss / Take-Profit:** werden als Alpaca-Bracket-Order (OCO) direkt bei Orderaufgabe gesetzt (`STOP_LOSS_PCT` / `TAKE_PROFIT_PCT`), mit `time_in_force=GTC` (Good Till Canceled) statt `DAY` -- mit `DAY` liefe die Take-Profit-Limit-Order zum Handelsschluss ab, sobald sie nicht gefuellt wurde, und wegen der OCO-Verknuepfung storniert Alpaca dabei automatisch AUCH den Stop-Loss, sodass die Position komplett ungeschuetzt weiterlaeuft (genau das war ein realer Vorfall: PYPL/MRVL liefen dadurch tagelang schutzlos mit 10-15% statt der vorgesehenen ~2% Verlust). GTC ist fuer Bracket-Orders auf Aktien in der regulaeren Handelszeit unterstuetzt; nur bei `extended_hours=True` (nutzt dieser Bot nicht) verlangt Alpaca fuer den Entry `DAY` + Limit-Order, und Crypto unterstuetzt bei Alpaca ueberhaupt keine Bracket-/OCO-Orders (dieser Bot handelt ausschliesslich US-Aktien, betrifft ihn also nicht).
- **Stop-Loss-Sicherheitsnetz:** jeder Bot-Zyklus prueft zusaetzlich fuer jede offene Position, ob tatsaechlich noch eine aktive Stop-Loss-Order existiert (`OrderExecutor.has_active_stop_loss`) -- unabhaengig von der Ursache eines fehlenden Stops. Fehlt einer, wird das als WARNING geloggt, automatisch eine neue Stop-Loss-Order zum konfigurierten `STOP_LOSS_PCT` nachgelegt, und (falls `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` gesetzt sind) sofort per Telegram alarmiert.
- **Tagesverlust-Limit:** sobald der realisierte Tagesverlust `MAX_DAILY_LOSS_PCT` % des Start-Equity des Tages ueberschreitet, werden fuer den Rest des Tages keine neuen Positionen mehr eroeffnet (offene Positionen bleiben durch ihre Bracket-Orders abgesichert).

## Logging

Jede Entscheidung (BUY, SELL, HOLD, HALT, ERROR) wird mit Zeitstempel, Symbol,
Menge, Preis, SL/TP, Order-ID und **Begruendung** (welche Indikatoren was
gezeigt haben) in `trades.csv` (Pfad ueber `TRADE_LOG_PATH` konfigurierbar)
angehaengt — bei 100 Symbolen entsprechend 100 Zeilen pro Zyklus, das ist so
gewollt (vollstaendiges Audit-Log).

Auf der Konsole (Python `logging`) wird das bewusst kompakt gehalten, damit
ein 100-Symbol-Durchlauf nicht zuspammt: einzelne HOLD-Entscheidungen werden
dort **nicht** ausgegeben. Stattdessen:

- **Beim Start** nur die Watchlist-Groesse und -Quelle, nicht jedes einzelne Symbol:
  ```
  Starting bot (paper trading) — watchlist: 99 symbols (Nasdaq-100), interval=15 min
  ```
- **Pro BUY/SELL** sofort eine ausfuehrliche Zeile mit Symbol, Preis und Begruendung
  (BUY gruen, SELL rot eingefaerbt via `colorama`, faellt automatisch auf unformatierten
  Text zurueck falls `colorama` nicht installiert ist):
  ```
  BUY AAPL x12 @ ~172.30 (SL 168.85 / TP 179.19) — Uptrend (SMA50 ... > SMA200 ...), MACD bullish crossover ..., RSI ...
  ```
- **Nach jedem Scan** eine Zusammenfassungszeile statt einer Zeile pro Symbol:
  ```
  Scan complete: 2 BUY, 1 SELL, 95 HOLD, 1 ERROR (duration: 45.3s)
  ```
- **Pro erkanntem Pattern** (nur wenn `PATTERN_ENABLED=true` und tatsaechlich
  ein Trendlinienbruch/-muster gefunden wurde, siehe oben) eine zusaetzliche
  cyanfarbene Zeile.

## Fehlerbehandlung

- API-Fehler (Alpaca down, Rate-Limits, ungueltige Order) werden pro Symbol
  abgefangen, geloggt und der Bot faehrt mit dem naechsten Symbol/Zyklus fort.
- Bei unklaren/widerspruechlichen Signalen wird keine Order ausgeloest (HOLD).
- Ein einzelner API-Ausfall beendet nicht den gesamten Bot — nur der aktuelle
  Zyklus wird uebersprungen, danach folgt der naechste turnusmaessige Versuch.
- **Position schliessen bei offener Bracket-Order:** `close_position()` storniert
  zuerst alle offenen Orders des Symbols (insbesondere die Stop-Loss-/Take-Profit-
  Kindauftraege einer Bracket-Order) und wartet/pollt, bis Alpaca die Stornierung
  bestaetigt, bevor die Position tatsaechlich geschlossen wird — sonst schlaegt
  der Close mit "insufficient qty available for order" fehl, weil die Aktien
  noch durch die offenen Kindauftraege reserviert sind. Schlaegt der Close trotz
  bestaetigter Stornierung wegen eines kurzen Timings-Races bei Alpaca noch
  einmal fehl, wird automatisch mit kurzem Backoff erneut versucht.

## Backtesting

**Vor jedem Einsatz von `PATTERN_ENABLED=true` im Live-/Paper-Betrieb** sollte
`backtest.py` gegen historische Daten laufen, um zu pruefen, ob das
Pattern-Modul die Ergebnisse tatsaechlich verbessert oder verschlechtert.

```bash
python -m trading_bot.backtest --symbol AAPL --days 730
```

- **Datenquelle:** zuerst Alpacas historische Markt-API (wenn gueltige Keys
  in `.env` stehen), sonst automatisch **yfinance** als Fallback (kein
  Alpaca-Account noetig -- `pip install yfinance`, ist in `requirements.txt`
  als optionale Abhaengigkeit vermerkt).
- **Simulation:** spielt Balken fuer Balken **dieselben Funktionen** durch,
  die auch der Live-Bot nutzt (`strategy.generate_signal` +, falls aktiv,
  das Pattern-Modul) -- long-only, eine Position gleichzeitig, Stop-Loss/
  Take-Profit exakt wie die Live-Bracket-Order (`STOP_LOSS_PCT`/`TAKE_PROFIT_PCT`),
  Positionsgroesse gemaess `POSITION_SIZE_PCT` (kein 100 %-des-Kapitals-Fantasieergebnis).
- **Timeframe:** verwendet immer `config.timeframe` (also die aktuelle
  `.env`/`TRADING_MODE`-Konfiguration, z.B. `15Min`) -- **nicht** hart
  codiert auf Tageskerzen. Der yfinance-Fallback mappt das auf das passende
  Yahoo-Intervall (`15Min`->`15m` usw.) und kappt `--days` automatisch auf
  Yahoo's Intraday-Limits (1m ~7 Tage, 5/15/30m ~60 Tage, 60m ~730 Tage,
  1d unbegrenzt), mit einer klaren Log-Zeile, falls gekappt wurde.
- **Output:** Timeframe + Balkenanzahl, Trefferquote, durchschnittlicher
  Gewinn/Verlust pro Trade, Anzahl Trades, Gesamtrendite, Max Drawdown, sowie
  ein **Buy-&-Hold-Vergleich** (Kaufen und Halten mit 100 % Kapital ueber
  denselben Zeitraum) inkl. Differenz in Prozentpunkten -- zeigt, ob die
  Entry/Exit-Logik ueberhaupt in die richtige Richtung tradet. Kein direkter
  Rendite-Vergleich bei gleichem Kapitaleinsatz, da die Strategie nur
  `POSITION_SIZE_PCT` einsetzt, Buy & Hold aber 100 %.
- Ohne `--no-compare` (Standard) laeuft der Backtest automatisch **zweimal**
  -- einmal ohne, einmal mit Pattern-Modul -- und druckt beide Reports
  direkt untereinander zum Vergleich.
- **Nasdaq-100-Batch:** `--use-nasdaq100` testet die komplette Watchlist aus
  `nasdaq100.py` statt eines einzelnen `--symbol` (laeuft dabei immer mit der
  aktuellen `.env`-Konfiguration, wie `--no-compare`). Ein einzelnes
  fehlschlagendes Symbol (fehlende Daten, Rate-Limit) bricht den Lauf nicht
  ab, sondern wird uebersprungen und geloggt. Am Ende: Median/Durchschnitt
  ueber alle erfolgreich getesteten Symbole, aufgeteilt nach Marktregime
  (Buy&Hold-Rendite positiv vs. negativ im Zeitraum) sowie Top-5/Flop-5 nach
  Differenz zu Buy & Hold -- damit laesst sich pruefen, ob ein an
  Einzeltiteln beobachtetes Muster (z.B. "schuetzt gut vor Abwaertstrends,
  verpasst Teile von Aufwaertstrends") sich ueber die ganze Liste bestaetigt.
  Ergebnis pro Symbol zusaetzlich als `nasdaq100_backtest_results.csv`.
  ```bash
  python -m trading_bot.backtest --use-nasdaq100 --days 730 --no-compare
  ```
- **Bekannte Vereinfachung:** das Tagesverlust-Limit (`MAX_DAILY_LOSS_PCT`)
  wird im Backtest nicht simuliert, nur Stop-Loss/Take-Profit und die
  Signal-Exit-Logik.

## Mobile-Dashboard

Ein schreibgeschuetztes Status-Dashboard fuers Handy, bestehend aus zwei
unabhaengigen Teilen: einem kleinen API-Server, der neben dem Bot laeuft
(z. B. auf einem Raspberry Pi), und einer statischen Seite ohne jeglichen
Server-Code oder Keys, die du auf GitHub Pages hostest.

### 1. `api_server.py` auf dem Pi (neben dem Bot)

Liest dieselben Alpaca-Keys aus `trading_bot/.env` -- keine zweite
Schluessel-Verwaltung. Stellt **nur** einen lesenden Endpoint bereit
(`GET /api/status`: Kontostand, Tages-P&L, offene Positionen, die letzten
10 BUY/SELL-Trades aus `trades.csv`, Paper/Live-Flag), keine Order-Routen.

```bash
# einmalig, im bereits aktivierten venv (siehe Setup oben):
pip install flask flask-cors   # oder: pip install -r trading_bot/requirements.txt

# Start (vom Projekt-Root aus, wie main.py):
python -m trading_bot.api_server
```

Beim allerersten Start wird automatisch ein zufaelliges Zugriffs-Token
erzeugt und in `trading_bot/dashboard_token.txt` gespeichert (Dateirechte
nur fuer den Owner, nicht eingecheckt) -- das Token wird einmal in der
Konsole ausgegeben und muss anschliessend nur einmalig ins Dashboard
eingetragen werden (siehe unten). Jeder Request an `/api/status` ohne
passenden Header `X-Dashboard-Token` bekommt `401 Unauthorized`.

**HTTPS/TLS:** Der Server laeuft ueber HTTPS mit dem per Tailscale
ausgestellten Zertifikat -- notwendig, weil die Dashboard-Seite auf
GitHub Pages per HTTPS ausgeliefert wird und Browser einer HTTPS-Seite
nicht erlauben, Daten von einer unverschluesselten HTTP-Adresse
nachzuladen ("Mixed Content"). Einmalig auf dem Pi, **im Projekt-Root**
(nicht in `trading_bot/`):

```bash
sudo tailscale cert tradingbot.tailed8a6b.ts.net
```

Das legt `tradingbot.tailed8a6b.ts.net.crt` und `.key` im aktuellen
Verzeichnis ab -- `api_server.py` erwartet beide Dateien im Projekt-Root
und loest den Pfad dorthin auf, egal von wo aus `python -m
trading_bot.api_server` gestartet wird. Fehlt eine der beiden Dateien
(z. B. Zertifikat abgelaufen), bricht der Server beim Start mit einer
klaren Fehlermeldung ab, die genau diesen Befehl noch einmal nennt,
statt mit einem unklaren Traceback abzustuerzen.

**Dauerhaft laufen lassen (tmux):**

```bash
tmux new -s dashboard-api
python -m trading_bot.api_server
# Session verlassen, Prozess laeuft weiter: Strg+B, dann D
# Spaeter wieder reinschauen: tmux attach -t dashboard-api
```

**Fernzugriff vom Handy:** Der Server bindet auf `0.0.0.0:5000`, ist also im
lokalen Netz erreichbar -- fuer Zugriff von unterwegs empfiehlt sich
[Tailscale](https://tailscale.com) auf dem Pi UND dem Handy (kostenlos fuer
den Privatgebrauch): einfach installieren, einloggen, dann ist der Pi aus
dem Tailscale-Netz erreichbar, ganz ohne Portfreigabe im Router.

Als Server-Adresse im Dashboard **den Tailscale-Hostnamen verwenden, nicht
die numerische Tailscale-IP**: `https://tradingbot.tailed8a6b.ts.net:5000`.
Das Zertifikat ist auf genau diesen Hostnamen ausgestellt -- ueber die IP
aufgerufen wuerde der Browser eine Zertifikatswarnung zeigen (Hostname
stimmt nicht ueberein). Da es sich um ein echtes, von Tailscale ausgestelltes
Zertifikat handelt (keine Selbstsignierung), zeigt Safari auf dem iPhone bei
korrekter Adresse keine Warnung.

> Der eingebaute Flask-Dev-Server ("this is a development server...") reicht
> hier voellig aus -- das Dashboard ist ein privates Ein-Personen-Tool hinter
> Tailscale, kein oeffentlich erreichbarer Dienst.

### 2. `index.html` (Projekt-Root) auf GitHub Pages

Komplett statisch, kein Server-Code, keine Keys im Code -- API-Adresse und
Token werden erst zur Laufzeit im Browser des Nutzers eingegeben und nur
lokal in `localStorage` auf dem jeweiligen Geraet gespeichert.

**Hosten:** Die Datei liegt im Projekt-Root (`index.html`) und ersetzt dort
die vorherige Seite -- unter **Settings → Pages** die Quelle auf den
`main`-Branch (Root) stellen, danach unter
`https://<username>.github.io/<repo>/` erreichbar.

**Einrichten:**
1. Seite im Handy-Browser oeffnen -- beim allerersten Aufruf oeffnet sich
   automatisch das Einstellungen-Modal (Zahnrad-Icon oben rechts oeffnet es
   auch spaeter wieder).
2. Server-Adresse eintragen (Tailscale-Hostname des Pi + Port, z. B.
   `https://tradingbot.tailed8a6b.ts.net:5000`) und das Token aus
   `dashboard_token.txt`.
3. Speichern -- das Dashboard aktualisiert sich danach automatisch alle 30
   Sekunden. Ist der Pi nicht erreichbar oder das Token falsch, wird das
   klar als Banner angezeigt (keine leere Seite).
4. **Zum Home-Bildschirm hinzufuegen (iPhone):** Seite in Safari oeffnen,
   Teilen-Icon → "Zum Home-Bildschirm" -- startet dann wie eine eigene App,
   ohne Safari-Adressleiste.

## 24/7-Absicherung (Hardware-Watchdog, Auto-Restart, Health-Checks, ...)

Fuer unbeaufsichtigten Dauerbetrieb (z.B. auf einem Raspberry Pi) siehe
[`../deploy/README.md`](../deploy/README.md): Hardware-Watchdog, systemd-
Services mit Auto-Restart und Speicherlimit, ein Health-Check-Cronjob mit
automatischer Selbstheilung, Log-Rotation, SD-Karten-Schonung, woechentlicher
Wartungs-Reboot und Telegram-Benachrichtigungen bei Problemen.

## Naechste Schritte / Anpassungen

- Neue Strategie? `strategy.generate_signal` austauschen/erweitern.
- Anderes Sizing (z. B. ATR-basiert)? Nur `risk_manager.py` anfassen.
- Anderer Broker/Datenanbieter? Nur `data_feed.py` / `order_executor.py` ersetzen, die Schnittstellen (`get_bars`, `submit_bracket_buy`, ...) bleiben gleich.
- Andere/mehr Chartmuster? Nur `patterns.py` anfassen (komplett eigenstaendig, kein Bezug zu Config/Alpaca).
