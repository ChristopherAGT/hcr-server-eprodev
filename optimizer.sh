#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#              HCR SERVER | PARAMETER CONTROL
#                   GLOBAL EDITOR PRO
# ============================================================
#
# FUNCIONES:
#   - Detección automática de todos los servicios HCR.
#   - Edición global de parámetros multipuerto.
#   - Menú interactivo con valores actuales alineados.
#   - Pantalla independiente para cada opción seleccionada.
#   - Activación y desactivación global de Session Stats
#     y Diagnostics mediante una sola opción.
#   - Estado ON/OFF automático en el menú.
#   - Activación automática con intervalos de 60s.
#   - Validación de intervalos entre 10s y 300s.
#   - Conservación de los demás parámetros.
#   - Copias de seguridad de las configuraciones originales.
#   - Actualización automática de systemd.
#   - Reinicio de todos los servicios modificados.
#   - Resumen del estado general de los servicios.
#   - Spinner animado de seis puntos.
#   - Interfaz visual moderna con estados por color.
#   - Consultas reciclables sin duplicar líneas.
#   - Espera silenciosa de ENTER para volver al menú.
#
# ============================================================

# -------------------- CONFIGURACIÓN -------------------------

SERVICE_PREFIX="hcr-server"
SERVICE_DIR="/etc/systemd/system"

BACKUP_BASE="/var/backups/hcr-parameter-control"

MIN_FRAME=1
MAX_FRAME=262140

MIN_TIMEOUT=1
MAX_TIMEOUT=30

MIN_INTERVAL=10
MAX_INTERVAL=300

DEFAULT_INTERVAL="60s"

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
    printf '%b\n' "${DIM}${BLUE}────────────────────────────────────────────────────────${RESET}"
}

success() {
    printf '  %b✓%b  %b%s%b\n' "$GREEN" "$RESET" "$WHITE" "$1" "$RESET"
}

error() {
    printf '  %b✗%b  %b%s%b\n' "$RED" "$RESET" "$RED" "$1" "$RESET"
}

info() {
    printf '  %b›%b  %b%s%b\n' "$CYAN" "$RESET" "$WHITE" "$1" "$RESET"
}

warning() {
    printf '  %b!%b  %b%s%b\n' "$YELLOW" "$RESET" "$YELLOW" "$1" "$RESET"
}

section() {
    printf '\n'
    printf '  %b◆%b  %b%s%b\n' "$CYAN" "$RESET" "$WHITE$BOLD" "$1" "$RESET"
    printf '\n'
}

# -------------------- ENCABEZADO PRINCIPAL ------------------

header() {
    clear 2>/dev/null || true

    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="O P T I M I Z A D O R"

    printf '\n\n'

    printf '%*s%bHCR%b %bSERVER%b %bEPRO DEV%b\n' \
        "$(( (width - ${#title}) / 2 ))" '' \
        "$CYAN$BOLD" "$RESET" \
        "$WHITE$BOLD" "$RESET" \
        "$MAGENTA$BOLD"

    printf '%*s%b%s%b\n' \
        "$(( (width - ${#subtitle}) / 2 ))" '' \
        "$DIM$GRAY" "$subtitle" "$RESET"

    printf '\n'
    line
    printf '\n'

    printf '  %b●%b  %bMODIFICAR PARAMETROS DE HCR%b\n' \
        "$GREEN" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
        "$YELLOW" "$RESET" "$GRAY" "$RESET"

    printf '\n'
    line
    printf '\n'
}

# -------------------- ENCABEZADO DE EDICIÓN -----------------

edit_header() {
    clear 2>/dev/null || true

    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="E D I T O R   D E   P A R Á M E T R O"

    printf '\n\n'

    printf '%*s%bHCR%b %bSERVER%b %bEPRO DEV%b\n' \
        "$(( (width - ${#title}) / 2 ))" '' \
        "$CYAN$BOLD" "$RESET" \
        "$WHITE$BOLD" "$RESET" \
        "$MAGENTA$BOLD"

    printf '%*s%b%s%b\n' \
        "$(( (width - ${#subtitle}) / 2 ))" '' \
        "$MAGENTA$BOLD" "$subtitle" "$RESET"

    printf '\n'

    printf '%b%s%b\n' \
        "$DIM$MAGENTA" \
        "────────────────────────────────────────────────────────" \
        "$RESET"

    printf '\n'

    printf '  %b●%b  %bMODO MAESTRO%b\n' \
        "$MAGENTA" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
        "$YELLOW" "$RESET" "$MAGENTA$BOLD" "$RESET"

    printf '\n'

    printf '%b%s%b\n' \
        "$DIM$MAGENTA" \
        "────────────────────────────────────────────────────────" \
        "$RESET"

    printf '\n'
}

# -------------------- SPINNER --------------------------------

spinner() {
    local message="$1"
    shift

    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴')
    local pid
    local status=0
    local i=0

    (
        set +m
        "$@" >/dev/null 2>&1
    ) &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r\033[2K  %b%s%b  %b%s%b' \
            "$CYAN$BOLD" "${frames[i]}" "$RESET" \
            "$WHITE" "$message" "$RESET"

        i=$(( (i + 1) % 6 ))
        sleep 0.10
    done

    wait "$pid" || status=$?

    if (( status == 0 )); then
        printf '\r\033[2K  %b✓%b  %b%s%b\n' \
            "$GREEN$BOLD" "$RESET" "$WHITE" "$message" "$RESET"
    else
        printf '\r\033[2K  %b✗%b  %b%s%b\n' \
            "$RED$BOLD" "$RESET" "$RED" "$message" "$RESET"
    fi

    return "$status"
}

# -------------------- CONSULTAS RECICLABLES -----------------

ask_recyclable() {
    local prompt="$1"
    local default="$2"
    local variable_name="$3"
    local value

    printf '\033[s'
    printf '%b' "$prompt"

    IFS= read -r value || {
        printf '\n'
        return 1
    }

    value="${value:-$default}"

    printf -v "$variable_name" '%s' "$value"
}

# -------------------- ESPERA SILENCIOSA ---------------------

wait_for_enter() {
    local ignored
    IFS= read -r ignored || return 1
}

# -------------------- ESPERA Y RECICLAJE --------------------

wait_and_recycle() {
    local message="$1"
    local ignored

    warning "$message"

    IFS= read -r ignored || return 1

    printf '\033[u\033[J'
}

# -------------------- REQUISITOS ----------------------------

check_requirements() {
    local command

    for command in systemctl awk sed grep sort install cp mktemp python3; do
        if ! command -v "$command" >/dev/null 2>&1; then
            error "Falta una dependencia: $command"
            return 1
        fi
    done

    return 0
}

# -------------------- DETECCIÓN DE SERVICIOS ----------------

detect_services() {
    local file

    SERVICES=()

    shopt -s nullglob

    for file in "$SERVICE_DIR/${SERVICE_PREFIX}-"*.service; do
        [[ -f "$file" ]] || continue
        SERVICES+=("$file")
    done

    shopt -u nullglob

    if (( ${#SERVICES[@]} == 0 )); then
        error "No se encontraron servicios HCR multipuerto."
        return 1
    fi

    return 0
}

# -------------------- CONTAR SERVICIOS ----------------------

show_service_count() {
    printf '  %b●%b  %bServicios HCR detectados:%b %b%s%b\n' \
        "$CYAN" "$RESET" "$GRAY" "$RESET" \
        "$WHITE$BOLD" "${#SERVICES[@]}" "$RESET"
}

# -------------------- OBTENER VALORES ACTUALES ---------------

get_parameter_value() {
    local file="$1"
    local parameter="$2"

    python3 - "$file" "$parameter" <<'PY'
import re
import sys

path, parameter = sys.argv[1:3]
pattern = re.compile(
    r'(?<!\S)--' + re.escape(parameter) + r'(?:=|\s+)([^\s]+)'
)

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

values = []

for line in content.splitlines():
    if not re.match(r'^\s*ExecStart\s*=', line):
        continue

    matches = pattern.findall(line)
    values.extend(matches)

if len(values) != 1:
    sys.exit(1)

print(values[0])
PY
}

inspect_parameter() {
    local parameter="$1"
    local file
    local value
    local first_value=""
    local initialized=0
    local different=0

    for file in "${SERVICES[@]}"; do
        if ! value="$(get_parameter_value "$file" "$parameter")"; then
            error "No se pudo leer --${parameter} en $(basename "$file")."
            return 1
        fi

        if (( initialized == 0 )); then
            first_value="$value"
            initialized=1
        elif [[ "$value" != "$first_value" ]]; then
            different=1
        fi
    done

    CURRENT_VALUE="$first_value"
    VALUES_DIFFERENT="$different"

    return 0
}

# -------------------- VALORES DEL MENÚ -----------------------

get_display_value() {
    local parameter="$1"
    local file
    local value
    local first_value=""
    local initialized=0
    local different=0

    for file in "${SERVICES[@]}"; do

        if ! value="$(get_parameter_value "$file" "$parameter" 2>/dev/null)"; then
            printf '%s' "N/D"
            return 0
        fi

        if (( initialized == 0 )); then
            first_value="$value"
            initialized=1
        elif [[ "$value" != "$first_value" ]]; then
            different=1
        fi
    done

    if (( initialized == 0 )); then
        printf '%s' "N/D"
    elif (( different )); then
        printf '%s' "VARIOS"
    else
        printf '%s' "$first_value"
    fi
}

# -------------------- ESTADO SESSION STATS / DIAGNOSTICS ----

get_feature_state() {
    local file
    local stats_value
    local diagnostics_value
    local initialized=0
    local first_stats=""
    local first_diagnostics=""

    FEATURE_ENABLED=0
    FEATURE_VALUES_DIFFERENT=0

    for file in "${SERVICES[@]}"; do

        if ! stats_value="$(get_parameter_value "$file" "session-stats-interval")"; then
            error "No se pudo leer Session Stats en $(basename "$file")."
            return 1
        fi

        if ! diagnostics_value="$(get_parameter_value "$file" "diagnostics-interval")"; then
            error "No se pudo leer Diagnostics en $(basename "$file")."
            return 1
        fi

        if (( initialized == 0 )); then
            first_stats="$stats_value"
            first_diagnostics="$diagnostics_value"
            initialized=1
        elif [[ "$stats_value" != "$first_stats" ||
                "$diagnostics_value" != "$first_diagnostics" ]]; then
            FEATURE_VALUES_DIFFERENT=1
        fi

        if [[ "$stats_value" != "0" || "$diagnostics_value" != "0" ]]; then
            FEATURE_ENABLED=1
        fi
    done

    FEATURE_STATS_CURRENT="$first_stats"
    FEATURE_DIAGNOSTICS_CURRENT="$first_diagnostics"

    return 0
}

show_feature_status() {
    if ! get_feature_state >/dev/null 2>&1; then
        printf '%b[N/D]%b' "$YELLOW$BOLD" "$RESET"
        return 0
    fi

    if (( FEATURE_ENABLED )); then
        printf '%b[ON]%b' "$GREEN$BOLD" "$RESET"
    else
        printf '%b[OFF]%b' "$RED$BOLD" "$RESET"
    fi
}

# -------------------- VALIDACIÓN NUMÉRICA -------------------

valid_positive_integer() {
    local value="$1"

    [[ "$value" =~ ^[0-9]{1,9}$ ]] || return 1
    (( 10#$value > 0 ))
}

valid_nonnegative_integer() {
    local value="$1"

    [[ "$value" =~ ^[0-9]{1,9}$ ]] || return 1
    (( 10#$value >= 0 ))
}

# -------------------- VALIDACIÓN FRAME -----------------------

valid_frame() {
    local value="$1"

    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    (( ${#value} <= 6 )) || return 1
    (( 10#$value >= MIN_FRAME && 10#$value <= MAX_FRAME ))
}

# -------------------- VALIDACIÓN POLL TIMEOUT ----------------

valid_timeout() {
    local value="$1"
    local number

    value="${value,,}"
    value="${value%s}"

    [[ "$value" =~ ^[0-9]{1,2}$ ]] || return 1

    number=$((10#$value))

    (( number >= MIN_TIMEOUT && number <= MAX_TIMEOUT ))
}

# -------------------- NORMALIZAR TIMEOUT ---------------------

normalize_timeout() {
    local value="$1"

    value="${value,,}"
    value="${value%s}"

    PARAMETER_VALUE="${value}s"
}

# -------------------- VALIDACIÓN INTERVALOS ------------------

normalize_interval() {
    local value="$1"
    local number
    local unit
    local seconds

    value="${value,,}"

    if [[ "$value" =~ ^([0-9]{1,3})(s|m)?$ ]]; then
        number="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]:-s}"
    else
        return 1
    fi

    number=$((10#$number))

    if [[ "$unit" == "m" ]]; then
        seconds=$((number * 60))
    else
        seconds=$number
    fi

    (( seconds >= MIN_INTERVAL && seconds <= MAX_INTERVAL )) || return 1

    PARAMETER_VALUE="${seconds}s"

    return 0
}

# -------------------- COPIA DE SEGURIDAD --------------------

create_backup() {
    local file

    install -d -m 700 "$BACKUP_BASE"

    BACKUP_DIR="$(mktemp -d "${BACKUP_BASE}/backup-XXXXXXXX")"

    for file in "${SERVICES[@]}"; do
        cp -a "$file" "$BACKUP_DIR/"
    done
}

# -------------------- MODIFICAR SERVICIOS --------------------

modify_services() {
    local file
    local temp_file

    for file in "${SERVICES[@]}"; do

        temp_file="$(mktemp)"

        if ! python3 - "$file" "$temp_file" "$SELECTED_PARAMETER" "$PARAMETER_VALUE" <<'PY'
import re
import sys

source, destination, parameter, value = sys.argv[1:5]

pattern = re.compile(
    r'(?<!\S)(--' + re.escape(parameter) + r')(?:=|\s+)([^\s]+)'
)

with open(source, "r", encoding="utf-8") as f:
    lines = f.readlines()

total = 0
updated = []

for line in lines:
    if re.match(r'^\s*ExecStart\s*=', line):
        line, count = pattern.subn(
            lambda match: match.group(1) + " " + value,
            line
        )
        total += count

    updated.append(line)

if total != 1:
    sys.exit(1)

with open(destination, "w", encoding="utf-8") as f:
    f.writelines(updated)
PY
        then
            rm -f "$temp_file"
            return 1
        fi

        if ! install -o root -g root -m 644 "$temp_file" "$file"; then
            rm -f "$temp_file"
            return 1
        fi

        rm -f "$temp_file"
    done

    return 0
}

# -------------------- MODIFICAR AMBOS INTERVALOS -------------

modify_feature_services() {
    local file
    local temp_file

    for file in "${SERVICES[@]}"; do

        temp_file="$(mktemp)"

        if ! python3 - \
            "$file" \
            "$temp_file" \
            "$FEATURE_STATS_VALUE" \
            "$FEATURE_DIAGNOSTICS_VALUE" <<'PY'
import re
import sys

source, destination, stats_value, diagnostics_value = sys.argv[1:5]

parameters = {
    "session-stats-interval": stats_value,
    "diagnostics-interval": diagnostics_value,
}

with open(source, "r", encoding="utf-8") as f:
    lines = f.readlines()

totals = {key: 0 for key in parameters}
updated = []

for line in lines:
    if re.match(r'^\s*ExecStart\s*=', line):

        for parameter, value in parameters.items():

            pattern = re.compile(
                r'(?<!\S)(--' + re.escape(parameter) + r')(?:=|\s+)([^\s]+)'
            )

            line, count = pattern.subn(
                lambda match: match.group(1) + " " + value,
                line
            )

            totals[parameter] += count

    updated.append(line)

if any(total != 1 for total in totals.values()):
    sys.exit(1)

with open(destination, "w", encoding="utf-8") as f:
    f.writelines(updated)
PY
        then
            rm -f "$temp_file"
            return 1
        fi

        if ! install -o root -g root -m 644 "$temp_file" "$file"; then
            rm -f "$temp_file"
            return 1
        fi

        rm -f "$temp_file"
    done

    return 0
}

# -------------------- RESTAURAR COPIAS -----------------------

rollback_services() {
    local file
    local backup_file

    for file in "${SERVICES[@]}"; do
        backup_file="$BACKUP_DIR/$(basename "$file")"

        if [[ -f "$backup_file" ]]; then
            cp -a "$backup_file" "$file" || true
        fi
    done

    systemctl daemon-reload >/dev/null 2>&1 || true
}

# -------------------- ACTUALIZAR SYSTEMD ---------------------

reload_systemd() {
    systemctl daemon-reload
}

# -------------------- REINICIAR SERVICIOS --------------------

restart_services() {
    local file
    local service
    local failed=0

    for file in "${SERVICES[@]}"; do
        service="$(basename "$file")"

        if ! systemctl restart "$service" >/dev/null 2>&1; then
            failed=1
        fi
    done

    return "$failed"
}

# -------------------- RESUMEN ESTADO DE SERVICIOS ------------

show_service_health() {
    local file
    local service
    local active_count=0
    local failed_count=0
    local total_count="${#SERVICES[@]}"

    for file in "${SERVICES[@]}"; do
        service="$(basename "$file")"

        if systemctl is-active --quiet "$service"; then
            active_count=$((active_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
    done

    printf '  %bTotal de servicios:%b          %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE$BOLD" "$total_count" "$RESET"

    printf '  %bServicios funcionando:%b      %b%s%b\n' \
        "$GRAY" "$RESET" "$GREEN$BOLD" "$active_count" "$RESET"

    printf '  %bServicios con problemas:%b     %b%s%b\n' \
        "$GRAY" "$RESET" "$RED$BOLD" "$failed_count" "$RESET"

    printf '\n'

    if (( failed_count > 0 )); then
        warning "Algunos servicios requieren atención."
    else
        success "Todos los servicios están funcionando correctamente."
    fi

    return 0
}

# -------------------- RESUMEN FINAL -------------------------

show_summary() {
    local message
    local width=58

    printf '\n'
    line
    section "RESUMEN DE CONFIGURACIÓN"

    printf '  %b%-30s%b %b%s%b\n' \
        "$CYAN" "${SELECTED_LABEL}:" "$RESET" \
        "$WHITE$BOLD" "$PARAMETER_VALUE" "$RESET"

    printf '\n'
    line
    section "ESTADO GENERAL DE LOS SERVICIOS"

    show_service_health

    printf '\n'
    info "Copia de seguridad: $BACKUP_DIR"

    printf '\n'
    line
    printf '\n'

    local failed_count=0

    for file in "${SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$(basename "$file")"; then
            failed_count=1
            break
        fi
    done

    if (( failed_count > 0 )); then
        message="ACTUALIZACIÓN CON ADVERTENCIAS"
        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$YELLOW$BOLD" "$message" "$RESET"
    else
        message="ACTUALIZACIÓN COMPLETADA"
        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$GREEN$BOLD" "$message" "$RESET"
    fi

    printf '\n'
    line
    printf '\n'
}

# -------------------- RESUMEN SESSION STATS / DIAGNOSTICS ---

show_feature_summary() {
    local message
    local width=58
    local failed_count=0
    local file

    printf '\n'
    line
    section "RESUMEN DE CONFIGURACIÓN"

    printf '  %bSession Stats:%b              %b%s%b\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$FEATURE_STATS_VALUE" "$RESET"

    printf '  %bDiagnostics:%b                %b%s%b\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$FEATURE_DIAGNOSTICS_VALUE" "$RESET"

    if [[ "$FEATURE_STATS_VALUE" == "0" &&
          "$FEATURE_DIAGNOSTICS_VALUE" == "0" ]]; then
        printf '  %bEstado general:%b             %b[OFF]%b\n' \
            "$GRAY" "$RESET" "$RED$BOLD" "$RESET"
    else
        printf '  %bEstado general:%b             %b[ON]%b\n' \
            "$GRAY" "$RESET" "$GREEN$BOLD" "$RESET"
    fi

    printf '\n'
    line
    section "ESTADO GENERAL DE LOS SERVICIOS"

    show_service_health

    printf '\n'
    info "Copia de seguridad: $BACKUP_DIR"

    for file in "${SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$(basename "$file")"; then
            failed_count=1
            break
        fi
    done

    printf '\n'
    line
    printf '\n'

    if (( failed_count > 0 )); then
        message="ACTUALIZACIÓN CON ADVERTENCIAS"
        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$YELLOW$BOLD" "$message" "$RESET"
    else
        message="ACTUALIZACIÓN COMPLETADA"
        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$GREEN$BOLD" "$message" "$RESET"
    fi

    printf '\n'
    line
    printf '\n'
}

# -------------------- ACTIVAR / DESACTIVAR AMBOS -------------

configure_feature_toggle() {

    SELECTED_LABEL="Session Stats & Diagnostics"
    edit_header

    if ! get_feature_state; then
        error "No se pudo determinar el estado de los parámetros."
        return 1
    fi

    section "CONFIGURACIÓN DE FUNCIONES"

    if (( FEATURE_ENABLED )); then

        FEATURE_STATS_VALUE="0"
        FEATURE_DIAGNOSTICS_VALUE="0"

        info "Estado actual: ACTIVADO"
        warning "Se desactivarán ambos parámetros."

    else

        FEATURE_STATS_VALUE="$DEFAULT_INTERVAL"
        FEATURE_DIAGNOSTICS_VALUE="$DEFAULT_INTERVAL"

        info "Estado actual: DESACTIVADO"
        success "Se activarán ambos parámetros."

    fi

    printf '\n'

    printf '  %bSession Stats:%b              %b%s%b\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$FEATURE_STATS_VALUE" "$RESET"

    printf '  %bDiagnostics:%b                %b%s%b\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$FEATURE_DIAGNOSTICS_VALUE" "$RESET"

    printf '\n'
    line
    section "APLICANDO CONFIGURACIÓN"

    if ! spinner "Creando copias de seguridad" create_backup; then
        error "No se pudieron crear las copias de seguridad."
        return 1
    fi

    if ! spinner "Actualizando parámetros de los servicios" modify_feature_services; then
        error "No se pudieron modificar todos los servicios."
        warning "Restaurando las configuraciones originales..."
        rollback_services
        return 1
    fi

    if ! spinner "Actualizando configuración de systemd" reload_systemd; then
        error "No se pudo actualizar systemd."
        warning "Restaurando las configuraciones originales..."
        rollback_services
        return 1
    fi

    if ! spinner "Reiniciando servicios HCR" restart_services; then
        warning "Uno o más servicios no pudieron reiniciarse."
    fi

    show_feature_summary

    return 0
}

# -------------------- CONFIGURAR PARÁMETRO ------------------

configure_parameter() {
    local option="$1"
    local input
    local input_default
    local prompt
    local validation_error

    case "$option" in
        1)
            SELECTED_PARAMETER="max-connections"
            SELECTED_LABEL="Max Connections"
            validation_error="Introduce un número entero mayor que cero."
            ;;

        2)
            SELECTED_PARAMETER="max-sessions"
            SELECTED_LABEL="Max Sessions"
            validation_error="Introduce un número entero mayor que cero."
            ;;

        3)
            SELECTED_PARAMETER="max-sessions-per-ip"
            SELECTED_LABEL="Max Sessions Per IP"
            validation_error="Introduce un número entero mayor que cero."
            ;;

        4)
            SELECTED_PARAMETER="max-download-frame"
            SELECTED_LABEL="Max Download Frame"
            validation_error="Frame inválido. Introduce un valor entre 1 y 262140."
            ;;

        5)
            SELECTED_PARAMETER="download-poll-timeout"
            SELECTED_LABEL="Download Poll Timeout"
            validation_error="Poll Timeout inválido. Introduce un valor entre 1s y 30s."
            ;;

        7)
            SELECTED_PARAMETER="session-stats-interval"
            SELECTED_LABEL="Session Stats Interval"
            validation_error="Intervalo inválido. Introduce un valor entre 10s y 300s."
            ;;

        8)
            SELECTED_PARAMETER="diagnostics-interval"
            SELECTED_LABEL="Diagnostics Interval"
            validation_error="Intervalo inválido. Introduce un valor entre 10s y 300s."
            ;;

        *)
            return 1
            ;;
    esac

    if ! inspect_parameter "$SELECTED_PARAMETER"; then
        return 1
    fi

    edit_header

    section "CONFIGURACIÓN DEL PARÁMETRO"

    printf '  %b⌬%b  %b%s%b\n' \
        "$MAGENTA$BOLD" "$RESET" \
        "$WHITE$BOLD" "$SELECTED_LABEL" "$RESET"

    printf '\n'

    if (( VALUES_DIFFERENT )); then
        warning "Los servicios tienen valores actuales diferentes."
        info "Valor de referencia: $CURRENT_VALUE"
        info "El nuevo valor se aplicará globalmente."
    else
        printf '  %b⦿%b  %bValor actual:%b %b%s%b\n' \
            "$CYAN$BOLD" "$RESET" \
            "$GRAY" "$RESET" \
            "$CYAN$BOLD" "$CURRENT_VALUE" "$RESET"
    fi

    printf '\n'
    line
    printf '\n'

    input_default="$CURRENT_VALUE"

    if [[ "$option" == "7" || "$option" == "8" ]]; then
        if [[ "$CURRENT_VALUE" == "0" ]]; then
            input_default="$DEFAULT_INTERVAL"
        fi
    fi

    prompt="  ${MAGENTA}${BOLD}Nuevo valor${RESET} ${DIM}[${input_default}]${RESET}: "

    while true; do
        ask_recyclable "$prompt" "$input_default" input || return 1

        case "$option" in
            1|2|3)
                if valid_positive_integer "$input"; then
                    PARAMETER_VALUE=$((10#$input))
                    printf '\033[u\033[2K'
                    break
                fi
                ;;

            4)
                if valid_frame "$input"; then
                    PARAMETER_VALUE=$((10#$input))
                    printf '\033[u\033[2K'
                    break
                fi
                ;;

            5)
                if valid_timeout "$input"; then
                    normalize_timeout "$input"
                    printf '\033[u\033[2K'
                    break
                fi
                ;;

            7|8)
                if normalize_interval "$input"; then
                    printf '\033[u\033[2K'
                    break
                fi
                ;;
        esac

        wait_and_recycle "$validation_error" || return 1
    done

    printf '\n'
    line
    section "APLICANDO CONFIGURACIÓN"

    if ! spinner "Creando copias de seguridad" create_backup; then
        error "No se pudieron crear las copias de seguridad."
        return 1
    fi

    if ! spinner "Actualizando parámetros de los servicios" modify_services; then
        error "No se pudieron modificar todos los servicios."
        warning "Restaurando las configuraciones originales..."
        rollback_services
        return 1
    fi

    if ! spinner "Actualizando configuración de systemd" reload_systemd; then
        error "No se pudo actualizar systemd."
        warning "Restaurando las configuraciones originales..."
        rollback_services
        return 1
    fi

    if ! spinner "Reiniciando servicios HCR" restart_services; then
        warning "Uno o más servicios no pudieron reiniciarse."
    fi

    show_summary

    return 0
}

# -------------------- MENÚ PRINCIPAL ------------------------

show_menu() {
    local value

    header
    show_service_count

    printf '\n'
    line
    printf '\n'

    # Título y encabezado de valores en la misma línea.
    printf '  %b◆%b  %b%-34s%b %b%15s%b\n\n' \
        "$CYAN" "$RESET" \
        "$WHITE$BOLD" "SELECCIONA EL PARÁMETRO" "$RESET" \
        "$DIM$GRAY" "VALOR ACTUAL" "$RESET"

    value="$(get_display_value "max-connections")"
    printf '  %b[1]%b  %-32s %b%14.14s%b\n' \
        "$CYAN$BOLD" "$RESET" \
        "Max Connections" \
        "$CYAN$BOLD" "$value" "$RESET"

    value="$(get_display_value "max-sessions")"
    printf '  %b[2]%b  %-32s %b%14.14s%b\n' \
        "$CYAN$BOLD" "$RESET" \
        "Max Sessions" \
        "$CYAN$BOLD" "$value" "$RESET"

    value="$(get_display_value "max-sessions-per-ip")"
    printf '  %b[3]%b  %-32s %b%14.14s%b\n' \
        "$CYAN$BOLD" "$RESET" \
        "Max Sessions Per IP" \
        "$CYAN$BOLD" "$value" "$RESET"

    value="$(get_display_value "max-download-frame")"
    printf '  %b[4]%b  %-32s %b%14.14s%b\n' \
        "$CYAN$BOLD" "$RESET" \
        "Max Download Frame" \
        "$CYAN$BOLD" "$value" "$RESET"

    value="$(get_display_value "download-poll-timeout")"
    printf '  %b[5]%b  %-32s %b%14.14s%b\n' \
        "$CYAN$BOLD" "$RESET" \
        "Download Poll Timeout" \
        "$CYAN$BOLD" "$value" "$RESET"

    # Estado de Session Stats y Diagnostics, junto a su opción.
    printf '  %b[6]%b  %bSession Stats & Diagnostics%b ' \
        "$CYAN$BOLD" "$RESET" \
        "$WHITE" "$RESET"

    show_feature_status
    printf '\n'

    # Los intervalos solo aparecen cuando la función está ON.
    if (( FEATURE_ENABLED )); then

        value="$(get_display_value "session-stats-interval")"
        printf '  %b[7]%b  %-32s %b%14.14s%b\n' \
            "$CYAN$BOLD" "$RESET" \
            "Session Stats Interval" \
            "$CYAN$BOLD" "$value" "$RESET"

        value="$(get_display_value "diagnostics-interval")"
        printf '  %b[8]%b  %-32s %b%14.14s%b\n' \
            "$CYAN$BOLD" "$RESET" \
            "Diagnostics Interval" \
            "$CYAN$BOLD" "$value" "$RESET"
    fi

    printf '\n'
    line
    printf '\n'

    printf '  %b[0]%b  Salir\n' "$RED$BOLD" "$RESET"

    printf '\n'
    line
    printf '\n'
}

# -------------------- EJECUCIÓN PRINCIPAL -------------------

main() {
    local option

    if (( EUID != 0 )); then
        printf '%b✗%b  %bEjecuta el editor como root.%b\n' \
            "$RED" "$RESET" "$WHITE" "$RESET"
        exit 1
    fi

    if ! check_requirements; then
        exit 1
    fi

    if ! detect_services; then
        exit 1
    fi

    while true; do
        show_menu

        printf '  %bSelecciona una opción:%b ' "$CYAN$BOLD" "$RESET"

        if ! IFS= read -r option; then
            printf '\n'
            break
        fi

        case "$option" in
            1|2|3|4|5)
                if ! configure_parameter "$option"; then
                    warning "No se pudo completar la operación."
                fi

                wait_for_enter || break
                ;;

            7|8)
                if ! get_feature_state; then
                    error "No se pudo determinar el estado de los parámetros."
                elif (( ! FEATURE_ENABLED )); then
                    error "Esta opción no está disponible mientras Session Stats y Diagnostics estén desactivados."
                else
                    if ! configure_parameter "$option"; then
                        warning "No se pudo completar la operación."
                    fi
                fi

                wait_for_enter || break
                ;;

            6)
                if ! configure_feature_toggle; then
                    warning "No se pudo completar la operación."
                fi

                wait_for_enter || break
                ;;

            0)
                printf '\n'
                success "Saliendo del editor de parámetros HCR."
                printf '\n'
                break
                ;;

            *)
                warning "Opción no válida."
                sleep 1
                ;;
        esac
    done
}

main "$@"
