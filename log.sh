#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SERVICE="${1:-hcr-server-80.service}"

# ============================================================
#                  HCR SERVER EPRO DEV
#                     JSON MONITOR
#                       PROFESSIONAL
# ============================================================

# -------------------- COLORES -------------------------------

if [[ -t 1 ]]; then
    RESET='\033[0m'
    BOLD='\033[1m'
    DIM='\033[2m'

    RED='\033[1;31m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;34m'
    MAGENTA='\033[1;35m'
    CYAN='\033[1;36m'
    WHITE='\033[1;37m'
    GRAY='\033[0;37m'
else
    RESET=''
    BOLD=''
    DIM=''

    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    WHITE=''
    GRAY=''
fi

# -------------------- FUNCIONES VISUALES --------------------

line() {
    local selected="${1:-$MAGENTA}"

    printf '%b\n' \
        "${DIM}${selected}────────────────────────────────────────────────────────${RESET}"
}

section() {
    local title="$1"
    local selected="${2:-$CYAN}"

    printf '\n'
    printf '  %b◆%b  %b%s%b\n' \
        "$selected" "$RESET" "$WHITE$BOLD" "$title" "$RESET"
}

success() {
    printf '  %b✓%b  %b%s%b\n' \
        "$GREEN" "$RESET" "$WHITE" "$1" "$RESET"
}

error() {
    printf '  %b✗%b  %b%s%b\n' \
        "$RED" "$RESET" "$RED" "$1" "$RESET"
}

info() {
    printf '  %b›%b  %b%s%b\n' \
        "$CYAN" "$RESET" "$WHITE" "$1" "$RESET"
}

warning() {
    printf '  %b!%b  %b%s%b\n' \
        "$YELLOW" "$RESET" "$YELLOW" "$1" "$RESET"
}

# -------------------- ENCABEZADO ----------------------------

header() {
    clear 2>/dev/null || true

    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="J S O N   M O N I T O R"

    printf '\n\n'

    printf '%*s%bHCR%b %bSERVER%b %bEPRO DEV%b\n' \
        "$(( (width - ${#title}) / 2 ))" '' \
        "$CYAN$BOLD" "$RESET" \
        "$WHITE$BOLD" "$RESET" \
        "$MAGENTA$BOLD" "$RESET"

    printf '%*s%b%s%b\n' \
        "$(( (width - ${#subtitle}) / 2 ))" '' \
        "$MAGENTA$BOLD" "$subtitle" "$RESET"

    printf '\n'
    line
    printf '\n'

    printf '  %b●%b  %bMONITORIZACIÓN DE EVENTOS HCR%b\n' \
        "$GREEN" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
        "$YELLOW" "$RESET" "$GRAY" "$RESET"

    printf '\n'
    line
    printf '\n'

    printf '  %bServicio:%b  %b%s%b\n' \
        "$GRAY" "$RESET" "$CYAN$BOLD" "$SERVICE" "$RESET"

    printf '  %bFormato:%b   %bJSON%b\n' \
        "$GRAY" "$RESET" "$WHITE" "$RESET"

    printf '  %bModo:%b      %bTIEMPO REAL%b\n' \
        "$GRAY" "$RESET" "$GREEN$BOLD" "$RESET"

    printf '  %bAnálisis:%b  %bAVANZADO%b\n' \
        "$GRAY" "$RESET" "$MAGENTA$BOLD" "$RESET"

    printf '\n'
    line

    section "CATEGORÍAS DE EVENTOS" "$CYAN"

    printf '  %bSESSION_STATS%b          Estadísticas de sesiones\n' "$GREEN" "$RESET"
    printf '  %bPATH_DIAGNOSTICS%b       Diagnóstico de operaciones\n' "$CYAN" "$RESET"
    printf '  %bCONNECTION_DIAGNOSTICS%b Diagnóstico de conexiones\n' "$MAGENTA" "$RESET"
    printf '  %bCONFIGURATION%b          Configuración del servidor\n' "$BLUE" "$RESET"
    printf '  %bLISTENER_STATUS%b        Estado del listener\n' "$GREEN" "$RESET"
    printf '  %bOTHER%b                  Otros eventos\n' "$GRAY" "$RESET"

    printf '\n'
    line
    printf '\n'

    success "Monitor iniciado correctamente."
    info "Esperando registros nuevos de HCR..."
    info "Presiona CTRL+C para salir."

    printf '\n'
    line
    printf '\n'
}

# -------------------- DEPENDENCIAS --------------------------

check_requirements() {
    local command_name

    for command_name in journalctl python3 systemctl; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            error "No se encontró el comando $command_name."
            return 1
        fi
    done

    return 0
}

# -------------------- VALIDAR SERVICIO ----------------------

check_service() {
    local state

    state="$(systemctl show "$SERVICE" \
        --property=LoadState --value 2>/dev/null || true)"

    if [[ "$state" != "loaded" ]]; then
        error "No se encontró el servicio $SERVICE."
        return 1
    fi

    return 0
}

# -------------------- EJECUCIÓN -----------------------------

main() {
    if (( EUID != 0 )); then
        error "Ejecuta el monitor como root."
        exit 1
    fi

    if ! check_requirements; then
        exit 1
    fi

    if ! check_service; then
        exit 1
    fi

    header

    trap 'exit 0' INT TERM

    set +e

    journalctl \
        --unit="$SERVICE" \
        --follow \
        --lines=0 \
        --output=cat \
        --no-pager |
    python3 -u -c '

import sys
import json
import textwrap
from datetime import datetime


# ============================================================
#                     CONFIGURACIÓN
# ============================================================

SERVICE = sys.argv[1]

WIDTH = 58
LABEL_WIDTH = 25
INDENT = 2

RESET   = "\033[0m"
BOLD    = "\033[1m"
DIM     = "\033[2m"

CYAN    = "\033[1;36m"
BLUE    = "\033[1;34m"
GREEN   = "\033[1;32m"
YELLOW  = "\033[1;33m"
RED     = "\033[1;31m"
MAGENTA = "\033[1;35m"
WHITE   = "\033[1;37m"
GRAY    = "\033[0;37m"

USE_COLOR = sys.stdout.isatty()


# ============================================================
#                  IDENTIDAD VISUAL POR CATEGORÍA
# ============================================================

CATEGORY_COLORS = {

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

    "OTHER": GRAY,

    "MONITOR_ERROR": RED
}


SECTION_COLORS = {

    "SUMMARY": CYAN,

    "OPERATIONS": BLUE,

    "LAST": YELLOW,

    "FIRST FAILURE": RED,

    "LAST FAILURE": RED,

    "FAILURE ANALYSIS": RED,

    "DETECTED CONDITIONS": YELLOW,

    "SESSION COUNTERS": GREEN,

    "CONNECTIONS": MAGENTA,

    "UNASSIGNED": CYAN,

    "UPLOAD": GREEN,

    "DOWNLOAD": BLUE,

    "INDICATORS": YELLOW,

    "DIAGNOSTICS": CYAN,

    "FIRST FAILURE ANALYSIS": RED,

    "LAST FAILURE ANALYSIS": RED
}


# ============================================================
#                     FUNCIONES BASE
# ============================================================

def color(value, selected):

    value = str(value)

    if USE_COLOR:
        return selected + value + RESET

    return value


def now():

    return datetime.now().astimezone().isoformat(
        timespec="milliseconds"
    )


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

    if msg == "runtime_configured":
        return "CONFIGURATION"

    if msg in (
        "listener_started",
        "listener_stopped",
        "listener_closed"
    ):
        return "LISTENER_STATUS"

    if msg.startswith("listener_"):
        return "LISTENER_EVENTS"

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

    if msg == "hcr_path_connections":
        return "CONNECTION_DIAGNOSTICS"

    if msg == "hcr_path":
        return "PATH_DIAGNOSTICS"

    if "diagnostic" in msg:
        return "OTHER_DIAGNOSTICS"

    if msg.startswith("hcr_path_"):
        return "OTHER_PATH_EVENTS"

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

    if "sequence" in code:
        return "SEQUENCE_ERROR"

    if "timeout" in kind or "timeout" in phase:
        return "TIMEOUT"

    if kind in ("io", "i/o"):
        return "IO_ERROR"

    if "protocol" in kind or "protocol" in phase:
        return "PROTOCOL_ERROR"

    if kind in (
        "error",
        "failed",
        "failure"
    ):
        return "FAILURE"

    return None


# ============================================================
#                    ANÁLISIS DE FALLOS
# ============================================================

def analyze_failure(operation):

    first = get_dict(operation, "first_failure")
    last = get_dict(operation, "last_failure")

    failure = last or first

    if not failure:
        return None

    kind = failure.get("kind")
    phase = failure.get("phase")
    code = failure.get("code")

    return {

        "type": classify_error(
            kind,
            phase,
            code
        ),

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
#                  ANÁLISIS SESSION STATS
# ============================================================

def analyze_session(data):

    closed_value = data.get("closed")
    closed = safe_bool(closed_value)

    if closed_value is None:
        status = "UNKNOWN"
    else:
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

            "session_closed": closed_value
        },

        "closed": closed_value
    }


# ============================================================
#                    ANÁLISIS DE OPERACIONES
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
            if failure and failure.get("type")
            else "FAILURE"
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
#                  ANÁLISIS GENERAL HCR_PATH
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
#              ANÁLISIS CONNECTION DIAGNOSTICS
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
#                   ANÁLISIS CONFIGURACIÓN
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
#                    ANÁLISIS SEVERIDAD
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
#                  FORMATO DE PRESENTACIÓN
# ============================================================

def display_value(value):

    if value is None:
        return "—"

    if isinstance(value, bool):
        return "true" if value else "false"

    if isinstance(value, (dict, list)):
        return ""

    return str(value)


def terminal_color_for_status(value):

    status = str(value).upper()

    if status in (
        "FAILURE",
        "ERROR",
        "PARSE_ERROR",
        "PROCESSING_ERROR",
        "SEQUENCE_ERROR",
        "IO_ERROR",
        "PROTOCOL_ERROR"
    ):
        return RED

    if status in (
        "REJECTED",
        "LIMITED",
        "WARNING",
        "STOPPED",
        "CLOSED",
        "TIMEOUT"
    ):
        return YELLOW

    if status in (
        "NORMAL",
        "ACTIVE",
        "STARTED",
        "CONFIGURED",
        "INFO",
        "TRUE"
    ):
        return GREEN

    if status in (
        "NO_ACTIVITY",
        "NOTICE",
        "UNSTRUCTURED_LOG",
        "FALSE",
        "UNKNOWN"
    ):
        return GRAY

    return CYAN


def get_category_color(category):

    return CATEGORY_COLORS.get(
        category,
        WHITE
    )


def get_section_color(key, default):

    normalized = str(key).replace(
        "_",
        " "
    ).upper()

    return SECTION_COLORS.get(
        normalized,
        default
    )


# ============================================================
#                    SEPARADORES
# ============================================================

def print_line(selected=MAGENTA, width=None):

    if width is None:
        width = WIDTH

    width = max(12, min(width, WIDTH))

    print(
        color(
            "  " + "─" * (width - 2),
            DIM + selected
        )
    )


def print_center(text, selected=WHITE):

    text = str(text)

    if len(text) > WIDTH - 4:
        text = text[:WIDTH - 7] + "..."

    padding = max(
        0,
        (WIDTH - len(text)) // 2
    )

    print(
        " " * padding +
        color(
            text,
            BOLD + selected
        )
    )


def print_section(title, selected=CYAN, depth=0):

    title = str(title).replace(
        "_",
        " "
    ).upper()

    indent = "  " + ("  " * depth)

    print()

    print(
        indent +
        color("◆", selected) +
        "  " +
        color(
            title,
            BOLD + WHITE
        )
    )


# ============================================================
#                 PRESENTACIÓN DE VALORES
# ============================================================

def print_wrapped_value(value, selected, indent):

    available = WIDTH - indent - 2

    if available < 10:
        available = 10

    wrapped = textwrap.wrap(
        value,
        width=available,
        break_long_words=False,
        break_on_hyphens=False,
        replace_whitespace=True,
        drop_whitespace=True
    ) or ["—"]

    for part in wrapped:

        print(
            " " * indent +
            color(
                part,
                selected
            )
        )


def print_pair(label, value, selected=CYAN, indent=2):

    label = str(label).replace(
        "_",
        " "
    ).upper()

    value = display_value(value)

    if value == "":
        return

    prefix = " " * indent

    # --------------------------------------------------------
    # TIMESTAMPS: ETIQUETA COMPACTA
    # --------------------------------------------------------

    if label in (
        "TIME",
        "RECIBIDO",
        "TIMESTAMP",
        "RECEIVED AT"
    ):

        print(
            prefix +
            color(label, GRAY) +
            color(" : ", DIM) +
            color(value, selected)
        )

        return

    label_width = LABEL_WIDTH

    value_width = (
        WIDTH - indent - label_width - 3
    )

    if value_width < 10:
        value_width = 10

    label = label[:label_width]

    # --------------------------------------------------------
    # VALORES CORTOS
    # --------------------------------------------------------

    if len(value) <= value_width:

        print(
            prefix +
            color(
                label.ljust(label_width),
                GRAY
            ) +
            color(" : ", DIM) +
            color(
                value,
                selected
            )
        )

        return

    # --------------------------------------------------------
    # VALORES EXTENSOS
    # --------------------------------------------------------

    print(
        prefix +
        color(
            label.ljust(label_width),
            GRAY
        ) +
        color(" : ", DIM)
    )

    print_wrapped_value(
        value,
        selected,
        indent + label_width + 3
    )


# ============================================================
#                   ÁRBOL DE INFORMACIÓN
# ============================================================

def render_tree(
    data,
    depth=0,
    category_color=CYAN
):

    if isinstance(data, dict):

        for key, value in data.items():

            label = str(key).replace(
                "_",
                " "
            ).upper()

            # ------------------------------------------------
            # OBJETOS
            # ------------------------------------------------

            if isinstance(value, dict):

                if not value:

                    print_pair(
                        label,
                        "{}",
                        category_color
                    )

                    continue

                selected = get_section_color(
                    label,
                    category_color
                )

                print_section(
                    label,
                    selected,
                    depth
                )

                print_line(
                    selected,
                    WIDTH - min(depth * 2, 12)
                )

                render_tree(
                    value,
                    depth + 1,
                    category_color
                )

            # ------------------------------------------------
            # LISTAS
            # ------------------------------------------------

            elif isinstance(value, list):

                if not value:

                    print_pair(
                        label,
                        "Sin elementos",
                        GRAY
                    )

                    continue

                selected = get_section_color(
                    label,
                    category_color
                )

                print_section(
                    label,
                    selected,
                    depth
                )

                print_line(
                    selected,
                    WIDTH - min(depth * 2, 12)
                )

                for index, item in enumerate(value, 1):

                    print_pair(
                        "ELEMENTO",
                        index,
                        selected
                    )

                    if isinstance(item, (dict, list)):

                        render_tree(
                            item,
                            depth + 1,
                            category_color
                        )

                    else:

                        print_pair(
                            "VALOR",
                            item,
                            selected
                        )

            # ------------------------------------------------
            # VALORES SIMPLES
            # ------------------------------------------------

            else:

                if key.lower() in (
                    "status",
                    "severity",
                    "enabled",
                    "closed",
                    "request_complete",
                    "response_prepared",
                    "has_pending_upload",
                    "has_replay_data",
                    "session_closed"
                ):

                    selected = terminal_color_for_status(
                        value
                    )

                else:

                    selected = category_color

                print_pair(
                    label,
                    value,
                    selected
                )


# ============================================================
#                     FICHA DEL EVENTO
# ============================================================

def render_record(result):

    category = result.get(
        "record_type",
        "OTHER"
    )

    event = result.get(
        "event",
        "UNKNOWN"
    )

    severity = result.get(
        "severity",
        "NOTICE"
    )

    selected = get_category_color(category)

    status_color = terminal_color_for_status(
        severity
    )

    # ========================================================
    # IDENTIFICACIÓN DEL EVENTO
    # ========================================================

    print()
    print_line(selected)

    print_center(
        "HCR SERVER EPRO DEV",
        selected
    )

    print_center(
        "EVENTO DETECTADO",
        WHITE
    )

    print_line(selected)

    print_pair(
        "EVENTO",
        event,
        selected
    )

    print_pair(
        "CATEGORÍA",
        category,
        selected
    )

    print_pair(
        "SEVERIDAD",
        severity,
        status_color
    )

    print_pair(
        "SERVICIO",
        result.get("service"),
        WHITE
    )

    print_pair(
        "RECIBIDO",
        result.get("received_at"),
        GRAY
    )

    print_line(selected)

    # ========================================================
    # ANÁLISIS DEL EVENTO
    # ========================================================

    analysis = result.get(
        "analysis",
        {}
    )

    if analysis:

        print_section(
            "ANÁLISIS DEL EVENTO",
            selected
        )

        print_line(selected)

        render_tree(
            analysis,
            category_color=selected
        )

    # ========================================================
    # DATOS ORIGINALES HCR
    # ========================================================

    original = result.get(
        "data",
        {}
    )

    if original:

        print()
        print_line(MAGENTA)

        print_center(
            "REGISTRO ORIGINAL",
            MAGENTA
        )

        print_section(
            "DATOS ORIGINALES HCR",
            MAGENTA
        )

        print_line(MAGENTA)

        # Los valores originales conservan el color
        # de su categoría, no todo queda en magenta.

        render_tree(
            original,
            category_color=selected
        )

    # ========================================================
    # FIN DEL REGISTRO
    # ========================================================

    print()
    print_line(selected)
    print()


# ============================================================
#                    PROCESAMIENTO JSON
# ============================================================

def process(line):

    line = line.strip()

    if not line:
        return

    start = line.find("{")

    if start < 0:

        result = build_raw_result(line)

        render_record(result)

        return

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

        render_record(result)

        return

    if not isinstance(data, dict):

        data = {
            "raw_data": data
        }

    result = build_result(data)

    render_record(result)


# ============================================================
#                      BUCLE PRINCIPAL
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

            render_record(result)

except KeyboardInterrupt:

    pass

' "$SERVICE"

    # --------------------------------------------------------
    # ESTADO DE LA TUBERÍA
    # --------------------------------------------------------

    local -a pipeline_statuses=("${PIPESTATUS[@]}")

    local journal_status="${pipeline_statuses[0]:-0}"
    local python_status="${pipeline_statuses[1]:-0}"

    set -e

    # --------------------------------------------------------
    # VALIDAR SALIDA
    # --------------------------------------------------------

    if (( python_status != 0 &&
          python_status != 130 &&
          python_status != 143 )); then

        error "El proceso Python del monitor terminó inesperadamente."
        exit "$python_status"
    fi

    if (( journal_status != 0 &&
          journal_status != 130 &&
          journal_status != 143 )); then

        error "Journalctl terminó inesperadamente."
        exit "$journal_status"
    fi

    printf '\n'
    success "Monitor detenido correctamente."
    printf '\n'
}

main "$@"
