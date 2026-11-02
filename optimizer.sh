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
#   - Validación cruzada de Max Sessions y Max Sessions Per IP.
#   - Ajuste automático autorizado de Max Sessions Per IP.
#   - Validación individual de todos los servicios HCR.
#   - Conservación de los demás parámetros.
#   - Copias de seguridad temporales por parámetro y fecha.
#   - Respaldo completo de todos los servicios detectados.
#   - Restauración automática ante fallos críticos.
#   - Verificación individual de todos los servicios.
#   - Eliminación automática de respaldos tras verificar.
#   - Conservación del respaldo si falla la restauración.
#   - Actualización automática de systemd.
#   - Reinicio de todos los servicios modificados.
#   - Verificación de los parámetros realmente aplicados.
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

BACKUP_BASE="/var/backups/hcr-parameters"
BACKUP_DIR=""

# Estado de cancelación de la edición.
CONFIG_CANCELLED=0

MIN_CONNECTIONS=1024
MAX_CONNECTIONS=32768

MIN_SESSIONS=16
MAX_SESSIONS=32768

MIN_SESSIONS_PER_IP=1

MIN_FRAME=1
MAX_FRAME=262140

MIN_TIMEOUT=1
MAX_TIMEOUT=30

MIN_INTERVAL=10
MAX_INTERVAL=300

DEFAULT_MAX_CONNECTIONS="2048"
DEFAULT_MAX_SESSIONS="32"
DEFAULT_MAX_SESSIONS_PER_IP="16"
DEFAULT_MAX_DOWNLOAD_FRAME="16384"
DEFAULT_DOWNLOAD_POLL_TIMEOUT="25s"

DEFAULT_INTERVAL="60s"

# Estado de validación cruzada.
MAX_ALLOWED_SESSIONS_PER_IP=0
SESSIONS_PER_IP_ADJUSTED=0

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

# Separador exclusivo de las pantallas de edición.
edit_line() {
    printf '%b\n' "${DIM}${MAGENTA}────────────────────────────────────────────────────────${RESET}"
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
        "$MAGENTA$BOLD" "$RESET"

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
        "$MAGENTA$BOLD" "$RESET"

    printf '%*s%b%s%b\n' \
        "$(( (width - ${#subtitle}) / 2 ))" '' \
        "$MAGENTA$BOLD" "$subtitle" "$RESET"

    printf '\n'

    edit_line

    printf '\n'

    printf '  %b●%b  %bMODO MAESTRO%b\n' \
        "$MAGENTA" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
        "$YELLOW" "$RESET" "$MAGENTA$BOLD" "$RESET"

    printf '\n'

    edit_line

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

    printf '\033[2A\033[2K'
    printf '\033[1A\033[2K'
}

# -------------------- REQUISITOS ----------------------------

check_requirements() {
    local command

    for command in systemctl awk sed grep sort install cp mktemp python3 date rm; do
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

# -------------------- NORMALIZAR ENTERO ---------------------

normalize_integer() {
    local value="$1"

    PARAMETER_VALUE=$((10#$value))
}

# -------------------- VALIDAR MAX CONNECTIONS ----------------

valid_max_connections() {
    local value="$1"
    local number

    [[ "$value" =~ ^[0-9]{1,5}$ ]] || return 1

    number=$((10#$value))

    (( number >= MIN_CONNECTIONS && number <= MAX_CONNECTIONS ))
}

# -------------------- VALIDAR MAX SESSIONS -------------------

valid_max_sessions() {
    local value="$1"
    local number

    [[ "$value" =~ ^[0-9]{1,5}$ ]] || return 1

    number=$((10#$value))

    (( number >= MIN_SESSIONS && number <= MAX_SESSIONS ))
}

# -------------------- VALIDAR MAX SESSIONS PER IP ------------

valid_max_sessions_per_ip() {
    local value="$1"
    local maximum="$2"
    local number

    [[ "$value" =~ ^[0-9]{1,5}$ ]] || return 1

    number=$((10#$value))

    (( number >= MIN_SESSIONS_PER_IP &&
       number <= maximum ))
}

# -------------------- OBTENER MÍNIMO ENTRE SERVICIOS ---------

get_minimum_parameter_value() {
    local parameter="$1"
    local file
    local value
    local number
    local minimum=""

    for file in "${SERVICES[@]}"; do

        if ! value="$(get_parameter_value "$file" "$parameter")"; then
            error "No se pudo leer --${parameter} en $(basename "$file")."
            return 1
        fi

        if [[ ! "$value" =~ ^[0-9]{1,9}$ ]]; then
            error "Valor numérico no válido en $(basename "$file")."
            return 1
        fi

        number=$((10#$value))

        if [[ -z "$minimum" ]] || (( number < minimum )); then
            minimum="$number"
        fi
    done

    [[ -n "$minimum" ]] || return 1

    MAX_ALLOWED_SESSIONS_PER_IP="$minimum"

    return 0
}

# -------------------- CONFIRMAR AJUSTE AUTOMÁTICO ------------

confirm_sessions_per_ip_adjustment() {
    local answer
    local pause
    local file
    local value
    local number

    edit_header

    printf '  %b◆%b  %bVALIDACIÓN DE PARÁMETROS%b\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '\n'

    warning "El nuevo MAX SESSIONS está por debajo de MAX SESSIONS PER IP."

    printf '\n'

    printf '  %bMAX SESSIONS:%b %b%s%b\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$PARAMETER_VALUE" "$RESET"

    printf '\n'

    printf '  %bSERVICIOS QUE REQUIEREN AJUSTE:%b\n\n' "$GRAY" "$RESET"

    for file in "${SERVICES[@]}"; do

        value="$(get_parameter_value "$file" "max-sessions-per-ip")" || return 1
        [[ "$value" =~ ^[0-9]+$ ]] || return 1

        number=$((10#$value))

        if (( number > PARAMETER_VALUE )); then
            printf '  %b›%b  %-28s %b%s → %s%b\n' \
                "$YELLOW" "$RESET" \
                "$(basename "$file")" \
                "$WHITE$BOLD" "$value" "$PARAMETER_VALUE" "$RESET"
        fi
    done

    printf '\n'
    edit_line
    printf '\n'

    warning "Es necesario ajustar los valores que superan el nuevo límite."

    printf '\n'

    info "Se conservarán los valores que ya sean válidos."
    info "No se aumentará ningún valor de MAX SESSIONS PER IP."

    printf '\n'
    edit_line
    printf '\n'

    printf '  %b◆%b  %bACCIONES%b\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '\n'

    printf '  %b[1]%b  Aceptar y continuar\n' "$GREEN$BOLD" "$RESET"
    printf '  %b[0]%b  Salir\n' "$RED$BOLD" "$RESET"

    printf '\n'
    edit_line
    printf '\n'

    # -------------------- CONSULTA RECICLABLE ----------------

    # Mostrar la pregunta inicial.
    printf '  %bSelecciona una opción:%b ' \
        "$CYAN$BOLD" "$RESET"

    while true; do

        # Esperar la opción y ENTER.
        if ! IFS= read -r answer; then
            return 1
        fi

        case "$answer" in

            1)
                # Limpiar la línea de entrada.
                printf '\033[2K\r'

                # Limpiar la pregunta.
                printf '\033[1A\033[2K\r\n'

                return 0
                ;;

            0)
                # Limpiar la línea de entrada.
                printf '\033[2K\r'

                # Limpiar la pregunta.
                printf '\033[1A\033[2K\r\n'

                CONFIG_CANCELLED=1
                return 0
                ;;

            *)
                # Mostrar advertencia debajo de la pregunta.
                printf '\033[2K\r'
                warning "Opción no válida."

                # Esperar ENTER sin mostrar otro mensaje.
                if ! IFS= read -r pause; then
                    return 1
                fi

                # Limpiar la pregunta con la entrada incorrecta.
                printf '\033[3A\r\033[2K'

                # Limpiar la advertencia.
                printf '\033[1B\r\033[2K'

                # Limpiar la línea utilizada para esperar ENTER.
                printf '\033[1B\r\033[2K'

                # Regresar a la posición original.
                printf '\033[2A\r'

                # Mostrar nuevamente la pregunta.
                printf '  %bSelecciona una opción:%b ' \
                    "$CYAN$BOLD" "$RESET"
                ;;
        esac

    done
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

# -------------------- PREPARAR COPIA DE SEGURIDAD ------------

prepare_backup_target() {
    local backup_name="$1"
    local timestamp

    install -d -m 700 "$BACKUP_BASE" || return 1

    timestamp="$(date '+%Y%m%d-%H%M%S')"

    BACKUP_DIR="$(mktemp -d \
        "${BACKUP_BASE}/${backup_name}-${timestamp}-XXXXXXXX")" || return 1

    chmod 700 "$BACKUP_DIR"

    return 0
}

# -------------------- CREAR COPIA DE SEGURIDAD ---------------

create_backup() {
    local file

    [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || return 1

    for file in "${SERVICES[@]}"; do
        cp -a "$file" "$BACKUP_DIR/" || return 1
    done

    return 0
}

# -------------------- ELIMINAR COPIA DE SEGURIDAD ------------

cleanup_backup() {

    [[ -n "$BACKUP_DIR" ]] || return 0
    [[ -d "$BACKUP_DIR" ]] || {
        BACKUP_DIR=""
        return 0
    }

    case "$BACKUP_DIR" in
        "$BACKUP_BASE"/*)
            ;;
        *)
            error "Ruta de copia de seguridad no válida. No se eliminará."
            return 1
            ;;
    esac

    if [[ "$BACKUP_DIR" == "$BACKUP_BASE" ]]; then
        error "Ruta de respaldo protegida. No se eliminará."
        return 1
    fi

    if ! rm -rf -- "$BACKUP_DIR"; then
        error "No se pudo eliminar la copia de seguridad."
        return 1
    fi

    BACKUP_DIR=""

    return 0
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

# -------------------- MODIFICAR SESSIONS Y PER IP ------------

modify_sessions_services() {
    local file
    local temp_file

    for file in "${SERVICES[@]}"; do

        temp_file="$(mktemp)"

        if ! python3 - \
            "$file" \
            "$temp_file" \
            "$PARAMETER_VALUE" <<'PY'
import re
import sys

source, destination, new_sessions = sys.argv[1:4]
new_sessions = int(new_sessions)

parameters = {
    "max-sessions": 0,
    "max-sessions-per-ip": 0,
}

patterns = {
    parameter: re.compile(
        r'(?<!\S)(--' + re.escape(parameter) + r')(?:=|\s+)([^\s]+)'
    )
    for parameter in parameters
}

with open(source, "r", encoding="utf-8") as f:
    lines = f.readlines()

updated = []

for line in lines:

    if re.match(r'^\s*ExecStart\s*=', line):

        for parameter, pattern in patterns.items():

            matches = list(pattern.finditer(line))

            if len(matches) != 1:
                sys.exit(1)

            match = matches[0]

            try:
                current_value = int(match.group(2))
            except ValueError:
                sys.exit(1)

            if parameter == "max-sessions":
                replacement = str(new_sessions)

            else:
                if current_value < 1:
                    sys.exit(1)

                replacement = (
                    str(new_sessions)
                    if current_value > new_sessions
                    else str(current_value)
                )

            line = pattern.sub(
                lambda item, replacement=replacement:
                    item.group(1) + " " + replacement,
                line,
                count=1
            )

            parameters[parameter] += 1

    updated.append(line)

if any(total != 1 for total in parameters.values()):
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

# -------------------- VERIFICAR PARÁMETROS APLICADOS ---------

verify_parameter_values() {
    local file
    local value
    local sessions
    local per_ip

    for file in "${SERVICES[@]}"; do

        if [[ "$SELECTED_PARAMETER" == "max-sessions" ]]; then

            sessions="$(get_parameter_value "$file" "max-sessions")" || return 1
            per_ip="$(get_parameter_value "$file" "max-sessions-per-ip")" || return 1

            [[ "$sessions" =~ ^[0-9]+$ ]] || return 1
            [[ "$per_ip" =~ ^[0-9]+$ ]] || return 1

            (( 10#$sessions == PARAMETER_VALUE )) || return 1
            (( 10#$per_ip >= MIN_SESSIONS_PER_IP )) || return 1
            (( 10#$per_ip <= 10#$sessions )) || return 1

        elif [[ "$SELECTED_PARAMETER" == "max-sessions-per-ip" ]]; then

            sessions="$(get_parameter_value "$file" "max-sessions")" || return 1
            per_ip="$(get_parameter_value "$file" "max-sessions-per-ip")" || return 1

            [[ "$sessions" =~ ^[0-9]+$ ]] || return 1
            [[ "$per_ip" =~ ^[0-9]+$ ]] || return 1

            (( 10#$per_ip == PARAMETER_VALUE )) || return 1
            (( 10#$per_ip >= MIN_SESSIONS_PER_IP )) || return 1
            (( 10#$per_ip <= 10#$sessions )) || return 1

        else

            value="$(get_parameter_value "$file" "$SELECTED_PARAMETER")" || return 1

            [[ "$value" == "$PARAMETER_VALUE" ]] || return 1

        fi
    done

    return 0
}

# -------------------- RESTAURAR COPIAS -----------------------

rollback_services() {
    local file
    local backup_file
    local failed=0

    if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]]; then
        error "No se encontró el respaldo para restaurar."
        return 1
    fi

    for file in "${SERVICES[@]}"; do
        backup_file="$BACKUP_DIR/$(basename "$file")"

        if [[ ! -f "$backup_file" ]]; then
            error "Falta el respaldo de $(basename "$file")."
            failed=1
            continue
        fi

        if ! cp -a -- "$backup_file" "$file"; then
            error "No se pudo restaurar $(basename "$file")."
            failed=1
        fi
    done

    if (( failed )); then
        return 1
    fi

    if ! systemctl daemon-reload >/dev/null 2>&1; then
        error "No se pudo actualizar systemd después de restaurar."
        return 1
    fi

    return 0
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

# -------------------- VERIFICAR SERVICIOS -------------------

verify_services() {
    local file
    local service
    local failed=0

    for file in "${SERVICES[@]}"; do
        service="$(basename "$file")"

        if ! systemctl is-active --quiet "$service"; then
            failed=1
        fi
    done

    return "$failed"
}

# -------------------- RECUPERACIÓN AUTOMÁTICA ----------------

recover_configuration() {

    warning "Se detectó un problema. Iniciando restauración automática..."

    if ! spinner "Restaurando configuraciones originales" rollback_services; then
        error "No se pudieron restaurar todas las configuraciones."
        warning "La copia de seguridad se conservará para recuperación manual."
        info "Respaldo conservado: $BACKUP_DIR"
        return 1
    fi

    if ! spinner "Reiniciando servicios con configuración original" restart_services; then
        error "No se pudieron reiniciar todos los servicios restaurados."
        warning "La copia de seguridad se conservará para recuperación manual."
        info "Respaldo conservado: $BACKUP_DIR"
        return 1
    fi

    if ! spinner "Verificando servicios restaurados" verify_services; then
        error "La restauración no logró recuperar todos los servicios."
        warning "La copia de seguridad se conservará para recuperación manual."
        info "Respaldo conservado: $BACKUP_DIR"
        return 1
    fi

    success "Todos los servicios fueron restaurados correctamente."

    if cleanup_backup; then
        success "Copia de seguridad temporal eliminada."
    else
        warning "La copia de seguridad permanece disponible."
        info "Respaldo conservado: $BACKUP_DIR"
    fi

    return 0
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

    printf '  %bServicios funcionando:%b       %b%s%b\n' \
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
    edit_line
    section "RESUMEN DE CONFIGURACIÓN"

    printf '  %b%-28s%b %b%s%b\n' \
        "$CYAN" "${SELECTED_LABEL}:" "$RESET" \
        "$WHITE$BOLD" "$PARAMETER_VALUE" "$RESET"

    if (( SESSIONS_PER_IP_ADJUSTED )); then
        printf '\n'
        warning "MAX SESSIONS PER IP fue ajustado automáticamente."
        info "Se conservaron los valores que ya cumplían el límite."
    fi

    printf '\n'
    edit_line
    section "ESTADO GENERAL DE LOS SERVICIOS"

    show_service_health

    printf '\n'

    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        info "Copia de seguridad conservada: $BACKUP_DIR"
    else
        info "Copia de seguridad: eliminada tras verificar los servicios."
    fi

    printf '\n'
    edit_line
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
    edit_line
    printf '\n'
}

# -------------------- RESUMEN SESSION STATS / DIAGNOSTICS ---

show_feature_summary() {
    local message
    local width=58
    local failed_count=0
    local file

    printf '\n'
    edit_line
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
    edit_line
    section "ESTADO GENERAL DE LOS SERVICIOS"

    show_service_health

    printf '\n'

    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        info "Copia de seguridad conservada: $BACKUP_DIR"
    else
        info "Copia de seguridad: eliminada tras verificar los servicios."
    fi

    for file in "${SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$(basename "$file")"; then
            failed_count=1
            break
        fi
    done

    printf '\n'
    edit_line
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
    edit_line
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
    edit_line
    section "APLICANDO CONFIGURACIÓN"

    if ! prepare_backup_target "session-stats-diagnostics"; then
        error "No se pudo preparar el directorio de respaldo."
        return 1
    fi

    if ! spinner "Creando copias de seguridad" create_backup; then
        error "No se pudieron crear las copias de seguridad."
        info "Respaldo conservado: $BACKUP_DIR"
        return 1
    fi

    if ! spinner "Actualizando parámetros de los servicios" modify_feature_services; then
        error "No se pudieron modificar todos los servicios."
        recover_configuration || true
        return 1
    fi

    if ! spinner "Actualizando configuración de systemd" reload_systemd; then
        error "No se pudo actualizar systemd."
        recover_configuration || true
        return 1
    fi

    if ! spinner "Reiniciando servicios HCR" restart_services; then
        error "No se pudieron reiniciar todos los servicios."
        recover_configuration || true
        return 1
    fi

    if ! spinner "Verificando estado de los servicios" verify_services; then
        error "Se detectaron servicios con problemas después del reinicio."
        recover_configuration || true
        return 1
    fi

    if cleanup_backup; then
        success "Copia de seguridad temporal eliminada."
    else
        warning "No se pudo eliminar la copia de seguridad."
        info "Respaldo conservado: $BACKUP_DIR"
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

    CONFIG_CANCELLED=0
    SESSIONS_PER_IP_ADJUSTED=0

    case "$option" in
        1)
            SELECTED_PARAMETER="max-connections"
            SELECTED_LABEL="Max Connections"
            validation_error="Max Connections inválido. Introduce un valor entre 1024 y 32768."
            ;;

        2)
            SELECTED_PARAMETER="max-sessions"
            SELECTED_LABEL="Max Sessions"
            validation_error="Max Sessions inválido. Introduce un valor entre 16 y 32768."
            ;;

        3)
            SELECTED_PARAMETER="max-sessions-per-ip"
            SELECTED_LABEL="Max Sessions Per IP"
            validation_error="Max Sessions Per IP inválido. Introduce un valor entre 1 y el máximo permitido por Max Sessions."
            ;;

        4)
            SELECTED_PARAMETER="max-download-frame"
            SELECTED_LABEL="Max Download Frame"
            validation_error="Frame inválido. Introduce un valor entre 1 y 262140."
            ;;

        5)
            SELECTED_PARAMETER="download-poll-timeout"
            SELECTED_LABEL="Download Poll Timeout"
            validation_error="Timeout inválido. Introduce un valor entre 1s y 30s."
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

    # Para Max Sessions Per IP, el máximo permitido será
    # el menor Max Sessions encontrado entre todos los servicios.

    if [[ "$option" == "3" ]]; then
        if ! get_minimum_parameter_value "max-sessions"; then
            return 1
        fi
    fi

    edit_header

    printf '  %b◆%b  %bCONFIGURACIÓN DEL PARÁMETRO%b\n\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b⌬%b  %b%s%b\n' \
        "$MAGENTA$BOLD" "$RESET" \
        "$WHITE$BOLD" "$SELECTED_LABEL" "$RESET"

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

    # Mostrar límites específicos del parámetro.

    case "$option" in
        1)
            info "Rango permitido: 1024 - 32768"
            ;;
        2)
            info "Rango permitido: 16 - 32768"
            ;;
        3)
            info "Rango permitido: 1 - $MAX_ALLOWED_SESSIONS_PER_IP"
            ;;
        4)
            info "Rango permitido: 1 - 262140"
            ;;
        5)
            info "Rango permitido: 1s - 30s"
            ;;
        7|8)
            info "Rango permitido: 10s - 300s"
            ;;
    esac

    printf '\n'
    edit_line

    case "$option" in
        1)
            input_default="$DEFAULT_MAX_CONNECTIONS"
            ;;
        2)
            input_default="$DEFAULT_MAX_SESSIONS"
            ;;
        3)
            input_default="$DEFAULT_MAX_SESSIONS_PER_IP"
            ;;
        4)
            input_default="$DEFAULT_MAX_DOWNLOAD_FRAME"
            ;;
        5)
            input_default="$DEFAULT_DOWNLOAD_POLL_TIMEOUT"
            ;;
        7|8)
            input_default="$DEFAULT_INTERVAL"
            ;;
    esac

    # -------------------- ACCIONES DE EDICIÓN ----------------

    section "ACCIONES"

    printf '  %b[0]%b  Salir\n' \
        "$RED$BOLD" "$RESET"

    printf '\n'
    edit_line
    printf '\n'

    prompt="  ${MAGENTA}${BOLD}Nuevo valor${RESET} ${DIM}[${input_default}]${RESET}: "

    while true; do
        ask_recyclable "$prompt" "$input_default" input || return 1

        if [[ "$input" == "0" ]]; then
            CONFIG_CANCELLED=1
            return 0
        fi

        case "$option" in
            1)
                if valid_max_connections "$input"; then
                    normalize_integer "$input"
                    break
                fi
                ;;

            2)
                if valid_max_sessions "$input"; then
                    normalize_integer "$input"
                    break
                fi
                ;;

            3)
                if valid_max_sessions_per_ip "$input" "$MAX_ALLOWED_SESSIONS_PER_IP"; then
                    normalize_integer "$input"
                    break
                fi
                ;;

            4)
                if valid_frame "$input"; then
                    normalize_integer "$input"
                    break
                fi
                ;;

            5)
                if valid_timeout "$input"; then
                    normalize_timeout "$input"
                    break
                fi
                ;;

            7|8)
                if normalize_interval "$input"; then
                    break
                fi
                ;;
        esac

        wait_and_recycle "$validation_error" || return 1
    done

    # -------------------- VALIDACIÓN CRUZADA -----------------

    if [[ "$option" == "2" ]]; then

        if ! inspect_sessions_per_ip_adjustment "$PARAMETER_VALUE"; then
            return 1
        fi

        if (( SESSIONS_PER_IP_ADJUSTED )); then

            confirm_sessions_per_ip_adjustment || return 1

            if (( CONFIG_CANCELLED )); then
                return 0
            fi
        fi
    fi

    printf '\n'
    edit_line
    section "APLICANDO CONFIGURACIÓN"

    if ! prepare_backup_target "$SELECTED_PARAMETER"; then
        error "No se pudo preparar el directorio de respaldo."
        return 1
    fi

    if ! spinner "Creando copias de seguridad" create_backup; then
        error "No se pudieron crear las copias de seguridad."
        info "Respaldo conservado: $BACKUP_DIR"
        return 1
    fi

    # Max Sessions requiere modificar también Max Sessions Per IP
    # cuando algún servicio supera el nuevo límite autorizado.

    if [[ "$option" == "2" ]]; then

        if ! spinner "Actualizando Max Sessions y Max Sessions Per IP" modify_sessions_services; then
            error "No se pudieron modificar todos los servicios."
            recover_configuration || true
            return 1
        fi

    else

        if ! spinner "Actualizando parámetros de los servicios" modify_services; then
            error "No se pudieron modificar todos los servicios."
            recover_configuration || true
            return 1
        fi

    fi

    if ! spinner "Actualizando configuración de systemd" reload_systemd; then
        error "No se pudo actualizar systemd."
        recover_configuration || true
        return 1
    fi

    if ! spinner "Reiniciando servicios HCR" restart_services; then
        error "No se pudieron reiniciar todos los servicios."
        recover_configuration || true
        return 1
    fi

    if ! spinner "Verificando estado de los servicios" verify_services; then
        error "Se detectaron servicios con problemas después del reinicio."
        recover_configuration || true
        return 1
    fi

    if ! spinner "Verificando parámetros aplicados" verify_parameter_values; then
        error "Los parámetros aplicados no coinciden con los valores esperados."
        recover_configuration || true
        return 1
    fi

    if cleanup_backup; then
        success "Copia de seguridad temporal eliminada."
    else
        warning "No se pudo eliminar la copia de seguridad."
        info "Respaldo conservado: $BACKUP_DIR"
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

    printf '  %b[6]%b  %bSession Stats & Diagnostics%b ' \
        "$CYAN$BOLD" "$RESET" \
        "$WHITE" "$RESET"

    show_feature_status
    printf '\n'

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

        while true; do

            printf '  %bSelecciona una opción:%b ' "$CYAN$BOLD" "$RESET"

            if ! IFS= read -r option; then
                printf '\n'
                return 0
            fi

            case "$option" in
                1|2|3|4|5)
                    break
                    ;;

                7|8)
                    break
                    ;;

                6)
                    break
                    ;;

                0)
                    break
                    ;;

                *)
                    warning "Opción no válida."
                    sleep 1

                    printf '\033[1A\033[2K'
                    printf '\033[1A\033[2K'
                    ;;
            esac
        done

        case "$option" in
            1|2|3|4|5)
                CONFIG_CANCELLED=0

                if ! configure_parameter "$option"; then
                    warning "No se pudo completar la operación."
                fi

                if (( CONFIG_CANCELLED )); then
                    continue
                fi

                wait_for_enter || break
                ;;

            7|8)
                if ! get_feature_state; then
                    error "No se pudo determinar el estado de los parámetros."
                elif (( ! FEATURE_ENABLED )); then
                    warning "Esta opción no está disponible mientras Session Stats y Diagnostics estén desactivados."
                else
                    CONFIG_CANCELLED=0

                    if ! configure_parameter "$option"; then
                        warning "No se pudo completar la operación."
                    fi

                    if (( CONFIG_CANCELLED )); then
                        continue
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
        esac
    done
}

main "$@"
