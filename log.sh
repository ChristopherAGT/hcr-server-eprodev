#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${1:-hcr-server-80.service}"

# ============================================================
#                  HCR SERVER EPRO DEV
#                       JSON MONITOR
# ============================================================

command -v journalctl >/dev/null 2>&1 || {
    echo "ERROR: journalctl no está instalado."
    exit 1
}

command -v python3 >/dev/null 2>&1 || {
    echo "ERROR: python3 no está instalado."
    exit 1
}

command -v systemctl >/dev/null 2>&1 || {
    echo "ERROR: systemctl no está instalado."
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
echo " Análisis : AUTOMÁTICO"
echo "────────────────────────────────────────────────────────"
echo
echo "Esperando registros... (CTRL+C para salir)"
echo

journalctl -u "$SERVICE" -f -n 0 -o cat --no-pager |
python3 -u -c '

import sys
import json
from datetime import datetime

# ============================================================
#                         COLORES
# ============================================================

CYAN    = "\033[1;36m"
BLUE    = "\033[1;34m"
GREEN   = "\033[1;32m"
YELLOW  = "\033[1;33m"
RED     = "\033[1;31m"
MAGENTA = "\033[1;35m"
WHITE   = "\033[1;37m"
RESET   = "\033[0m"

USE_COLOR = sys.stdout.isatty()

SERVICE = sys.argv[1]


# ============================================================
#                    FUNCIONES GENERALES
# ============================================================

def color(text, selected):
    if USE_COLOR:
        return selected + text + RESET
    return text


def safe_int(value, default=0):
    try:
        return int(value)
    except (ValueError, TypeError):
        return default


def get_message(data):
    return str(data.get("msg", "")).strip().lower()


def get_event(data):
    return data.get("msg", "event_not_specified")


def duration_ms(value):
    if value is None:
        return None

    try:
        return round(float(value) / 1000, 3)
    except (ValueError, TypeError):
        return None


# ============================================================
#                    CLASIFICACIÓN PRINCIPAL
# ============================================================

def classify(data):

    msg = get_message(data)

    # Configuración del servidor
    if msg == "runtime_configured":
        return "CONFIGURATION"

    # Estado del listener
    if msg in (
        "listener_started",
        "listener_stopped",
        "listener_closed"
    ):
        return "LISTENER_STATUS"

    # Estadísticas de sesiones
    if msg in (
        "session_stats",
        "session_statistics"
    ) or msg.startswith((
        "session_stats_",
        "session_statistics_",
        "stream_stats",
        "stream_statistics"
    )):
        return "SESSION_STATS"

    # Diagnóstico de conexiones
    if msg == "hcr_path_connections":
        return "CONNECTION_DIAGNOSTICS"

    # Diagnóstico detallado de operaciones
    if msg == "hcr_path":
        return "PATH_DIAGNOSTICS"

    # Otros eventos de diagnóstico
    if "diagnostic" in msg:
        return "OTHER_DIAGNOSTICS"

    # Otros eventos conocidos de la familia HCR
    if msg.startswith("hcr_path_"):
        return "OTHER_PATH_EVENTS"

    # Eventos adicionales
    if msg.startswith("listener_"):
        return "LISTENER_STATUS"

    if msg.startswith("session_"):
        return "SESSION_EVENTS"

    if msg.startswith("connection_"):
        return "CONNECTION_EVENTS"

    return "OTHER"


# ============================================================
#                  CLASIFICACIÓN DE ERRORES
# ============================================================

def classify_error(kind=None, phase=None, code=None):

    kind = str(kind or "").lower()
    phase = str(phase or "").lower()
    code = str(code or "").upper()

    if "sequence" in code:
        return "SEQUENCE_ERROR"

    if "timeout" in kind or "timeout" in phase:
        return "TIMEOUT"

    if kind in ("io", "i/o"):
        return "IO_ERROR"

    if "protocol" in kind or "protocol" in phase:
        return "PROTOCOL_ERROR"

    if code:
        return "PROTOCOL_ERROR"

    if kind in ("error", "failed", "failure"):
        return "FAILURE"

    return None


# ============================================================
#                  ANÁLISIS DE SESSION STATS
# ============================================================

def analyze_session(data):

    closed = bool(data.get("closed", False))

    if closed:
        status = "CLOSED"
    else:
        status = "ACTIVE"

    return {
        "status": status,
        "index": data.get("index"),
        "upload": {
            "next": data.get("upload_next"),
            "pending": data.get("upload_pending"),
            "pending_bytes": data.get("pending_bytes"),
            "target_written_bytes": data.get("target_written")
        },
        "download": {
            "next": data.get("download_next"),
            "delivery_next": data.get("delivery_next"),
            "acked": data.get("acked"),
            "target_read_bytes": data.get("target_read"),
            "replay_bytes": data.get("replay_bytes")
        },
        "closed": closed
    }


# ============================================================
#              ANÁLISIS DE PATH DIAGNOSTICS
# ============================================================

def analyze_path(data):

    operations = data.get("ops", [])

    if not isinstance(operations, list):
        operations = []

    total_completed = 0
    total_failed = 0
    total_rejected = 0

    analyzed_operations = []
    detected_errors = []

    for operation in operations:

        if not isinstance(operation, dict):
            continue

        completed = safe_int(operation.get("completed"))
        failed = safe_int(operation.get("failed"))
        rejected = safe_int(operation.get("rejected"))

        total_completed += completed
        total_failed += failed
        total_rejected += rejected

        last = operation.get("last", {})

        if not isinstance(last, dict):
            last = {}

        first_failure = operation.get("first_failure", {})
        last_failure = operation.get("last_failure", {})

        if not isinstance(first_failure, dict):
            first_failure = {}

        if not isinstance(last_failure, dict):
            last_failure = {}

        phase = last.get("phase")
        kind = last.get("kind")
        code = last.get("code")

        error_type = classify_error(
            kind,
            phase,
            code
        )

        if error_type:
            detected_errors.append(error_type)

        if failed > 0:

            failure_kind = (
                last_failure.get("kind")
                or first_failure.get("kind")
                or kind
            )

            failure_phase = (
                last_failure.get("phase")
                or first_failure.get("phase")
                or phase
            )

            failure_code = (
                last_failure.get("code")
                or first_failure.get("code")
                or code
            )

            failure_type = classify_error(
                failure_kind,
                failure_phase,
                failure_code
            )

            if failure_type:
                detected_errors.append(failure_type)

        if rejected > 0 and code:
            detected_errors.append(
                classify_error(kind, phase, code)
                or "REJECTED"
            )

        analyzed_operations.append({

            "op": operation.get("op"),

            "status": (
                "FAILURE" if failed > 0
                else "REJECTED" if rejected > 0
                else "NORMAL"
            ),

            "completed": completed,
            "failed": failed,
            "rejected": rejected,

            "request_read_bytes": operation.get(
                "request_read_b"
            ),

            "response_written_bytes": operation.get(
                "response_write_b"
            ),

            "total_duration_ms": duration_ms(
                operation.get("total_us")
            ),

            "max_duration_ms": duration_ms(
                operation.get("max_us")
            ),

            "last": {
                "phase": phase,
                "kind": kind,
                "code": code,
                "status": last.get("status"),
                "sequence": last.get("seq"),
                "elapsed_ms": duration_ms(
                    last.get("elapsed_us")
                ),
                "request_complete": last.get(
                    "request_complete"
                )
            },

            "first_failure": first_failure or None,
            "last_failure": last_failure or None
        })

    if total_failed > 0:
        status = "FAILURE"

    elif total_rejected > 0:
        status = "REJECTED"

    else:
        status = "NORMAL"

    errors = list(dict.fromkeys(
        error for error in detected_errors if error
    ))

    return {

        "status": status,

        "summary": {
            "completed": total_completed,
            "failed": total_failed,
            "rejected": total_rejected,
            "operations_count": len(analyzed_operations)
        },

        "detected_errors": errors,

        "operations": analyzed_operations
    }


# ============================================================
#           ANÁLISIS DE CONNECTION DIAGNOSTICS
# ============================================================

def analyze_connections(data):

    unassigned = data.get("unassigned", {})

    if not isinstance(unassigned, dict):
        unassigned = {}

    completed = safe_int(unassigned.get("completed"))
    failed = safe_int(unassigned.get("failed"))
    rejected = safe_int(unassigned.get("rejected"))

    last = unassigned.get("last", {})

    if not isinstance(last, dict):
        last = {}

    first_failure = unassigned.get("first_failure", {})
    last_failure = unassigned.get("last_failure", {})

    if not isinstance(first_failure, dict):
        first_failure = {}

    if not isinstance(last_failure, dict):
        last_failure = {}

    error_type = classify_error(
        last.get("kind"),
        last.get("phase"),
        last.get("code")
    )

    if failed > 0:
        status = "FAILURE"

        failure_kind = (
            last_failure.get("kind")
            or first_failure.get("kind")
            or last.get("kind")
        )

        failure_phase = (
            last_failure.get("phase")
            or first_failure.get("phase")
            or last.get("phase")
        )

        error_type = classify_error(
            failure_kind,
            failure_phase,
            last_failure.get("code")
            or first_failure.get("code")
        ) or error_type

    elif rejected > 0:
        status = "REJECTED"

    elif safe_int(data.get("limited")) > 0:
        status = "LIMITED"

    else:
        status = "NORMAL"

    return {

        "status": status,

        "connections": {
            "accepted": data.get("accepted"),
            "inflight": data.get("inflight"),
            "limited": data.get("limited"),
            "omitted_requests": data.get(
                "omitted_requests"
            )
        },

        "unassigned": {

            "completed": completed,
            "failed": failed,
            "rejected": rejected,

            "request_read_bytes": unassigned.get(
                "request_read_b"
            ),

            "response_written_bytes": unassigned.get(
                "response_write_b"
            ),

            "total_duration_ms": duration_ms(
                unassigned.get("total_us")
            ),

            "max_duration_ms": duration_ms(
                unassigned.get("max_us")
            ),

            "last": {
                "phase": last.get("phase"),
                "kind": last.get("kind"),
                "sequence": last.get("seq"),
                "status": last.get("status"),
                "elapsed_ms": duration_ms(
                    last.get("elapsed_us")
                ),
                "request_complete": last.get(
                    "request_complete"
                )
            },

            "first_failure": first_failure or None,
            "last_failure": last_failure or None
        },

        "detected_error": error_type
    }


# ============================================================
#                  ANÁLISIS DE CONFIGURACIÓN
# ============================================================

def analyze_configuration(data):

    return {
        "status": "CONFIGURED",
        "version": data.get("version"),
        "max_connections": data.get("max_connections"),
        "max_sessions": data.get("max_sessions"),
        "max_sessions_per_source": data.get(
            "max_sessions_per_source"
        ),
        "session_idle_timeout_seconds": data.get(
            "session_idle_timeout_seconds"
        ),
        "cleanup_interval_seconds": data.get(
            "cleanup_interval_seconds"
        ),
        "rejection_log_interval_seconds": data.get(
            "rejection_log_interval_seconds"
        ),
        "diagnostics_interval_seconds": data.get(
            "diagnostics_interval_seconds"
        )
    }


# ============================================================
#                    ANÁLISIS DEL LISTENER
# ============================================================

def analyze_listener(data):

    msg = get_message(data)

    if msg == "listener_started":
        status = "STARTED"

    elif msg == "listener_stopped":
        status = "STOPPED"

    elif msg == "listener_closed":
        status = "CLOSED"

    else:
        status = "LISTENER_EVENT"

    return {
        "status": status,
        "version": data.get("version"),
        "address": data.get("address"),
        "transport": data.get("transport")
    }


# ============================================================
#                    SEVERIDAD DEL EVENTO
# ============================================================

def get_severity(category, analysis):

    if category in (
        "CONFIGURATION",
        "LISTENER_STATUS"
    ):
        status = analysis.get("status")

        if status in ("STOPPED", "CLOSED"):
            return "WARNING"

        return "INFO"

    if category == "SESSION_STATS":

        if analysis.get("status") == "CLOSED":
            return "INFO"

        return "INFO"

    if category in (
        "PATH_DIAGNOSTICS",
        "CONNECTION_DIAGNOSTICS"
    ):

        status = analysis.get("status")

        if status == "FAILURE":
            return "ERROR"

        if status in ("REJECTED", "LIMITED"):
            return "WARNING"

        return "INFO"

    if category in (
        "OTHER_DIAGNOSTICS",
        "OTHER_PATH_EVENTS"
    ):
        return "INFO"

    return "NOTICE"


# ============================================================
#                    COLOR POR CATEGORÍA
# ============================================================

def get_color(category, severity):

    if severity == "ERROR":
        return RED

    if severity == "WARNING":
        return YELLOW

    colors = {
        "SESSION_STATS": GREEN,
        "PATH_DIAGNOSTICS": CYAN,
        "CONNECTION_DIAGNOSTICS": MAGENTA,
        "CONFIGURATION": BLUE,
        "LISTENER_STATUS": GREEN,
        "OTHER_DIAGNOSTICS": CYAN,
        "OTHER_PATH_EVENTS": CYAN,
        "SESSION_EVENTS": GREEN,
        "CONNECTION_EVENTS": MAGENTA,
        "OTHER": YELLOW
    }

    return colors.get(category, WHITE)


# ============================================================
#                     PROCESAMIENTO JSON
# ============================================================

def process(line):

    line = line.strip()

    if not line:
        return

    start = line.find("{")

    # Registro que no contiene JSON.
    if start < 0:

        result = {
            "record_type": "OTHER",
            "event": "NON_JSON_LINE",
            "severity": "NOTICE",
            "service": SERVICE,
            "received_at": datetime.now().astimezone().isoformat(),
            "data": {
                "raw": line
            }
        }

        print(
            color(
                json.dumps(
                    result,
                    indent=2,
                    ensure_ascii=False
                ),
                YELLOW
            ),
            flush=True
        )

        return

    try:
        data = json.loads(line[start:])

    except json.JSONDecodeError as error:

        result = {
            "record_type": "OTHER",
            "event": "INVALID_JSON",
            "severity": "WARNING",
            "service": SERVICE,
            "received_at": datetime.now().astimezone().isoformat(),
            "analysis": {
                "error": str(error)
            },
            "data": {
                "raw": line
            }
        }

        print(
            color(
                json.dumps(
                    result,
                    indent=2,
                    ensure_ascii=False
                ),
                RED
            ),
            flush=True
        )

        return

    if not isinstance(data, dict):
        data = {
            "raw_data": data
        }

    category = classify(data)

    event = get_event(data)

    analysis = {}

    # --------------------------------------------------------
    # Clasificación y análisis individual
    # --------------------------------------------------------

    if category == "SESSION_STATS":
        analysis = analyze_session(data)

    elif category == "PATH_DIAGNOSTICS":
        analysis = analyze_path(data)

    elif category == "CONNECTION_DIAGNOSTICS":
        analysis = analyze_connections(data)

    elif category == "CONFIGURATION":
        analysis = analyze_configuration(data)

    elif category == "LISTENER_STATUS":
        analysis = analyze_listener(data)

    severity = get_severity(category, analysis)

    result = {

        "record_type": category,

        "event": event,

        "severity": severity,

        "service": SERVICE,

        "received_at": datetime.now().astimezone().isoformat(),

        "analysis": analysis,

        # Se conserva el registro original sin modificarlo.
        "data": data
    }

    selected_color = get_color(category, severity)

    print(
        color(
            json.dumps(
                result,
                indent=2,
                ensure_ascii=False
            ),
            selected_color
        ),
        flush=True
    )


# ============================================================
#                       BUCLE PRINCIPAL
# ============================================================

for line in sys.stdin:

    try:
        process(line)

    except KeyboardInterrupt:
        break

    except Exception as error:

        print(
            color(
                json.dumps({
                    "record_type": "MONITOR_ERROR",
                    "severity": "ERROR",
                    "service": SERVICE,
                    "error": str(error),
                    "received_at": datetime.now().astimezone().isoformat()
                }, indent=2, ensure_ascii=False),
                RED
            ),
            flush=True
        )

' "$SERVICE"
