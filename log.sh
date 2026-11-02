#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${1:-hcr-server-80.service}"

command -v journalctl >/dev/null 2>&1 || {
    echo "ERROR: journalctl no está instalado."
    exit 1
}

command -v python3 >/dev/null 2>&1 || {
    echo "ERROR: python3 no está instalado."
    exit 1
}

if ! systemctl list-unit-files "$SERVICE" --no-legend 2>/dev/null | grep -q .; then
    echo "ERROR: No se encontró el servicio $SERVICE"
    exit 1
fi

clear

printf '\033[1;36m'
echo "       HCR SERVER EPRO DEV"
echo "          JSON MONITOR"
printf '\033[0m'

echo "────────────────────────────────────────────────────────"
echo " Servicio : $SERVICE"
echo " Formato  : JSON"
echo " Modo     : TIEMPO REAL"
echo "────────────────────────────────────────────────────────"
echo
echo "Esperando registros... (CTRL+C para salir)"
echo

journalctl -u "$SERVICE" -f -n 0 -o cat --no-pager |
python3 -u -c '
import sys
import json
import re
from datetime import datetime

CYAN = "\033[1;36m"
BLUE = "\033[1;34m"
GREEN = "\033[1;32m"
YELLOW = "\033[1;33m"
RED = "\033[1;31m"
RESET = "\033[0m"

def classify(data):
    msg = str(data.get("msg", "")).lower()

    if msg == "runtime_configured":
        return "CONFIGURATION"

    if msg.startswith("hcr_path_") or "diagnostic" in msg:
        return "DIAGNOSTICS"

    if any(word in msg for word in (
        "session_stats",
        "session_statistics",
        "session_stats_",
        "stream_stats",
        "stream_statistics"
    )):
        return "SESSION_STATS"

    return "UNKNOWN"

def process(line):
    line = line.strip()

    if not line:
        return

    # Extraer JSON incluso si journalctl añade texto externo.
    start = line.find("{")
    if start < 0:
        return

    try:
        data = json.loads(line[start:])
    except json.JSONDecodeError:
        return

    if not isinstance(data, dict):
        return

    category = classify(data)

    result = {
        "record_type": category,
        "service": sys.argv[1],
        "received_at": datetime.now().astimezone().isoformat(),
        "data": data
    }

    if category == "DIAGNOSTICS":
        color = CYAN
    elif category == "SESSION_STATS":
        color = GREEN
    elif category == "CONFIGURATION":
        color = BLUE
    else:
        color = YELLOW

    print(color + json.dumps(
        result,
        indent=2,
        ensure_ascii=False
    ) + RESET, flush=True)

for line in sys.stdin:
    try:
        process(line)
    except Exception as error:
        print(RED + "Error procesando registro: " +
              str(error) + RESET, flush=True)
' "$SERVICE"
