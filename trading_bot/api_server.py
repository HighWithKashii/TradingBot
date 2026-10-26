"""Read-only Status-API fuer das Mobile-Dashboard.

Laeuft NEBEN dem Trading-Bot (gleicher Rechner, z. B. Raspberry Pi), liest
dieselben Alpaca-Keys aus trading_bot/.env ueber die bestehende Config/
OrderExecutor-Logik (keine eigene Alpaca-Anbindung, kein doppelter Code) und
stellt zwei Endpoints bereit, die die statische index.html (GitHub Pages)
per fetch() abfragt: `/api/status` (Account/Positionen/letzte Trades) und
`/api/equity-history` (Kontostand-Verlauf fuer den Chart, siehe
build_equity_history_payload).

Nur lesend: es werden keine Order-Endpunkte exponiert. Zugriff ausschliesslich
mit gueltigem Header `X-Dashboard-Token`, Token wird beim ersten Start
generiert und in dashboard_token.txt (neben dieser Datei, nicht eingecheckt)
abgelegt.

Laeuft ueber HTTPS mit dem per `sudo tailscale cert` erzeugten
Tailscale-TLS-Zertifikat (Dateien liegen im Projekt-Root, nicht im
trading_bot-Unterordner).

Start (immer vom Projekt-Root aus, wie main.py):
    python -m trading_bot.api_server
"""

from __future__ import annotations

import csv
import logging
import secrets
import stat
import sys
import time
from collections import deque
from datetime import date, datetime, timezone
from functools import wraps
from pathlib import Path
from typing import Callable
from zoneinfo import ZoneInfo

import requests
from flask import Flask, jsonify, request
from flask_cors import CORS

from trading_bot.config import Config, load_config
from trading_bot.order_executor import OrderExecutionError, OrderExecutor

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("dashboard_api")

TOKEN_PATH = Path(__file__).resolve().parent / "dashboard_token.txt"
MAX_RECENT_TRADES = 10

# Kontostand-Verlauf (siehe build_equity_history_payload). Alpaca kennt kein
# period="all" -- 20A (20 Jahre) ist grosszuegig mehr als jedes Paper-/
# Live-Konto jemals alt sein kann, Alpaca schneidet die Antwort automatisch
# auf die tatsaechlich vorhandene Historie zu (kein Padding mit leeren Tagen
# davor, siehe Alpaca-Doku: taegliche Aufloesung hat kein Limit, Daten gibt
# es ab Account-Erstellung).
EQUITY_HISTORY_PERIODS: dict[str, str] = {"1w": "1W", "1m": "1M", "3m": "3M", "all": "20A"}
EQUITY_HISTORY_CACHE_SECONDS = 300.0
BERLIN_TZ = ZoneInfo("Europe/Berlin")

# Diese Datei liegt in trading_bot/, das Projekt-Root ist eine Ebene hoeher --
# die Zertifikatsdateien liegen im Root, nicht im trading_bot-Unterordner.
# Ueber Path(__file__) aufgeloest, damit das unabhaengig vom aktuellen
# Arbeitsverzeichnis funktioniert (genau wie main.py per `-m` gestartet).
PROJECT_ROOT = Path(__file__).resolve().parent.parent
TAILSCALE_HOSTNAME = "tradingbot.tailed8a6b.ts.net"
TLS_CERT_PATH = PROJECT_ROOT / f"{TAILSCALE_HOSTNAME}.crt"
TLS_KEY_PATH = PROJECT_ROOT / f"{TAILSCALE_HOSTNAME}.key"


def _load_or_create_token() -> str:
    """Beim allerersten Start wird ein zufaelliges Token generiert und
    dauerhaft in dashboard_token.txt gespeichert (Dateirechte auf "nur
    Owner darf lesen/schreiben" beschraenkt) -- bei jedem weiteren Start
    wird dasselbe Token wiederverwendet, damit sich das Dashboard nicht
    nach jedem Neustart neu konfigurieren muss.
    """
    if TOKEN_PATH.exists():
        return TOKEN_PATH.read_text(encoding="utf-8").strip()

    token = secrets.token_urlsafe(32)
    TOKEN_PATH.write_text(token, encoding="utf-8")
    TOKEN_PATH.chmod(stat.S_IRUSR | stat.S_IWUSR)  # 0600 -- nur der Owner
    logger.info("Neues Dashboard-Token erzeugt und in %s gespeichert.", TOKEN_PATH)
    logger.info("Dashboard-Token (einmalig in die Einstellungen der Dashboard-Seite eintragen): %s", token)
    return token


def _resolve_ssl_context() -> tuple[str, str]:
    """Prueft, dass die Tailscale-TLS-Zertifikatsdateien im Projekt-Root
    vorhanden sind, und gibt ihre Pfade als (cert, key)-Tupel fuer
    app.run(ssl_context=...) zurueck. Bricht mit einer klaren Fehlermeldung
    ab statt mit einem unklaren Traceback, falls eine Datei fehlt.
    """
    missing = [p for p in (TLS_CERT_PATH, TLS_KEY_PATH) if not p.exists()]
    if missing:
        logger.error(
            "TLS-Zertifikat(e) nicht gefunden: %s\n"
            "Erwartet werden '%s' und '%s' im Projekt-Root (%s), nicht im "
            "trading_bot-Unterordner.\n"
            "Falls die Tailscale-Zertifikate fehlen oder abgelaufen sind, auf "
            "dem Pi erneut ausfuehren: sudo tailscale cert %s",
            ", ".join(str(p) for p in missing),
            TLS_CERT_PATH.name,
            TLS_KEY_PATH.name,
            PROJECT_ROOT,
            TAILSCALE_HOSTNAME,
        )
        sys.exit(1)

    return (str(TLS_CERT_PATH), str(TLS_KEY_PATH))


def _require_token(token: str) -> Callable:
    """Decorator-Fabrik statt eines globalen Tokens -- macht create_app()
    unabhaengig von Modul-Globals und damit einfach mit einem Fake-Token
    testbar.
    """

    def decorator(view: Callable) -> Callable:
        @wraps(view)
        def wrapped(*args, **kwargs):
            if request.headers.get("X-Dashboard-Token") != token:
                return jsonify({"error": "unauthorized"}), 401
            return view(*args, **kwargs)

        return wrapped

    return decorator


def _read_recent_trades(path: str, limit: int = MAX_RECENT_TRADES) -> list[dict]:
    """Liest die letzten `limit` BUY/SELL-Zeilen aus trades.csv (HOLD/HALT/
    ERROR-Zeilen zaehlen nicht als "Trade"), neueste zuerst. Nutzt eine
    begrenzte deque statt die ganze Datei in eine Liste einzulesen, damit
    das auch bei einer ueber Monate gewachsenen CSV schnell bleibt.
    """
    csv_path = Path(path)
    if not csv_path.exists():
        return []

    recent: deque[dict] = deque(maxlen=limit)
    with csv_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("action") not in ("BUY", "SELL"):
                continue
            try:
                recent.append(
                    {
                        "timestamp": row["timestamp"],
                        "symbol": row["symbol"],
                        "action": row["action"],
                        "qty": int(float(row["qty"])),
                        "price": float(row["price"]),
                        "reason": row["reason"],
                    }
                )
            except (KeyError, ValueError):
                logger.warning("Ueberspringe unlesbare Zeile in %s: %r", path, row)

    return list(reversed(recent))  # neueste zuerst


def build_status_payload(executor: OrderExecutor, config: Config) -> dict:
    """Baut die komplette /api/status-Antwort. Von der Flask-Schicht
    getrennt, damit sich die eigentliche Logik ohne HTTP/Token-Kram mit
    einem Fake-Executor testen laesst.
    """
    account = executor.get_account()
    positions = executor.get_all_positions()

    equity = float(account.equity)
    last_equity = float(account.last_equity)
    day_pl_dollar = equity - last_equity
    day_pl_percent = (day_pl_dollar / last_equity * 100) if last_equity > 0 else 0.0

    positions_payload = [
        {
            "symbol": symbol,
            "qty": float(position.qty),
            "avg_entry_price": float(position.avg_entry_price),
            "current_price": float(position.current_price),
            "unrealized_pl": float(position.unrealized_pl),
            "unrealized_pl_percent": float(position.unrealized_plpc) * 100,
        }
        for symbol, position in positions.items()
    ]

    return {
        "mode": "paper" if config.paper else "live",
        "account": {
            "equity": equity,
            "cash": float(account.cash),
            "buying_power": float(account.buying_power),
            "day_pl_dollar": day_pl_dollar,
            "day_pl_percent": day_pl_percent,
        },
        "positions": positions_payload,
        "recent_trades": _read_recent_trades(config.trade_log_path),
        "server_time": datetime.now(timezone.utc).isoformat(),
    }


def _extract_equity_points(raw: dict) -> tuple[list[dict], float | None]:
    """Wandelt die rohe Alpaca-Portfolio-History-Antwort (parallele Listen
    `timestamp`/`equity`, siehe OrderExecutor.get_portfolio_history) in eine
    saubere, chronologisch sortierte Liste von Tagespunkten um.

    Verteidigt sich gegen genau die Eigenheiten, die Alpaca fuer dieses
    Endpoint bekannt hat:
    - `None`-Werte in `timestamp` oder `equity` (laut Beobachtung gelegentlich
      vorhanden) -- ein solcher Index wird komplett uebersprungen, nicht als
      0 oder NaN eingetragen, sonst gaebe es einen falschen Ausschlag im
      Chart.
    - Tage ohne Handel (Wochenende/Feiertag) liefert Alpaca schlicht gar
      nicht erst zurueck -- es muss hier nichts extra gefiltert werden, die
      Liste enthaelt dadurch automatisch nur echte Handelstage, keine
      kuenstlichen Spruenge auf der x-Achse.
    - Timestamps sind Unix-Sekunden in UTC; fuer die Anzeige wird daraus das
      Kalenderdatum in Europe/Berlin gebildet (nicht einfach das UTC-Datum --
      wuerde bei einem spaeten UTC-Zeitstempel sonst einen Tag zu frueh
      anzeigen).

    Gibt (points, base_value) zurueck -- `base_value` faellt auf den ersten
    gueltigen Equity-Wert zurueck, falls Alpaca keinen mitliefert (ebenfalls
    `Optional` im Response-Schema).
    """
    timestamps = raw.get("timestamp") or []
    equities = raw.get("equity") or []

    points: list[dict] = []
    for ts, equity in zip(timestamps, equities):
        if ts is None or equity is None:
            continue
        try:
            ts_int = int(ts)
            equity_float = float(equity)
        except (TypeError, ValueError):
            continue
        local_date = datetime.fromtimestamp(ts_int, tz=timezone.utc).astimezone(BERLIN_TZ).date()
        points.append({"timestamp": ts_int, "date": local_date.isoformat(), "equity": equity_float})

    points.sort(key=lambda p: p["timestamp"])

    base_value = raw.get("base_value")
    try:
        base_value = float(base_value) if base_value is not None else None
    except (TypeError, ValueError):
        base_value = None
    if base_value is None and points:
        base_value = points[0]["equity"]

    return points, base_value


def _compute_equity_stats(points: list[dict], base_value: float | None) -> dict:
    """Kennzahlenzeile fuers Dashboard: aktueller Kontostand, P&L im Zeitraum
    ($ und %), bester/schlechtester Tag, maximaler Drawdown. Reine,
    Flask-freie Funktion auf der schon bereinigten Punkteliste -- billige
    O(n)-Schleifen ueber hoechstens ein paar tausend Tagespunkte, selbst auf
    einem Pi Zero kein Thema.
    """
    if not points:
        return {
            "current_equity": None,
            "base_value": base_value,
            "period_pl_dollar": None,
            "period_pl_percent": None,
            "best_day": None,
            "worst_day": None,
            "max_drawdown_dollar": None,
            "max_drawdown_percent": None,
        }

    current_equity = points[-1]["equity"]
    period_pl_dollar = (current_equity - base_value) if base_value else None
    period_pl_percent = (period_pl_dollar / base_value * 100) if base_value and period_pl_dollar is not None else None

    best_day = None
    worst_day = None
    peak = points[0]["equity"]
    max_drawdown_dollar = 0.0
    max_drawdown_percent = 0.0

    for prev, curr in zip(points, points[1:]):
        change_dollar = curr["equity"] - prev["equity"]
        change_percent = (change_dollar / prev["equity"] * 100) if prev["equity"] else 0.0
        day = {"date": curr["date"], "change_dollar": change_dollar, "change_percent": change_percent}
        if best_day is None or change_dollar > best_day["change_dollar"]:
            best_day = day
        if worst_day is None or change_dollar < worst_day["change_dollar"]:
            worst_day = day

        peak = max(peak, curr["equity"])
        drawdown_dollar = curr["equity"] - peak
        drawdown_percent = (drawdown_dollar / peak * 100) if peak else 0.0
        if drawdown_dollar < max_drawdown_dollar:
            max_drawdown_dollar = drawdown_dollar
            max_drawdown_percent = drawdown_percent

    return {
        "current_equity": current_equity,
        "base_value": base_value,
        "period_pl_dollar": period_pl_dollar,
        "period_pl_percent": period_pl_percent,
        "best_day": best_day,
        "worst_day": worst_day,
        "max_drawdown_dollar": max_drawdown_dollar,
        "max_drawdown_percent": max_drawdown_percent,
    }


def build_equity_history_payload(executor: OrderExecutor, period_key: str) -> dict:
    """Baut die komplette /api/equity-history-Antwort fuer einen der
    erlaubten Zeitraeume (siehe EQUITY_HISTORY_PERIODS). Von der Flask-
    Schicht und vom Cache getrennt, damit sich die Aufbereitung ohne
    HTTP/Token/Cache-Kram mit einem Fake-Executor testen laesst.
    """
    alpaca_period = EQUITY_HISTORY_PERIODS[period_key]
    raw = executor.get_portfolio_history(alpaca_period, timeframe="1D")
    points, base_value = _extract_equity_points(raw)
    stats = _compute_equity_stats(points, base_value)
    return {"period": period_key, "points": points, **stats}


# Einfache In-Memory-TTL-Cache (siehe EQUITY_HISTORY_CACHE_SECONDS) pro
# Zeitraum -- der Flask-Dev-Server hier laeuft einzeln (kein threaded=True,
# siehe main()), Requests werden also sequentiell abgearbeitet, ein Lock ist
# dafuer nicht noetig. Zweck: mehrfaches Neuladen der Dashboard-Seite oder
# ein Wechsel zwischen den vier Zeitraum-Buttons soll nicht bei jedem Klick
# erneut Alpaca treffen (Rate-Limit-Schonung UND weniger Arbeit fuer den
# Pi Zero).
_equity_history_cache: dict[str, tuple[float, dict]] = {}


def _get_equity_history_cached(executor: OrderExecutor, period_key: str) -> dict:
    now = time.monotonic()
    cached = _equity_history_cache.get(period_key)
    if cached is not None and (now - cached[0]) < EQUITY_HISTORY_CACHE_SECONDS:
        return cached[1]

    payload = build_equity_history_payload(executor, period_key)
    _equity_history_cache[period_key] = (now, payload)
    return payload


def create_app(executor: OrderExecutor, config: Config, token: str) -> Flask:
    app = Flask(__name__)
    CORS(app)  # index.html laeuft auf einer anderen Origin (GitHub Pages) --
    # die eigentliche Absicherung ist das Token, nicht die CORS-Origin.

    require_token = _require_token(token)

    @app.route("/")
    def index():
        return jsonify({"service": "trading-bot-dashboard-api", "status": "running"})

    @app.route("/api/status")
    @require_token
    def status():
        try:
            payload = build_status_payload(executor, config)
        except OrderExecutionError as exc:
            logger.error("Alpaca-Abfrage fehlgeschlagen: %s", exc)
            return jsonify({"error": f"Alpaca nicht erreichbar: {exc}"}), 502
        return jsonify(payload)

    @app.route("/api/equity-history")
    @require_token
    def equity_history():
        period_key = request.args.get("period", "all").strip().lower()
        if period_key not in EQUITY_HISTORY_PERIODS:
            return (
                jsonify({"error": f"Ungueltiger Zeitraum '{period_key}', erlaubt: {', '.join(EQUITY_HISTORY_PERIODS)}"}),
                400,
            )
        try:
            payload = _get_equity_history_cached(executor, period_key)
        except OrderExecutionError as exc:
            logger.error("Alpaca-Portfolio-History-Abfrage fehlgeschlagen: %s", exc)
            return jsonify({"error": f"Alpaca nicht erreichbar: {exc}"}), 502
        except requests.exceptions.RequestException as exc:
            # Dasselbe Timeout, das OrderExecutor._client fuer JEDEN Alpaca-
            # Call erzwingt (siehe order_executor.apply_default_request_timeout)
            # -- hier separat behandelt, weil requests.exceptions.Timeout keine
            # OrderExecutionError ist (siehe bot.run_safety_check_once fuer
            # denselben Fall).
            logger.error("Timeout/Netzwerkfehler bei Alpaca-Portfolio-History: %s", exc)
            return jsonify({"error": f"Alpaca nicht erreichbar (Timeout): {exc}"}), 502
        return jsonify(payload)

    return app


def main() -> None:
    try:
        config = load_config()
    except ValueError as exc:
        logger.error("Konfigurationsfehler: %s", exc)
        sys.exit(1)

    ssl_context = _resolve_ssl_context()
    token = _load_or_create_token()
    executor = OrderExecutor(config)
    app = create_app(executor, config, token)

    logger.info("Dashboard-API startet auf https://0.0.0.0:5000 (%s trading)", "paper" if config.paper else "LIVE")
    app.run(host="0.0.0.0", port=5000, debug=False, ssl_context=ssl_context)


if __name__ == "__main__":
    main()
