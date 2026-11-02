#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SERVICE="${1:-hcr-server-80.service}"

# ============================================================
#                 HCR SERVER EPRO DEV
#                      JSON MONITOR
#                       PROFESSIONAL
# ============================================================

# ------------------------------------------------------------
# VALIDACIÓN DE DEPENDENCIAS
# ------------------------------------------------------------

for command_name in journalctl python3 systemctl grep; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "ERROR: No se encontró el comando $command_name."
        exit 1
    fi
done

# ------------------------------------------------------------
# VALIDACIÓN DEL SERVICIO
# ------------------------------------------------------------

if ! systemctl list-unit-files "$SERVICE" --no-legend 2>/dev/null |
     grep -Fq "$SERVICE"; then

    echo "ERROR: No se encontró el servicio $SERVICE"
    exit 1
fi

# ------------------------------------------------------------
# INTERFAZ
# ------------------------------------------------------------

clear

printf '\033[1;36m'
echo "       HCR SERVER EPRO DEV"
echo "          JSON MONITOR"
printf '\033[0m'

echo "────────────────────────────────────────────────────────"
echo " Servicio : $SERVICE"
echo " Formato  : JSON"
echo " Modo     : TIEMPO REAL"
echo " Análisis : AVANZADO"
echo "────────────────────────────────────────────────────────"
echo
echo "Categorías:"
echo "  SESSION_STATS          Estadísticas de sesiones"
echo "  PATH_DIAGNOSTICS       Diagnóstico de operaciones"
echo "  CONNECTION_DIAGNOSTICS Diagnóstico de conexiones"
echo "  CONFIGURATION          Configuración del servidor"
echo "  LISTENER_STATUS        Estado del listener"
echo "  OTHER                  Otros eventos"
echo
echo "Esperando registros... (CTRL+C para salir)"
echo

# ------------------------------------------------------------
# MONITOR EN TIEMPO REAL
# ------------------------------------------------------------

trap 'exit 0' INT TERM

journalctl \
    --unit="$SERVICE" \
    --follow \
    --lines=0 \
    --output=cat \
    --no-pager |
python3 -u -c '

import sys
import json
from datetime import datetime


# ============================================================
#                         CONFIGURACIÓN
# ============================================================

SERVICE = sys.argv[1]

CYAN    = "\033[1;36m"
BLUE    = "\033[1;34m"
GREEN   = "\033[1;32m"
YELLOW  = "\033[1;33m"
RED     = "\033[1;31m"
MAGENTA = "\033[1;35m"
WHITE   = "\033[1;37m"
RESET   = "\033[0m"

USE_COLOR = sys.stdout.isatty()


# ============================================================
#                       FUNCIONES BASE
# ============================================================

def color(value, selected):

    value = str(value)

    if USE_COLOR:
        return selected + value + RESET

    return value


def now():

    return datetime.now().astimezone().isoformat()


def safe_int(value, default=0):

    try:
        if value is None:
            return default

        return int(value)

    except (ValueError, TypeError, OverflowError):
        return default


def safe_number(value, default=None):

    try:
        if value is None:
            return default

        return float(value)

    except (ValueError, TypeError, OverflowError):
        return default


def duration_ms(value):

    number = safe_number(value)

    if number is None:
        return None

    return round(number / 1000, 3)


def get_message(data):

    return str(
        data.get("msg", "")
    ).strip().lower()


def get_event(data):

    return data.get(
        "msg",
        "event_not_specified"
    )


def get_dict(data, key):

    value = data.get(key, {})

    if isinstance(value, dict):
        return value

    return {}


def unique(values):

    result = []

    for value in values:

        if value and value not in result:
            result.append(value)

    return result


def safe_bool(value):

    if isinstance(value, bool):
        return value

    if isinstance(value, (int, float)):
        return value != 0

    if isinstance(value, str):
        return value.strip().lower() in (
            "true", "1", "yes", "on"
        )

    return False


# ============================================================
#                    CLASIFICACIÓN DE EVENTOS
# ============================================================

def classify(data):

    msg = get_message(data)

    # Configuración
    if msg == "runtime_configured":
        return "CONFIGURATION"

    # Listener
    if msg in (
        "listener_started",
        "listener_stopped",
        "listener_closed"
    ):
        return "LISTENER_STATUS"

    if msg.startswith("listener_"):
        return "LISTENER_EVENTS"

    # Session Stats
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

    # Diagnóstico de operaciones
    if msg == "hcr_path":
        return "PATH_DIAGNOSTICS"

    # Familia de diagnósticos
    if "diagnostic" in msg:
        return "OTHER_DIAGNOSTICS"

    if msg.startswith("hcr_path_"):
        return "OTHER_PATH_EVENTS"

    # Eventos adicionales
    if msg.startswith("session_"):
        return "SESSION_EVENTS"

    if msg.startswith("connection_"):
        return "CONNECTION_EVENTS"

    return "OTHER"


# ============================================================
#                  CLASIFICACIÓN DE ERRORES
# ============================================================

def classify_error(kind=None, phase=None, code=None):

    kind = str(kind or "").strip().lower()
    phase = str(phase or "").strip().lower()
    code = str(code or "").strip().upper()

    # Error de secuencia
    if "sequence" in code:
        return "SEQUENCE_ERROR"

    # Timeout
    if "timeout" in kind or "timeout" in phase:
        return "TIMEOUT"

    # Error de entrada/salida
    if kind in ("io", "i/o"):
        return "IO_ERROR"

    # Error de protocolo
    if "protocol" in kind or "protocol" in phase:
        return "PROTOCOL_ERROR"

    # Código no vacío sin semántica conocida
    if code:
        return "CODE_PRESENT"

    # Fallo genérico
    if kind in (
        "error",
        "failed",
        "failure"
    ):
        return "FAILURE"

    return None


# ============================================================
#                  ANÁLISIS DE FALLOS
# ============================================================

def analyze_failure(operation):

    first = get_dict(operation, "first_failure")
    last = get_dict(operation, "last_failure")

    # Priorizar el último fallo; si no existe, usar el primero.
    failure = last or first

    if not failure:
        return None

    kind = failure.get("kind")
    phase = failure.get("phase")
    code = failure.get("code")

    return {
        "type": classify_error(kind, phase, code),
        "phase": phase,
        "kind": kind,
        "code": code,
        "sequence": failure.get("seq"),
        "elapsed_ms": duration_ms(
            failure.get("elapsed_us")
        ),
        "request_complete": failure.get(
            "request_complete"
        )
    }


# ============================================================
#                   ANÁLISIS DE SESSION STATS
# ============================================================

def analyze_session(data):

    closed = safe_bool(data.get("closed"))

    status = "CLOSED" if closed else "ACTIVE"

    upload_pending = safe_int(
        data.get("upload_pending")
    )

    pending_bytes = safe_int(
        data.get("pending_bytes")
    )

    replay_bytes = safe_int(
        data.get("replay_bytes")
    )

    return {

        "status": status,

        "index": data.get("index"),

        "upload": {

            "next": data.get("upload_next"),

            "pending": upload_pending,

            "pending_bytes": pending_bytes,

            "target_written_bytes": data.get(
                "target_written"
            )
        },

        "download": {

            "next": data.get("download_next"),

            "delivery_next": data.get(
                "delivery_next"
            ),

            "acked": data.get("acked"),

            "target_read_bytes": data.get(
                "target_read"
            ),

            "replay_bytes": replay_bytes
        },

        "indicators": {

            "has_pending_upload": pending_bytes > 0,

            "has_replay_data": replay_bytes > 0,

            "session_closed": closed
        },

        "closed": closed
    }


# ============================================================
#                  ANÁLISIS DE OPERACIONES
# ============================================================

def analyze_operation(operation):

    completed = safe_int(
        operation.get("completed")
    )

    failed = safe_int(
        operation.get("failed")
    )

    rejected = safe_int(
        operation.get("rejected")
    )

    last = get_dict(operation, "last")

    phase = last.get("phase")
    kind = last.get("kind")
    code = last.get("code")

    failure = analyze_failure(operation)

    detected = []

    if failed > 0:

        detected.append(
            failure.get("type")
            if failure else "FAILURE"
        )

    if rejected > 0:
        detected.append("REJECTED")

        rejection_error = classify_error(
            kind,
            phase,
            code
        )

        if rejection_error:
            detected.append(rejection_error)

    # Estado de la operación
    if failed > 0:
        status = "FAILURE"

    elif rejected > 0:
        status = "REJECTED"

    elif completed > 0:
        status = "NORMAL"

    else:
        status = "NO_ACTIVITY"

    return {

        "op": operation.get("op"),

        "status": status,

        "completed": completed,

        "failed": failed,

        "rejected": rejected,

        "request_read_bytes": operation.get(
            "request_read_b"
        ),

        "response_written_bytes": operation.get(
            "response_write_b"
        ),

        "max_request_bytes": operation.get(
            "max_request_b"
        ),

        "max_response_bytes": operation.get(
            "max_response_b"
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

            # Se conserva el código numérico.
            # No se interpreta sin documentación oficial.
            "status_code": last.get("status"),

            "sequence": last.get("seq"),

            "elapsed_ms": duration_ms(
                last.get("elapsed_us")
            ),

            "request_expected_bytes": last.get(
                "request_expected_b"
            ),

            "request_read_bytes": last.get(
                "request_read_b"
            ),

            "request_complete": last.get(
                "request_complete"
            ),

            "response_expected_bytes": last.get(
                "response_expected_b"
            ),

            "response_written_bytes": last.get(
                "response_write_b"
            ),

            "response_prepared": last.get(
                "response_prepared"
            )
        },

        "detected_conditions": unique(detected),

        "first_failure": (
            get_dict(operation, "first_failure") or None
        ),

        "last_failure": (
            get_dict(operation, "last_failure") or None
        ),

        "failure_analysis": failure
    }


# ============================================================
#                 ANÁLISIS GENERAL DE HCR_PATH
# ============================================================

def analyze_path(data):

    operations = data.get("ops", [])

    if not isinstance(operations, list):
        operations = []

    analyzed = []

    total_completed = 0
    total_failed = 0
    total_rejected = 0

    total_request_bytes = 0
    total_response_bytes = 0

    detected = []

    for operation in operations:

        if not isinstance(operation, dict):
            continue

        result = analyze_operation(operation)

        analyzed.append(result)

        total_completed += result["completed"]
        total_failed += result["failed"]
        total_rejected += result["rejected"]

        total_request_bytes += safe_int(
            result["request_read_bytes"]
        )

        total_response_bytes += safe_int(
            result["response_written_bytes"]
        )

        detected.extend(
            result["detected_conditions"]
        )

    # Estado general
    if total_failed > 0:
        status = "FAILURE"

    elif total_rejected > 0:
        status = "REJECTED"

    elif total_completed > 0:
        status = "NORMAL"

    else:
        status = "NO_ACTIVITY"

    return {

        "status": status,

        "run": data.get("run"),

        "summary": {

            "completed": total_completed,

            "failed": total_failed,

            "rejected": total_rejected,

            "operations_count": len(analyzed),

            "request_read_bytes": total_request_bytes,

            "response_written_bytes": total_response_bytes
        },

        "session_counters": {

            "upload_next": data.get("upload_next"),

            "pending_bytes": data.get("pending_bytes"),

            "target_written_bytes": data.get(
                "target_written"
            ),

            "target_read_bytes": data.get(
                "target_read"
            ),

            "delivery_next": data.get(
                "delivery_next"
            ),

            "acked": data.get("acked"),

            "replay_bytes": data.get(
                "replay_bytes"
            ),

            "closed": data.get("closed")
        },

        "detected_conditions": unique(detected),

        "operations": analyzed
    }


# ============================================================
#               ANÁLISIS DE CONNECTION DIAGNOSTICS
# ============================================================

def analyze_connections(data):

    unassigned = get_dict(data, "unassigned")

    completed = safe_int(
        unassigned.get("completed")
    )

    failed = safe_int(
        unassigned.get("failed")
    )

    rejected = safe_int(
        unassigned.get("rejected")
    )

    limited = safe_int(
        data.get("limited")
    )

    last = get_dict(unassigned, "last")

    first_failure = get_dict(
        unassigned,
        "first_failure"
    )

    last_failure = get_dict(
        unassigned,
        "last_failure"
    )

    # Seleccionar el detalle de fallo disponible.
    failure = last_failure or first_failure

    if failure:
        error_type = classify_error(
            failure.get("kind"),
            failure.get("phase"),
            failure.get("code")
        )
    else:
        error_type = classify_error(
            last.get("kind"),
            last.get("phase"),
            last.get("code")
        )

    conditions = []

    if failed > 0:
        status = "FAILURE"
        conditions.append(error_type or "FAILURE")

    elif rejected > 0:
        status = "REJECTED"
        conditions.append("REJECTED")

    elif limited > 0:
        status = "LIMITED"
        conditions.append("LIMITED")

    elif completed > 0:
        status = "NORMAL"

    else:
        status = "NORMAL"

    return {

        "status": status,

        "connections": {

            "accepted": data.get("accepted"),

            "inflight": data.get("inflight"),

            "limited": limited,

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

            "max_request_bytes": unassigned.get(
                "max_request_b"
            ),

            "max_response_bytes": unassigned.get(
                "max_response_b"
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

                "code": last.get("code"),

                "status_code": last.get("status"),

                "sequence": last.get("seq"),

                "elapsed_ms": duration_ms(
                    last.get("elapsed_us")
                ),

                "request_expected_bytes": last.get(
                    "request_expected_b"
                ),

                "request_read_bytes": last.get(
                    "request_read_b"
                ),

                "request_complete": last.get(
                    "request_complete"
                ),

                "response_expected_bytes": last.get(
                    "response_expected_b"
                ),

                "response_written_bytes": last.get(
                    "response_write_b"
                )
            },

            "first_failure": first_failure or None,

            "last_failure": last_failure or None
        },

        "detected_conditions": unique(conditions),

        "detected_error": error_type
    }


# ============================================================
#                  ANÁLISIS DE CONFIGURACIÓN
# ============================================================

def analyze_configuration(data):

    interval = safe_int(
        data.get("diagnostics_interval_seconds")
    )

    return {

        "status": "CONFIGURED",

        "version": data.get("version"),

        "max_connections": data.get(
            "max_connections"
        ),

        "max_sessions": data.get(
            "max_sessions"
        ),

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

        "diagnostics": {

            "enabled": interval > 0,

            "interval_seconds": interval
        }
    }


# ============================================================
#                     ANÁLISIS LISTENER
# ============================================================

def analyze_listener(data):

    msg = get_message(data)

    states = {
        "listener_started": "STARTED",
        "listener_stopped": "STOPPED",
        "listener_closed": "CLOSED"
    }

    status = states.get(
        msg,
        "LISTENER_EVENT"
    )

    return {

        "status": status,

        "version": data.get("version"),

        "address": data.get("address"),

        "transport": data.get("transport")
    }


# ============================================================
#                   ANÁLISIS DE SEVERIDAD
# ============================================================

def get_severity(category, analysis):

    status = analysis.get("status")

    if status == "FAILURE":
        return "ERROR"

    if status in (
        "REJECTED",
        "LIMITED",
        "STOPPED",
        "CLOSED"
    ):
        return "WARNING"

    if category in (
        "CONFIGURATION",
        "LISTENER_STATUS",
        "SESSION_STATS",
        "PATH_DIAGNOSTICS",
        "CONNECTION_DIAGNOSTICS"
    ):
        return "INFO"

    return "NOTICE"


# ============================================================
#                      COLOR POR EVENTO
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

        "LISTENER_EVENTS": GREEN,

        "OTHER_DIAGNOSTICS": CYAN,

        "OTHER_PATH_EVENTS": CYAN,

        "SESSION_EVENTS": GREEN,

        "CONNECTION_EVENTS": MAGENTA,

        "OTHER": WHITE
    }

    return colors.get(category, WHITE)


# ============================================================
#                  CONSTRUCCIÓN DEL RESULTADO
# ============================================================

def build_result(data):

    category = classify(data)

    event = get_event(data)

    analysis = {}

    if category == "SESSION_STATS":
        analysis = analyze_session(data)

    elif category == "PATH_DIAGNOSTICS":
        analysis = analyze_path(data)

    elif category == "CONNECTION_DIAGNOSTICS":
        analysis = analyze_connections(data)

    elif category == "CONFIGURATION":
        analysis = analyze_configuration(data)

    elif category in (
        "LISTENER_STATUS",
        "LISTENER_EVENTS"
    ):
        analysis = analyze_listener(data)

    severity = get_severity(
        category,
        analysis
    )

    return {

        "record_type": category,

        "event": event,

        "severity": severity,

        "service": SERVICE,

        "received_at": now(),

        "analysis": analysis,

        # Datos originales de HCR.
        # No se eliminan ni se reinterpretan.
        "data": data
    }


# ============================================================
#                    REGISTROS NO JSON
# ============================================================

def build_raw_result(line):

    return {

        "record_type": "OTHER",

        "event": "NON_JSON_LINE",

        "severity": "NOTICE",

        "service": SERVICE,

        "received_at": now(),

        "analysis": {
            "status": "UNSTRUCTURED_LOG"
        },

        "data": {
            "raw": line
        }
    }


# ============================================================
#                    PROCESAMIENTO JSON
# ============================================================

def process(line):

    line = line.strip()

    if not line:
        return

    start = line.find("{")

    # Registro sin JSON
    if start < 0:

        result = build_raw_result(line)

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

    # Extraer JSON permitiendo texto posterior.
    try:

        decoder = json.JSONDecoder()

        data, _ = decoder.raw_decode(
            line[start:]
        )

    except json.JSONDecodeError as error:

        result = {

            "record_type": "OTHER",

            "event": "INVALID_JSON",

            "severity": "WARNING",

            "service": SERVICE,

            "received_at": now(),

            "analysis": {

                "status": "PARSE_ERROR",

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

    result = build_result(data)

    selected_color = get_color(
        result["record_type"],
        result["severity"]
    )

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

try:

    for line in sys.stdin:

        try:
            process(line)

        except Exception as error:

            result = {

                "record_type": "MONITOR_ERROR",

                "event": "PROCESSING_ERROR",

                "severity": "ERROR",

                "service": SERVICE,

                "received_at": now(),

                "analysis": {
                    "error": str(error)
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

except KeyboardInterrupt:
    pass

' "$SERVICE"

exit 0
