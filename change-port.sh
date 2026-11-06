#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#              HCR SERVER EPRO DEV
#             MODIFICACIÓN DE REDIRECCIÓN
# ============================================================

SERVICE_PREFIX="hcr-server"
SERVICE_DIR="/etc/systemd/system"
BACKUP_BASE="/var/backups/hcr-redirection-control"

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

# -------------------- VARIABLES -----------------------------

declare -a SERVICES=()
declare -a SERVICE_PATHS=()
declare -a SERVICE_PORTS=()
declare -a SERVICE_TARGETS=()
declare -a SERVICE_STATES=()

declare -a UPDATED_SERVICES=()
declare -a FAILED_SERVICES=()

CURRENT_PORT=""
NEW_PORT=""
BACKUP_DIR=""

VALIDATION_ERROR=""

# -------------------- FUNCIONES VISUALES --------------------

line() {
    printf '%b\n' "${DIM}${BLUE}────────────────────────────────────────────────────────${RESET}"
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

section() {
    printf '\n'
    printf '  %b◆%b  %b%s%b\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$1" "$RESET"
    printf '\n'
}

# -------------------- ENCABEZADO ----------------------------

header() {
    clear 2>/dev/null || true

    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="R E D I R E C C I Ó N"

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

    printf '  %b●%b  %bMODIFICAR PUERTO DE REDIRECCIÓN%b\n' \
        "$GREEN" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
        "$YELLOW" "$RESET" "$GRAY" "$RESET"

    printf '\n'
    line
}

# -------------------- SPINNER --------------------------------

spinner() {
    local message="$1"
    shift

    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴')
    local pid
    local status=0
    local i=0
    local temp_dir
    local output_file
    local status_file
    local output_line

    temp_dir="$(mktemp -d)" || return 1
    output_file="$temp_dir/output"
    status_file="$temp_dir/status"

    (
        set +e
        "$@" >"$output_file" 2>&1
        status=$?
        printf '%s\n' "$status" >"$status_file"
        exit "$status"
    ) &

    pid=$!

    while [[ ! -f "$status_file" ]] && kill -0 "$pid" 2>/dev/null; do
        printf '\r\033[2K  %b%s%b  %b%s%b' \
            "$CYAN$BOLD" "${frames[i]}" "$RESET" \
            "$WHITE" "$message" "$RESET"

        i=$(( (i + 1) % 6 ))
        sleep 0.10
    done

    wait "$pid" || status=$?

    if [[ -f "$status_file" ]]; then
        read -r status < "$status_file"
    fi

    if (( status == 0 )); then
        printf '\r\033[2K  %b✓%b  %b%s%b\n' \
            "$GREEN$BOLD" "$RESET" "$WHITE" "$message" "$RESET"
    else
        printf '\r\033[2K  %b✗%b  %b%s%b\n' \
            "$RED$BOLD" "$RESET" "$RED" "$message" "$RESET"

        if [[ -s "$output_file" ]]; then
            printf '\n'

            while IFS= read -r output_line || [[ -n "$output_line" ]]; do
                printf '  %b›%b  %s\n' \
                    "$YELLOW" "$RESET" "$output_line"
            done < "$output_file"
        fi
    fi

    rm -rf "$temp_dir"

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

# -------------------- ESPERA Y RECICLAJE --------------------

wait_and_recycle() {
    local message="$1"
    local ignored

    warning "$message"

    IFS= read -r ignored || return 1

    printf '\033[u\033[J'
}

# -------------------- MENSAJE DE CANCELACIÓN ----------------

show_cancellation() {
    local message="MODIFICACIÓN CANCELADA"
    local width=58
    local padding
    
    line?
    printf '\n'

    padding=$(( (width - ${#message}) / 2 ))

    printf '%*s%b%s%b\n' \
        "$padding" '' \
        "$YELLOW$BOLD" "$message" "$RESET"

    printf '\n'
    line
    printf '\n'
}

# ============================================================
#                COMPROBACIONES INICIALES
# ============================================================

check_root() {
    if (( EUID != 0 )); then
        error "Ejecuta el script como root."
        exit 1
    fi
}

check_requirements() {
    local command

    for command in systemctl awk sort mktemp find python3 cp date; do
        if ! command -v "$command" >/dev/null 2>&1; then
            error "Falta una dependencia: $command"
            return 1
        fi
    done

    return 0
}

# ============================================================
#                VALIDACIÓN DE PUERTOS
# ============================================================

valid_port() {
    local port="$1"
    local value

    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1

    value=$((10#$port))

    (( value >= 1 && value <= 65535 ))
}

# ============================================================
#                LECTURA Y MODIFICACIÓN DE TARGET
# ============================================================

read_target() {
    local file="$1"

    python3 - "$file" <<'PY'
import re
import sys

path = sys.argv[1]

try:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
except Exception:
    sys.exit(1)

matches = []

pattern = re.compile(
    r'(--target(?:=|\s+))(["\']?)([^"\'\s]+)(["\']?)'
)

for line in lines:
    if not re.match(r'^\s*ExecStart\s*=', line):
        continue

    for match in pattern.finditer(line):
        matches.append(match.group(3))

if len(matches) != 1:
    sys.exit(1)

target = matches[0]

if ":" not in target:
    sys.exit(1)

host, port = target.rsplit(":", 1)

if not host or not port.isdigit():
    sys.exit(1)

if not 1 <= int(port) <= 65535:
    sys.exit(1)

print(target)
PY
}

update_target() {
    local file="$1"
    local new_port="$2"

    python3 - "$file" "$new_port" <<'PY'
import os
import re
import sys
import stat
import tempfile

path = sys.argv[1]
new_port = sys.argv[2]

try:
    if not new_port.isdigit() or not 1 <= int(new_port) <= 65535:
        sys.exit(1)

    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    pattern = re.compile(
        r'(--target(?:=|\s+))(["\']?)([^"\'\s]+)(["\']?)'
    )

    found = 0
    updated_lines = []

    for line in lines:
        if not re.match(r'^\s*ExecStart\s*=', line):
            updated_lines.append(line)
            continue

        def replace(match):
            global found

            target = match.group(3)

            if ":" not in target:
                raise ValueError("Destino de redirección inválido")

            host, old_port = target.rsplit(":", 1)

            if not host or not old_port.isdigit():
                raise ValueError("Destino de redirección inválido")

            found += 1

            return (
                match.group(1)
                + match.group(2)
                + host
                + ":"
                + new_port
                + match.group(4)
            )

        updated_lines.append(pattern.sub(replace, line))

    if found != 1:
        sys.exit(1)

    original_stat = os.stat(path)

    directory = os.path.dirname(path)

    fd, temporary = tempfile.mkstemp(
        prefix=".hcr-redirection-",
        dir=directory
    )

    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.writelines(updated_lines)
            f.flush()
            os.fsync(f.fileno())

        os.chown(
            temporary,
            original_stat.st_uid,
            original_stat.st_gid
        )

        os.chmod(
            temporary,
            stat.S_IMODE(original_stat.st_mode)
        )

        os.replace(temporary, path)

    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

except Exception:
    sys.exit(1)
PY
}

# ============================================================
#                DETECCIÓN DE SERVICIOS HCR
# ============================================================

discover_services() {
    local unit
    local port
    local state
    local path
    local target
    local target_port
    local dropins
    local seen=" "

    SERVICES=()
    SERVICE_PATHS=()
    SERVICE_PORTS=()
    SERVICE_TARGETS=()
    SERVICE_STATES=()

    while IFS= read -r unit; do

        [[ "$unit" =~ ^${SERVICE_PREFIX}-([0-9]{1,5})\.service$ ]] ||
            continue

        port="${BASH_REMATCH[1]}"

        if ! valid_port "$port"; then
            continue
        fi

        port=$((10#$port))

        if [[ "$seen" == *" $unit "* ]]; then
            continue
        fi

        seen+="$unit "

        path="$(systemctl show "$unit" \
            --property=FragmentPath \
            --value 2>/dev/null || true)"

        if [[ -z "$path" || "$path" == "-" || ! -f "$path" ]]; then
            error "No se pudo localizar la unidad $unit."
            return 1
        fi

        case "$path" in
            /etc/systemd/system/*)
                ;;
            *)
                error "Ubicación no administrada: $unit."
                return 1
                ;;
        esac

        dropins="$(systemctl show "$unit" \
            --property=DropInPaths \
            --value 2>/dev/null || true)"

        if [[ -n "$dropins" ]]; then
            error "El servicio $unit tiene configuraciones drop-in."
            info "No se modificó ningún servicio."
            return 1
        fi

        if ! target="$(read_target "$path")"; then
            error "No se pudo identificar el destino de $unit."
            return 1
        fi

        target_port="${target##*:}"

        if ! valid_port "$target_port"; then
            error "El puerto de redirección de $unit no es válido."
            return 1
        fi

        if systemctl is-active --quiet "$unit"; then
            state="ON"
        else
            state="OFF"
        fi

        SERVICES+=( "$unit" )
        SERVICE_PATHS+=( "$path" )
        SERVICE_PORTS+=( "$port" )
        SERVICE_TARGETS+=( "$target" )
        SERVICE_STATES+=( "$state" )

    done < <(
        {
            systemctl list-unit-files \
                --type=service \
                --no-legend 2>/dev/null |
                awk '{print $1}'

            systemctl list-units \
                --all \
                --type=service \
                --no-legend 2>/dev/null |
                awk '{print $1}'

            find \
                /etc/systemd/system \
                -maxdepth 1 \
                \( -type f -o -type l \) \
                -name "${SERVICE_PREFIX}-*.service" \
                -printf '%f\n' 2>/dev/null || true

        } | sort -Vu
    )

    (( ${#SERVICES[@]} > 0 ))
}

# ============================================================
#                MOSTRAR INFORMACIÓN ACTUAL
# ============================================================

show_current_information() {
    local target
    local port
    local first_port=""
    local different=0

    for target in "${SERVICE_TARGETS[@]}"; do

        port="${target##*:}"

        if [[ -z "$first_port" ]]; then
            first_port="$port"
        elif [[ "$first_port" != "$port" ]]; then
            different=1
            break
        fi

    done

    if (( different == 1 )); then
        CURRENT_PORT="VARIOS"
    else
        CURRENT_PORT="$first_port"
    fi

    section "CONFIGURACIÓN ACTUAL"

    printf '  %bTotal de servicios:%b %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE$BOLD" "${#SERVICES[@]}" "$RESET"

    printf '  %bPuerto actual:%b      %b%s%b\n' \
        "$GRAY" "$RESET" "$CYAN$BOLD" "$CURRENT_PORT" "$RESET"

    printf '\n'
    line
}

# ============================================================
#                SOLICITAR NUEVO PUERTO
# ============================================================

read_new_port() {
    local input
    local prompt
    local normalized

    section "OPERACIONES"

    printf '  %b[%s]%b  %bSALIR%b\n' \
    "$YELLOW$BOLD" "0" "$RESET" \
    "$WHITE$BOLD" "$RESET"

    printf '\n'
    line
    printf '\n'

    prompt="  ${CYAN}${BOLD}Nuevo puerto de redirección:${RESET} "

    while true; do

        ask_recyclable "$prompt" "" input || return 1

        if [[ "$input" == "0" ]]; then
            printf '\r\033[2K'
            return 2
        fi

        if ! valid_port "$input"; then
            wait_and_recycle "Puerto inválido. Utiliza un valor entre 1 y 65535." ||
                return 1
            continue
        fi

        normalized=$((10#$input))

        if [[ "$normalized" == "$CURRENT_PORT" ]]; then
            wait_and_recycle "El puerto indicado ya es el puerto actual." ||
                return 1
            continue
        fi

        NEW_PORT="$normalized"

        printf '\r\033[2K'
        return 0

    done
}

# ============================================================
#                CREAR COPIAS DE SEGURIDAD
# ============================================================

create_backups() {
    local i
    local path
    local unit

    BACKUP_DIR="$BACKUP_BASE/$(date '+%Y%m%d-%H%M%S')"

    mkdir -p "$BACKUP_DIR" || return 1
    chmod 700 "$BACKUP_BASE" "$BACKUP_DIR" || return 1

    for (( i=0; i<${#SERVICES[@]}; i++ )); do

        unit="${SERVICES[$i]}"
        path="${SERVICE_PATHS[$i]}"

        cp -a -- "$path" "$BACKUP_DIR/$unit" || return 1

    done

    return 0
}

# ============================================================
#                RESTAURAR CONFIGURACIÓN ORIGINAL
# ============================================================

rollback_changes() {
    local i
    local unit
    local path

    for (( i=0; i<${#SERVICES[@]}; i++ )); do

        unit="${SERVICES[$i]}"
        path="${SERVICE_PATHS[$i]}"

        if [[ -f "$BACKUP_DIR/$unit" ]]; then
            cp -a -- "$BACKUP_DIR/$unit" "$path" || true
        fi

    done

    systemctl daemon-reload >/dev/null 2>&1 || true

    for (( i=0; i<${#SERVICES[@]}; i++ )); do

        if [[ "${SERVICE_STATES[$i]}" == "ON" ]]; then
            systemctl restart "${SERVICES[$i]}" >/dev/null 2>&1 || true
        fi

    done
}

# ============================================================
#                APLICAR NUEVA CONFIGURACIÓN
# ============================================================

apply_changes() {
    local i
    local unit
    local path

    UPDATED_SERVICES=()
    FAILED_SERVICES=()

    # --------------------------------------------------------
    # MODIFICAR DESTINO DE REDIRECCIÓN
    # --------------------------------------------------------

    for (( i=0; i<${#SERVICES[@]}; i++ )); do

        unit="${SERVICES[$i]}"
        path="${SERVICE_PATHS[$i]}"

        if update_target "$path" "$NEW_PORT"; then
            UPDATED_SERVICES+=( "$unit" )
        else
            FAILED_SERVICES+=( "$unit" )
            rollback_changes
            return 1
        fi

    done

    # --------------------------------------------------------
    # ACTUALIZAR SYSTEMD
    # --------------------------------------------------------

    if ! systemctl daemon-reload; then
        rollback_changes
        return 1
    fi

    # --------------------------------------------------------
    # REINICIAR SERVICIOS QUE ESTABAN ACTIVOS
    # --------------------------------------------------------

    for (( i=0; i<${#SERVICES[@]}; i++ )); do

        unit="${SERVICES[$i]}"

        if [[ "${SERVICE_STATES[$i]}" == "ON" ]]; then

            if ! systemctl restart "$unit"; then
                FAILED_SERVICES+=( "$unit" )
                rollback_changes
                return 1
            fi

        fi

    done

    return 0
}

# ============================================================
#                VERIFICAR CONFIGURACIÓN FINAL
# ============================================================

verify_changes() {
    local i
    local unit
    local path
    local target
    local port

    FAILED_SERVICES=()

    for (( i=0; i<${#SERVICES[@]}; i++ )); do

        unit="${SERVICES[$i]}"
        path="${SERVICE_PATHS[$i]}"

        if ! target="$(read_target "$path")"; then
            FAILED_SERVICES+=( "$unit" )
            continue
        fi

        port="${target##*:}"

        if [[ "$port" != "$NEW_PORT" ]]; then
            FAILED_SERVICES+=( "$unit" )
            continue
        fi

        if [[ "${SERVICE_STATES[$i]}" == "ON" ]] &&
           ! systemctl is-active --quiet "$unit"; then

            FAILED_SERVICES+=( "$unit" )
            continue
        fi

    done

    (( ${#FAILED_SERVICES[@]} == 0 ))
}

# ============================================================
#                RESUMEN FINAL
# ============================================================

show_summary() {
    local total="${#SERVICES[@]}"
    local failed="${#FAILED_SERVICES[@]}"
    local updated=$((total - failed))

    printf '\n'
    line

    section "ESTADO DE ACTUALIZACIÓN"

    if (( failed == 0 )); then

        success "Todos los servicios fueron actualizados."

    else

        error "No se pudo completar la actualización."
        warning "Se intentó restaurar la configuración anterior."

    fi

    printf '\n'
    line
    printf '\n'

    printf '  %bPuerto anterior:%b        %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE$BOLD" "$CURRENT_PORT" "$RESET"

    printf '  %bNuevo puerto:%b           %b%s%b\n' \
        "$GRAY" "$RESET" "$CYAN$BOLD" "$NEW_PORT" "$RESET"

    printf '  %bTotal de servicios:%b     %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE$BOLD" "$total" "$RESET"

    printf '  %bServicios actualizados:%b %b%s%b\n' \
        "$GRAY" "$RESET" "$GREEN$BOLD" "$updated" "$RESET"

    if (( failed > 0 )); then
        printf '  %bServicios con errores:%b %b%s%b\n' \
            "$GRAY" "$RESET" "$RED$BOLD" "$failed" "$RESET"
    fi

    printf '\n'
    line
    printf '\n'

    local message
    local width=58

    if (( failed == 0 )); then
        message="ACTUALIZACIÓN COMPLETADA"

        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$GREEN$BOLD" "$message" "$RESET"
    else
        message="ACTUALIZACIÓN CON ERRORES"

        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$RED$BOLD" "$message" "$RESET"
    fi

    printf '\n'
    line
    printf '\n'
}

# ============================================================
#                    EJECUCIÓN PRINCIPAL
# ============================================================

main() {
    local result

    check_root
    header

    if ! check_requirements; then
        exit 1
    fi

    # --------------------------------------------------------
    # DETECCIÓN DE SERVICIOS
    # --------------------------------------------------------

    if ! discover_services; then

        if (( ${#SERVICES[@]} == 0 )); then
            error "No se encontraron servicios HCR."
        fi

        exit 0
    fi

    # --------------------------------------------------------
    # MOSTRAR CONFIGURACIÓN ACTUAL
    # --------------------------------------------------------

    show_current_information

    # --------------------------------------------------------
    # SOLICITAR NUEVO PUERTO
    # --------------------------------------------------------

    if read_new_port; then
        :
    else
        result=$?

        if (( result == 2 )); then
            show_cancellation
            exit 0
        fi

        exit 1
    fi

    # --------------------------------------------------------
    # CREAR COPIAS DE SEGURIDAD
    # --------------------------------------------------------

    if ! create_backups; then
        error "No se pudieron crear las copias de seguridad."
        exit 1
    fi

    # --------------------------------------------------------
    # APLICAR MODIFICACIONES
    # --------------------------------------------------------
    
    printf '\n'
    line
    printf '\n'
    
    if ! spinner "Actualizando servicios HCR" apply_changes; then

        error "No se pudo completar la modificación."
        info "Se intentó restaurar la configuración original."

        exit 1
    fi

    # --------------------------------------------------------
    # VERIFICAR RESULTADOS
    # --------------------------------------------------------

    if ! verify_changes; then
        warning "La verificación detectó servicios con errores."
    fi

    # --------------------------------------------------------
    # RESUMEN FINAL
    # --------------------------------------------------------

    show_summary

    if (( ${#FAILED_SERVICES[@]} > 0 )); then
        exit 1
    fi
}

main "$@"
