"""Read-only Status-API fuer das Mobile-Dashboard.

Laeuft NEBEN dem Trading-Bot (gleicher Rechner, z. B. Raspberry Pi), liest
dieselben Alpaca-Keys aus trading_bot/.env ueber die bestehende Config/
OrderExecutor-Logik (keine eigene Alpaca-Anbindung, kein doppelter Code) und
stellt einen einzigen Endpoint bereit, den die statische index.html (GitHub
Pages) per fetch() abfragt.

Nur lesend: es werden keine Order-Endpunkte exponiert. Zugriff ausschliesslich
mit gueltigem Header `X-Dashboard-Token`, Token wird beim ersten Start
generiert und in dashboard_token.txt (neben dieser Datei, nicht eingecheckt)
abgelegt.

Start (immer vom Projekt-Root aus, wie main.py):
    python -m trading_bot.api_server
"""

from __future__ import annotations

import csv
import logging
import secrets
import stat
import sys
from collections import deque
from datetime import datetime, timezone
from functools import wraps
from pathlib import Path
from typing import Callable

from flask import Flask, jsonify, request
from flask_cors import CORS

from trading_bot.config import Config, load_config
from trading_bot.order_executor import OrderExecutionError, OrderExecutor

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("dashboard_api")

TOKEN_PATH = Path(__file__).resolve().parent / "dashboard_token.txt"
MAX_RECENT_TRADES = 10


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

    return app


def main() -> None:
    try:
        config = load_config()
    except ValueError as exc:
        logger.error("Konfigurationsfehler: %s", exc)
        sys.exit(1)

    token = _load_or_create_token()
    executor = OrderExecutor(config)
    app = create_app(executor, config, token)

    logger.info("Dashboard-API startet auf http://0.0.0.0:5000 (%s trading)", "paper" if config.paper else "LIVE")
    app.run(host="0.0.0.0", port=5000, debug=False)


if __name__ == "__main__":
    main()
