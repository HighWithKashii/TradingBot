"""Sofortige Telegram-Benachrichtigung bei fehlgeschlagenen Trades.

Getrennt von deploy/scripts/notify.sh (das ist die Bash-Variante fuer den
5-Minuten-Health-Check bzw. komplette Prozessabstuerze). Dieses Modul meldet
stattdessen einzelne fehlgeschlagene Order-Versuche, sofort, direkt aus dem
laufenden Bot-Prozess heraus -- unabhaengig davon, ob der Bot dabei abstuerzt
oder einfach weiterlaeuft.

Nutzt bewusst nur die Python-Standardbibliothek (urllib) statt "requests",
um diesem Fehler-Meldepfad keine zusaetzliche Abhaengigkeit aufzubuerden.
"""

from __future__ import annotations

import json
import logging
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from trading_bot.config import Config

logger = logging.getLogger(__name__)

_TELEGRAM_API_URL = "https://api.telegram.org/bot{token}/sendMessage"
_TIMEOUT_SECONDS = 5.0


def send_telegram_message(config: Config, message: str) -> bool:
    """Verschickt eine Telegram-Nachricht ueber die Bot-API.

    Gibt True/False fuer Erfolg zurueck und wirft NIEMALS -- ein
    nicht erreichbares Telegram (Netzwerk, falscher Token, Rate-Limit
    von Telegrams Seite) darf den Bot niemals zum Absturz bringen.
    """
    if not config.telegram_bot_token or not config.telegram_chat_id:
        logger.debug("Telegram-Benachrichtigung uebersprungen: kein Token/Chat-ID in .env gesetzt.")
        return False

    url = _TELEGRAM_API_URL.format(token=config.telegram_bot_token)
    data = urllib.parse.urlencode({"chat_id": config.telegram_chat_id, "text": message}).encode("utf-8")
    request = urllib.request.Request(url, data=data, method="POST")

    try:
        with urllib.request.urlopen(request, timeout=_TIMEOUT_SECONDS) as response:
            if response.status == 200:
                return True
            logger.warning("Telegram-API antwortete mit Status %s", response.status)
            return False
    except urllib.error.HTTPError as exc:
        logger.warning("Telegram-API-Fehler (HTTP %s): %s", exc.code, exc.read().decode("utf-8", "replace"))
        return False
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        logger.warning("Telegram nicht erreichbar, Nachricht konnte nicht gesendet werden: %s", exc)
        return False


def extract_alpaca_reason(exc: BaseException) -> str:
    """Zieht die eigentliche, saubere Fehlermeldung aus einer (evtl. gewrappten)
    Alpaca-APIError -- z.B. "insufficient buying power" statt dem rohen
    JSON-Fehlerkoerper oder einem "Failed to submit ... for AAPL: ..."-Praefix.
    """
    cause = exc.__cause__ if exc.__cause__ is not None else exc
    message = getattr(cause, "message", None)
    if message is None:
        try:
            message = json.loads(str(cause)).get("message")
        except (json.JSONDecodeError, AttributeError):
            message = None
    if message:
        return str(message)
    return str(cause)


class TradeFailureNotifier:
    """Meldet fehlgeschlagene Order-Versuche per Telegram, mit Drosselung.

    Drosselung ist pro "Order-Art" (z.B. "AAPL Buy Order", "MSFT Sell Order")
    -- innerhalb von throttle_seconds nach der letzten gesendeten Nachricht
    einer Art wird eine erneute Meldung derselben Art unterdrueckt und nur
    gezaehlt. Die naechste tatsaechlich gesendete Nachricht dieser Art fasst
    die zwischenzeitlich unterdrueckten Fehlschlaege kurz zusammen. So wird
    aus z.B. 50 Fehlschlagen bei einem laengeren Alpaca-Ausfall trotzdem nur
    eine Nachricht alle throttle_seconds statt einer Flut von Nachrichten.
    """

    def __init__(self, config: Config, throttle_seconds: float = 600.0) -> None:
        self._config = config
        self._throttle_seconds = throttle_seconds
        self._lock = threading.Lock()
        self._last_sent_at: dict[str, float] = {}
        self._suppressed_count: dict[str, int] = {}

    def notify_order_failure(self, symbol: str, order_kind: str, exc: BaseException) -> None:
        """order_kind z.B. "Buy Order", "Sell Order", "Bracket Buy Order"."""
        reason = extract_alpaca_reason(exc)
        message = f"Trade fehlgeschlagen: {symbol} {order_kind} abgelehnt, Grund: {reason}"
        self._send_throttled(f"{symbol}:{order_kind}", message, suppressed_label="weitere gleichartige Fehlschlaege")

    def notify_unprotected_position(self, symbol: str, detail: str, critical: bool = False) -> None:
        """Sicherheitsnetz-Alarm (siehe bot._check_position_protection):
        eine offene Position hat gerade keine aktive Stop-Loss-Order --
        egal aus welchem Grund (z.B. eine abgelaufene, OCO-verknuepfte
        Take-Profit-Order hat beim Ablauf automatisch auch den Stop-Loss
        storniert). `detail` sollte kurz zusammenfassen, was der Bot dagegen
        unternommen hat (neue Stop-Loss-Order nachgelegt oder nicht).

        `critical=True`: der Bot konnte die Position weder per neuer
        Stop-Loss-Order noch per Market-Sell schuetzen (Kurs bereits durch
        den Stop-Preis durchgebrochen UND auch der Notfall-Market-Sell
        fehlgeschlagen) -- eigene Alert-Stufe ("KRITISCH:" statt "WARNUNG:")
        und eigener Drossel-Schluessel, damit ein kritischer Alarm nicht
        stillschweigend im Drossel-Fenster einer vorherigen normalen Warnung
        fuer dasselbe Symbol untergeht.
        """
        prefix = "KRITISCH" if critical else "WARNUNG"
        throttle_key = f"{symbol}:Unprotected Position" + (" (KRITISCH)" if critical else "")
        suppressed_label = "weitere kritische Warnungen" if critical else "weitere gleichartige Warnungen"
        message = f"{prefix}: {symbol} hat aktuell KEINEN aktiven Stop-Loss! {detail}"
        self._send_throttled(throttle_key, message, suppressed_label=suppressed_label)

    def _send_throttled(self, throttle_key: str, message: str, suppressed_label: str) -> None:
        now = time.monotonic()

        with self._lock:
            last_sent = self._last_sent_at.get(throttle_key)
            if last_sent is not None and (now - last_sent) < self._throttle_seconds:
                self._suppressed_count[throttle_key] = self._suppressed_count.get(throttle_key, 0) + 1
                logger.info(
                    "Telegram-Meldung fuer %s gedrosselt (%d unterdrueckt in den letzten %.0fs).",
                    throttle_key,
                    self._suppressed_count[throttle_key],
                    self._throttle_seconds,
                )
                return

            suppressed = self._suppressed_count.pop(throttle_key, 0)
            self._last_sent_at[throttle_key] = now

        if suppressed:
            message += f"\n({suppressed} {suppressed_label} in den letzten {int(self._throttle_seconds // 60)} Minuten unterdrueckt)"

        send_telegram_message(self._config, message)
