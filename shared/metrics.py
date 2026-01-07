"""
EWOA-safe metrics emission:
- fire-and-forget
- best-effort
- NEVER blocks execution
Default sink: StatsD over UDP (optional).
"""
import os
import socket

_HOST = os.getenv("STATSD_HOST", "")
_PORT = int(os.getenv("STATSD_PORT", "8125"))
_ENABLED = bool(_HOST)
_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM) if _ENABLED else None


def timing_ms(name: str, value_ms: float, tags: dict | None = None) -> None:
    if not _ENABLED:
        return
    try:
        tag_str = ""
        if tags:
            tag_str = "|#" + ",".join([f"{k}:{v}" for k, v in tags.items()])
        msg = f"{name}:{int(value_ms)}|ms{tag_str}"
        _sock.sendto(msg.encode("utf-8"), (_HOST, _PORT))
    except Exception:
        return


def incr(name: str, value: int = 1, tags: dict | None = None) -> None:
    if not _ENABLED:
        return
    try:
        tag_str = ""
        if tags:
            tag_str = "|#" + ",".join([f"{k}:{v}" for k, v in tags.items()])
        msg = f"{name}:{int(value)}|c{tag_str}"
        _sock.sendto(msg.encode("utf-8"), (_HOST, _PORT))
    except Exception:
        return
