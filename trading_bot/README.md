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
| `bot.py` | Haupt-Loop: Marktzeiten pruefen, Watchlist durchgehen, Fehlerbehandlung pro Symbol. |
| `main.py` | Einstiegspunkt (`python -m trading_bot.main`). |

Jedes Modul laesst sich unabhaengig austauschen — z. B. eine andere Strategie
in `strategy.py`, ein anderes Sizing-Modell in `risk_manager.py`, oder ein
anderer Broker in `data_feed.py`/`order_executor.py`.

## Setup

```bash
cd trading_bot
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
```

Trage in `.env` deine **Paper-Trading**-API-Keys ein (https://app.alpaca.markets,
"Paper Trading" Bereich). `ALPACA_PAPER=true` sorgt dafuer, dass ausschliesslich
der Paper-Endpunkt (`paper-api.alpaca.markets`) verwendet wird. Keys stehen
ausschliesslich in `.env` (nicht eingecheckt, siehe `.gitignore`) — niemals im Code.

## Start

```bash
python -m trading_bot.main
```

Der Bot laeuft in einer Endlosschleife, prueft alle `CHECK_INTERVAL_MINUTES`
Minuten die Watchlist, verlangt aber, dass die Boerse laut Alpaca-Clock
geoeffnet ist. Mit `Strg+C` sauber beenden.

## Strategie (Standardparameter)

- **Trendfilter:** SMA 50 vs. SMA 200 (Golden Cross = Aufwaertstrend).
- **Einstiegstrigger:** MACD(12,26,9)-Linie kreuzt die Signallinie von unten (bullisches Crossover).
- **Bestaetigung:** RSI(14) zwischen 30 und 70 (kein ueberkaufter/ueberverkaufter Extremzustand).
- **Einstieg (BUY):** nur wenn alle drei Bedingungen gleichzeitig erfuellt sind, sonst HOLD.
- **Ausstieg (SELL) einer offenen Position:** Death Cross, MACD-Bear-Crossover **oder** RSI ueberkauft (>= 70) — jede dieser Bedingungen allein reicht.
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

## Risikomanagement

- **Positionsgroesse:** `POSITION_SIZE_PCT` % des Account-Equity pro Trade (nach oben durch verfuegbare Buying Power begrenzt).
- **Stop-Loss / Take-Profit:** werden als Alpaca-Bracket-Order (OCO) direkt bei Orderaufgabe gesetzt (`STOP_LOSS_PCT` / `TAKE_PROFIT_PCT`).
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

## Naechste Schritte / Anpassungen

- Neue Strategie? `strategy.generate_signal` austauschen/erweitern.
- Anderes Sizing (z. B. ATR-basiert)? Nur `risk_manager.py` anfassen.
- Anderer Broker/Datenanbieter? Nur `data_feed.py` / `order_executor.py` ersetzen, die Schnittstellen (`get_bars`, `submit_bracket_buy`, ...) bleiben gleich.
