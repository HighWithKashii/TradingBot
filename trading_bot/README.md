# Alpaca Trading Bot

Vollautomatischer, modularer Trading-Bot fuer Alpaca (Paper-Trading zuerst).

> **Disclaimer:** Dies ist keine Finanzberatung. Nutze ausschliesslich das
> Paper-Trading-Konto zum Testen, bevor du (falls ueberhaupt) live handelst.
> Handel mit Wertpapieren ist mit Verlustrisiko verbunden — auch mit diesem Bot.

## Module

| Datei | Verantwortlichkeit |
|---|---|
| `config.py` | Laedt alle Parameter aus `.env` (Keys, Watchlist, Strategie- und Risikoparameter). |
| `indicators.py` | Reine SMA/EMA/RSI/MACD-Berechnung (pandas, keine externen TA-Libs). |
| `strategy.py` | Kombiniert Trendfilter (SMA-Crossover), MACD-Crossover und RSI zu BUY/SELL/HOLD inkl. Begruendung. |
| `risk_manager.py` | Positionsgroesse (% des Kapitals), Stop-Loss/Take-Profit-Preise, Tagesverlust-Limit. |
| `data_feed.py` | Alpaca Marktdaten (historische Bars, Market Clock). |
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

## Risikomanagement

- **Positionsgroesse:** `POSITION_SIZE_PCT` % des Account-Equity pro Trade (nach oben durch verfuegbare Buying Power begrenzt).
- **Stop-Loss / Take-Profit:** werden als Alpaca-Bracket-Order (OCO) direkt bei Orderaufgabe gesetzt (`STOP_LOSS_PCT` / `TAKE_PROFIT_PCT`).
- **Tagesverlust-Limit:** sobald der realisierte Tagesverlust `MAX_DAILY_LOSS_PCT` % des Start-Equity des Tages ueberschreitet, werden fuer den Rest des Tages keine neuen Positionen mehr eroeffnet (offene Positionen bleiben durch ihre Bracket-Orders abgesichert).

## Logging

Jede Entscheidung (BUY, SELL, HOLD, HALT, ERROR) wird mit Zeitstempel, Symbol,
Menge, Preis, SL/TP, Order-ID und **Begruendung** (welche Indikatoren was
gezeigt haben) in `trades.csv` (Pfad ueber `TRADE_LOG_PATH` konfigurierbar)
angehaengt. Fehler/Systemmeldungen laufen zusaetzlich ueber Pythons `logging`
auf der Konsole.

## Fehlerbehandlung

- API-Fehler (Alpaca down, Rate-Limits, ungueltige Order) werden pro Symbol
  abgefangen, geloggt und der Bot faehrt mit dem naechsten Symbol/Zyklus fort.
- Bei unklaren/widerspruechlichen Signalen wird keine Order ausgeloest (HOLD).
- Ein einzelner API-Ausfall beendet nicht den gesamten Bot — nur der aktuelle
  Zyklus wird uebersprungen, danach folgt der naechste turnusmaessige Versuch.

## Naechste Schritte / Anpassungen

- Neue Strategie? `strategy.generate_signal` austauschen/erweitern.
- Anderes Sizing (z. B. ATR-basiert)? Nur `risk_manager.py` anfassen.
- Anderer Broker/Datenanbieter? Nur `data_feed.py` / `order_executor.py` ersetzen, die Schnittstellen (`get_bars`, `submit_bracket_buy`, ...) bleiben gleich.
