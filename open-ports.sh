#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#              HCR SERVER EPRO DEV
#                 APERTURA DE PUERTOS
# ============================================================
#
# FUNCIONES:
#   - Detección automática de servicios HCR existentes.
#   - Herencia automática de parámetros del servicio.
#   - Conservación de transporte PLAIN, TLS o AUTO.
#   - Reutilización de certificados TLS existentes.
#   - No descarga ni reemplaza el binario HCR.
#   - Instalación multipuerto independiente.
#   - Un servicio systemd por cada puerto.
#   - Validación y agrupación de puertos ocupados.
#   - Comprobación TCP mediante ss y /proc/net/tcp.
#   - Verificación mediante /proc/net/tcp6.
#   - Espera del listener después del inicio.
#   - Resumen detallado de estados y totales.
#   - Spinner animado.
#   - Consultas reciclables sin duplicar líneas.
#
# ============================================================

# -------------------- CONFIGURACIÓN -------------------------

SERVICE_PREFIX="hcr-server"
SERVICE_DIR="/etc/systemd/system"

DEFAULT_PORTS="8081"

PORT_CHECK_ATTEMPTS=20
PORT_CHECK_INTERVAL=0.25

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

    BG_BLUE='\033[44m'
    BG_CYAN='\033[46m'
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

    BG_BLUE=''
    BG_CYAN=''
fi

# -------------------- VARIABLES -----------------------------

declare -a SERVICES=()
declare -a SOURCE_ARGS=()
declare -a NEW_EXEC_ARGS=()
declare -a PORTS=()
declare -a CREATED_SERVICES=()

SOURCE_UNIT=""
SOURCE_WORKDIR=""
SOURCE_TRANSPORT=""

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
    local subtitle="A P E R T U R A   D E   P U E R T O S"

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

    printf '  %b●%b  %bREUTILIZACIÓN DE PARÁMETROS HCR%b\n' \
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

    for command in systemctl python3 awk sort mktemp ss find ln; do
        if ! command -v "$command" >/dev/null 2>&1; then
            error "Falta una dependencia: $command"
            return 1
        fi
    done

    return 0
}

# ============================================================
#                DETECCIÓN DE SERVICIOS HCR
# ============================================================

discover_services() {
    local unit

    SERVICES=()

    while IFS= read -r unit; do

        [[ "$unit" == "$SERVICE_PREFIX.service" ]] ||
        [[ "$unit" == "$SERVICE_PREFIX"-*.service ]] || continue

        SERVICES+=( "$unit" )

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
                /run/systemd/system \
                /usr/lib/systemd/system \
                /lib/systemd/system \
                -maxdepth 1 \
                \( -type f -o -type l \) \
                -name "${SERVICE_PREFIX}*.service" \
                -printf '%f\n' 2>/dev/null || true

        } | sort -u
    )

    (( ${#SERVICES[@]} > 0 ))
}

# ============================================================
#                EXTRAER EXECSTART EFECTIVO
# ============================================================

extract_execstart() {
    local unit="$1"
    local output
    local temp_args

    SOURCE_ARGS=()

    output="$(
        systemctl show "$unit" \
            -p ExecStart \
            --value 2>/dev/null || true
    )"

    [[ -n "$output" ]] || return 1

    temp_args="$(mktemp)" || return 1

    if ! printf '%s' "$output" |
        python3 -c '
import re
import shlex
import sys

data = sys.stdin.read()

match = re.search(
    r"argv\[\]=(.*?)(?:\s;\s|\s*\}\s*$)",
    data,
    re.S
)

if not match:
    sys.exit(1)

try:
    args = shlex.split(match.group(1))
except ValueError:
    sys.exit(1)

if not args:
    sys.exit(1)

for arg in args:
    if "\0" in arg:
        sys.exit(1)

    sys.stdout.buffer.write(arg.encode() + b"\0")
' > "$temp_args"; then

        rm -f "$temp_args"
        return 1
    fi

    if ! mapfile -d '' -t SOURCE_ARGS < "$temp_args"; then
        rm -f "$temp_args"
        return 1
    fi

    rm -f "$temp_args"

    (( ${#SOURCE_ARGS[@]} > 0 ))
}

# ============================================================
#                  WORKING DIRECTORY
# ============================================================

get_source_workdir() {
    local unit="$1"

    SOURCE_WORKDIR="$(
        systemctl show "$unit" \
            -p WorkingDirectory \
            --value 2>/dev/null || true
    )"

    if [[ -z "$SOURCE_WORKDIR" || "$SOURCE_WORKDIR" == "-" ]]; then
        SOURCE_WORKDIR="$(dirname "${SOURCE_ARGS[0]}")"
    fi

    [[ -n "$SOURCE_WORKDIR" ]] || SOURCE_WORKDIR="/"
}

# ============================================================
#                    DETECCIÓN DE TRANSPORTE
# ============================================================

get_transport() {
    local i=1
    local transport_count=0
    local value=""

    SOURCE_TRANSPORT=""

    while (( i < ${#SOURCE_ARGS[@]} )); do

        case "${SOURCE_ARGS[$i]}" in

            --transport=*)

                transport_count=$((transport_count + 1))
                value="${SOURCE_ARGS[$i]#*=}"
                ;;

            --transport)

                transport_count=$((transport_count + 1))

                if (( i + 1 >= ${#SOURCE_ARGS[@]} )); then
                    error "El argumento --transport no tiene un valor."
                    return 1
                fi

                value="${SOURCE_ARGS[$((i + 1))]}"

                if [[ -z "$value" || "$value" == --* ]]; then
                    error "El valor de --transport no es válido."
                    return 1
                fi

                i=$((i + 1))
                ;;

        esac

        i=$((i + 1))
    done

    if (( transport_count > 1 )); then
        error "La configuración contiene más de un argumento --transport."
        return 1
    fi

    if (( transport_count == 0 )); then
        SOURCE_TRANSPORT="auto"
    else
        SOURCE_TRANSPORT="${value,,}"
    fi

    case "$SOURCE_TRANSPORT" in
        plain|tls|auto)
            return 0
            ;;

        *)
            error "Transporte no válido: ${SOURCE_TRANSPORT:-vacío}. Usa plain, tls o auto."
            return 1
            ;;
    esac
}

# ============================================================
#                    DETECCIÓN DE CERTIFICADOS
# ============================================================

has_tls_arguments() {
    local has_cert=0
    local has_key=0
    local i=1

    while (( i < ${#SOURCE_ARGS[@]} )); do

        case "${SOURCE_ARGS[$i]}" in

            --tls-cert=*)
                has_cert=1
                ;;

            --tls-cert)
                if (( i + 1 < ${#SOURCE_ARGS[@]} )); then
                    has_cert=1
                    i=$((i + 1))
                fi
                ;;

            --tls-key=*)
                has_key=1
                ;;

            --tls-key)
                if (( i + 1 < ${#SOURCE_ARGS[@]} )); then
                    has_key=1
                    i=$((i + 1))
                fi
                ;;

        esac

        i=$((i + 1))
    done

    (( has_cert == 1 && has_key == 1 ))
}

service_has_tls() {
    local unit="$1"
    local -a saved_args=()
    local saved_transport="$SOURCE_TRANSPORT"

    saved_args=( "${SOURCE_ARGS[@]}" )

    if ! extract_execstart "$unit"; then
        SOURCE_ARGS=( "${saved_args[@]}" )
        SOURCE_TRANSPORT="$saved_transport"
        return 1
    fi

    if ! get_transport; then
        SOURCE_ARGS=( "${saved_args[@]}" )
        SOURCE_TRANSPORT="$saved_transport"
        return 1
    fi

    if [[ "$SOURCE_TRANSPORT" != "plain" ]] &&
       has_tls_arguments; then

        SOURCE_ARGS=( "${saved_args[@]}" )
        SOURCE_TRANSPORT="$saved_transport"
        return 0
    fi

    SOURCE_ARGS=( "${saved_args[@]}" )
    SOURCE_TRANSPORT="$saved_transport"

    return 1
}

# ============================================================
#             SELECCIÓN AUTOMÁTICA DE REFERENCIA
# ============================================================

select_reference_service() {
    local unit

    local active_tls=""
    local active_any=""
    local inactive_tls=""
    local inactive_any=""

    for unit in "${SERVICES[@]}"; do

        if ! extract_execstart "$unit"; then
            continue
        fi

        if (( ${#SOURCE_ARGS[@]} == 0 )); then
            continue
        fi

        if [[ ! -x "${SOURCE_ARGS[0]}" ]]; then
            continue
        fi

        if systemctl is-active --quiet "$unit"; then

            if service_has_tls "$unit"; then
                [[ -n "$active_tls" ]] || active_tls="$unit"
            else
                [[ -n "$active_any" ]] || active_any="$unit"
            fi

        else

            if service_has_tls "$unit"; then
                [[ -n "$inactive_tls" ]] || inactive_tls="$unit"
            else
                [[ -n "$inactive_any" ]] || inactive_any="$unit"
            fi

        fi
    done

    SOURCE_UNIT="${active_tls:-${active_any:-${inactive_tls:-$inactive_any}}}"

    if [[ -z "$SOURCE_UNIT" ]]; then
        error "No se encontró un servicio HCR válido para heredar parámetros."
        return 1
    fi

    if ! extract_execstart "$SOURCE_UNIT"; then
        error "No se pudo obtener la configuración del servicio de referencia."
        return 1
    fi

    get_source_workdir "$SOURCE_UNIT"

    if ! get_transport; then
        return 1
    fi

    return 0
}

# ============================================================
#                  OBTENER VALOR DE ARGUMENTO
# ============================================================

get_argument_value() {
    local wanted="$1"
    local i=1

    while (( i < ${#SOURCE_ARGS[@]} )); do

        case "${SOURCE_ARGS[$i]}" in

            "$wanted"=*)
                printf '%s' "${SOURCE_ARGS[$i]#*=}"
                return 0
                ;;

            "$wanted")
                if (( i + 1 < ${#SOURCE_ARGS[@]} )); then
                    printf '%s' "${SOURCE_ARGS[$((i + 1))]}"
                    return 0
                fi

                return 1
                ;;

        esac

        i=$((i + 1))
    done

    return 1
}

# ============================================================
#              OBTENER PUERTO DE REDIRECCIÓN
# ============================================================

get_redirect_port() {
    local target=""

    target="$(get_argument_value "--target" || true)"

    if [[ "$target" =~ :([0-9]{1,5})$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf 'NO CONFIGURADO'
    fi
}

# ============================================================
#                 PREPARAR ARGUMENTOS HEREDADOS
# ============================================================

prepare_arguments() {
    local i=1
    local arg
    local listen_count=0
    local listen_value

    NEW_EXEC_ARGS=()

    if (( ${#SOURCE_ARGS[@]} < 1 )); then
        error "La configuración de referencia está vacía."
        return 1
    fi

    NEW_EXEC_ARGS+=( "${SOURCE_ARGS[0]}" )

    while (( i < ${#SOURCE_ARGS[@]} )); do

        arg="${SOURCE_ARGS[$i]}"

        case "$arg" in

            --listen)

                listen_count=$((listen_count + 1))

                if (( i + 1 >= ${#SOURCE_ARGS[@]} )); then
                    error "El argumento --listen no tiene un valor."
                    return 1
                fi

                listen_value="${SOURCE_ARGS[$((i + 1))]}"

                if [[ -z "$listen_value" || "$listen_value" == --* ]]; then
                    error "El valor de --listen no es válido."
                    return 1
                fi

                # CORRECCIÓN:
                # Se conserva --listen en su posición original.
                # El valor se sustituirá al crear cada servicio.
                NEW_EXEC_ARGS+=( "$arg" "$listen_value" )

                i=$((i + 2))
                continue
                ;;

            --listen=*)

                listen_count=$((listen_count + 1))
                listen_value="${arg#*=}"

                if [[ -z "$listen_value" ]]; then
                    error "El argumento --listen no tiene un valor."
                    return 1
                fi

                # Se conserva también el formato --listen=valor.
                NEW_EXEC_ARGS+=( "$arg" )

                i=$((i + 1))
                continue
                ;;

        esac

        NEW_EXEC_ARGS+=( "$arg" )
        i=$((i + 1))
    done

    if (( listen_count != 1 )); then
        error "La configuración debe contener exactamente un --listen."
        return 1
    fi

    # El transporte PLAIN no debe heredar rutas TLS.
    if [[ "$SOURCE_TRANSPORT" == "plain" ]]; then
        if ! remove_tls_arguments; then
            return 1
        fi
    fi

    validate_tls_configuration
}

# ============================================================
#                 ELIMINAR ARGUMENTOS TLS
# ============================================================

remove_tls_arguments() {
    local -a filtered=()
    local i=1
    local arg
    local value

    filtered+=( "${NEW_EXEC_ARGS[0]}" )

    while (( i < ${#NEW_EXEC_ARGS[@]} )); do

        arg="${NEW_EXEC_ARGS[$i]}"

        case "$arg" in

            --tls-cert|--tls-key)

                if (( i + 1 >= ${#NEW_EXEC_ARGS[@]} )); then
                    error "Un argumento TLS no tiene un valor."
                    return 1
                fi

                value="${NEW_EXEC_ARGS[$((i + 1))]}"

                if [[ -z "$value" || "$value" == --* ]]; then
                    error "Se detectó un argumento TLS con un valor inválido."
                    return 1
                fi

                i=$((i + 2))
                continue
                ;;

            --tls-cert=*|--tls-key=*)

                value="${arg#*=}"

                if [[ -z "$value" ]]; then
                    error "Se detectó un argumento TLS vacío."
                    return 1
                fi

                i=$((i + 1))
                continue
                ;;

        esac

        filtered+=( "$arg" )
        i=$((i + 1))
    done

    NEW_EXEC_ARGS=( "${filtered[@]}" )
    return 0
}

# ============================================================
#                 VALIDAR CERTIFICADOS TLS
# ============================================================

get_tls_value() {
    local wanted="$1"
    local i=1

    while (( i < ${#NEW_EXEC_ARGS[@]} )); do

        case "${NEW_EXEC_ARGS[$i]}" in

            "$wanted"=*)
                printf '%s' "${NEW_EXEC_ARGS[$i]#*=}"
                return 0
                ;;

            "$wanted")
                if (( i + 1 < ${#NEW_EXEC_ARGS[@]} )); then
                    printf '%s' "${NEW_EXEC_ARGS[$((i + 1))]}"
                    return 0
                fi

                return 1
                ;;

        esac

        i=$((i + 1))
    done

    return 1
}

resolve_tls_path() {
    local path="$1"

    if [[ "$path" == /* ]]; then
        printf '%s' "$path"
    else
        printf '%s/%s' "$SOURCE_WORKDIR" "$path"
    fi
}

validate_tls_configuration() {
    local cert=""
    local key=""
    local cert_path=""
    local key_path=""
    local cert_count=0
    local key_count=0
    local value
    local i=1
    local arg

    while (( i < ${#NEW_EXEC_ARGS[@]} )); do

        arg="${NEW_EXEC_ARGS[$i]}"

        case "$arg" in

            --tls-cert=*)

                cert_count=$((cert_count + 1))
                value="${arg#*=}"

                if [[ -z "$value" ]]; then
                    error "El argumento --tls-cert está vacío."
                    return 1
                fi

                cert="$value"
                ;;

            --tls-key=*)

                key_count=$((key_count + 1))
                value="${arg#*=}"

                if [[ -z "$value" ]]; then
                    error "El argumento --tls-key está vacío."
                    return 1
                fi

                key="$value"
                ;;

            --tls-cert|--tls-key)

                if (( i + 1 >= ${#NEW_EXEC_ARGS[@]} )); then
                    error "Un argumento TLS no tiene un valor."
                    return 1
                fi

                value="${NEW_EXEC_ARGS[$((i + 1))]}"

                if [[ -z "$value" || "$value" == --* ]]; then
                    error "Se detectó un argumento TLS con un valor inválido."
                    return 1
                fi

                if [[ "$arg" == "--tls-cert" ]]; then
                    cert_count=$((cert_count + 1))
                    cert="$value"
                else
                    key_count=$((key_count + 1))
                    key="$value"
                fi

                i=$((i + 1))
                ;;

        esac

        i=$((i + 1))
    done

    if (( cert_count > 1 || key_count > 1 )); then
        error "La configuración contiene argumentos TLS duplicados."
        return 1
    fi

    if (( cert_count != key_count )); then
        error "La configuración TLS tiene certificado o clave incompletos."
        return 1
    fi

    if [[ "$SOURCE_TRANSPORT" == "tls" ]] &&
       (( cert_count == 0 )); then

        error "El transporte TLS requiere --tls-cert y --tls-key."
        return 1
    fi

    if (( cert_count == 1 && key_count == 1 )); then

        cert_path="$(resolve_tls_path "$cert")"
        key_path="$(resolve_tls_path "$key")"

        if [[ ! -f "$cert_path" || ! -r "$cert_path" ]]; then
            error "No se puede leer el certificado TLS: $cert_path"
            return 1
        fi

        if [[ ! -f "$key_path" || ! -r "$key_path" ]]; then
            error "No se puede leer la clave TLS: $key_path"
            return 1
        fi

    fi

    return 0
}

# ============================================================
#                    VALIDACIÓN DE PUERTOS
# ============================================================

valid_port() {
    local port="$1"

    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1

    (( 10#$port >= 1 && 10#$port <= 65535 ))
}

# ============================================================
#                 COMPROBACIÓN MEDIANTE SS
# ============================================================

port_in_use_ss() {
    local port="$1"
    local listeners

    listeners="$(ss -H -lnt 2>/dev/null || true)"

    [[ -n "$listeners" ]] || return 1

    awk -v port="$port" '
        {
            address = $4

            sub(/^.*:/, "", address)

            if (address ~ /^[0-9]+$/ && address == port) {
                found = 1
                exit
            }
        }

        END {
            exit !found
        }
    ' <<< "$listeners"
}

# ============================================================
#                COMPROBACIÓN /proc/net/tcp
# ============================================================

port_in_use_proc() {
    local port="$1"
    local port_hex

    printf -v port_hex '%04X' "$port"

    if [[ -r /proc/net/tcp ]]; then

        if awk -v port_hex="$port_hex" '
            FNR > 1 {
                split($2, address, ":")

                local_port = toupper(address[2])
                state = toupper($4)

                if (local_port == port_hex && state == "0A") {
                    found = 1
                    exit
                }
            }

            END {
                exit !found
            }
        ' /proc/net/tcp; then
            return 0
        fi

    fi

    if [[ -r /proc/net/tcp6 ]]; then

        if awk -v port_hex="$port_hex" '
            FNR > 1 {
                split($2, address, ":")

                local_port = toupper(address[2])
                state = toupper($4)

                if (local_port == port_hex && state == "0A") {
                    found = 1
                    exit
                }
            }

            END {
                exit !found
            }
        ' /proc/net/tcp6; then
            return 0
        fi

    fi

    return 1
}

# ============================================================
#                  COMPROBACIÓN GLOBAL TCP
# ============================================================

port_in_use() {
    local port="$1"

    if port_in_use_ss "$port"; then
        return 0
    fi

    if port_in_use_proc "$port"; then
        return 0
    fi

    return 1
}

# ============================================================
#                 COMPROBAR SERVICIO EXISTENTE
# ============================================================

service_file_exists() {
    local port="$1"
    local unit="${SERVICE_PREFIX}-${port}.service"

    if [[ -e "$SERVICE_DIR/$unit" || -L "$SERVICE_DIR/$unit" ]]; then
        return 0
    fi

    if systemctl cat "$unit" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# ============================================================
#                 NORMALIZAR PUERTOS
# ============================================================

normalize_ports() {
    local input="$1"
    local item
    local -a items=()
    local -a normalized=()
    local seen=" "

    input="${input//,/ }"

    read -r -a items <<< "$input"

    for item in "${items[@]}"; do

        if [[ ! "$item" =~ ^[0-9]+$ ]] ||
           (( ${#item} > 5 )); then

            VALIDATION_ERROR="Entrada inválida. Introduce puertos correctos (1-65535)."
            return 1
        fi

        if ! valid_port "$item"; then
            VALIDATION_ERROR="El puerto $item no es válido. Rango permitido: 1-65535."
            return 1
        fi

        item=$((10#$item))

        if [[ "$seen" == *" $item "* ]]; then
            continue
        fi

        normalized+=( "$item" )
        seen+="$item "
    done

    if (( ${#normalized[@]} == 0 )); then
        VALIDATION_ERROR="Debes introducir al menos un puerto."
        return 1
    fi

    PORTS=( "${normalized[@]}" )

    return 0
}

# ============================================================
#             AGRUPAR TODOS LOS PUERTOS OCUPADOS
# ============================================================

join_port_list() {
    local -a values=( "$@" )
    local count="${#values[@]}"
    local i
    local result=""

    for (( i=0; i<count; i++ )); do

        if (( i == 0 )); then
            result="${values[$i]}"

        elif (( i == count - 1 )); then
            result+=" y ${values[$i]}"

        else
            result+=", ${values[$i]}"
        fi

    done

    printf '%s' "$result"
}

check_ports() {
    local port
    local -a occupied_ports=()
    local -a sorted_ports=()
    local ports_text

    for port in "${PORTS[@]}"; do

        if service_file_exists "$port" || port_in_use "$port"; then
            occupied_ports+=( "$port" )
        fi

    done

    if (( ${#occupied_ports[@]} > 0 )); then

        mapfile -t sorted_ports < <(
            printf '%s\n' "${occupied_ports[@]}" |
                sort -n -u
        )

        ports_text="$(join_port_list "${sorted_ports[@]}")"

        VALIDATION_ERROR="Los puertos ${ports_text} ya están ocupados."

        return 1
    fi

    return 0
}

# ============================================================
#                 ESPERA Y VERIFICACIÓN DEL LISTENER
# ============================================================

wait_for_port() {
    local port="$1"
    local attempt

    for (( attempt=0; attempt<PORT_CHECK_ATTEMPTS; attempt++ )); do

        if port_in_use "$port"; then
            return 0
        fi

        sleep "$PORT_CHECK_INTERVAL"
    done

    port_in_use "$port"
}

# ============================================================
#                   ESCAPE PARA SYSTEMD
# ============================================================

systemd_quote_arguments() {
    python3 -c '
import re
import sys

args = sys.argv[1:]

# Los argumentos simples se mantienen sin comillas.
# Los argumentos especiales se protegen para systemd.

SAFE_ARGUMENT = re.compile(r"^[A-Za-z0-9_./:@+=,-]+$")

def quote(value):

    if SAFE_ARGUMENT.fullmatch(value):
        return value

    value = value.replace("\\", "\\\\")
    value = value.replace("\"", "\\\"")
    value = value.replace("%", "%%")
    value = value.replace("$", "$$")
    value = value.replace("\n", "\\n")

    return "\"" + value + "\""

print(" ".join(quote(arg) for arg in args))
' "$@"
}

# ============================================================
#               PREPARAR ARGUMENTOS PARA CADA PUERTO
# ============================================================

build_port_arguments() {
    local port="$1"
    local i=1
    local arg
    local value
    local listen_count=0

    local -a final_args=()

    final_args+=( "${NEW_EXEC_ARGS[0]}" )

    while (( i < ${#NEW_EXEC_ARGS[@]} )); do

        arg="${NEW_EXEC_ARGS[$i]}"

        case "$arg" in

            --listen)

                if (( i + 1 >= ${#NEW_EXEC_ARGS[@]} )); then
                    error "El argumento --listen no tiene un valor."
                    return 1
                fi

                value="${NEW_EXEC_ARGS[$((i + 1))]}"

                if [[ -z "$value" || "$value" == --* ]]; then
                    error "El valor de --listen no es válido."
                    return 1
                fi

                listen_count=$((listen_count + 1))

                # Sustituye el valor en su posición original.
                final_args+=( "--listen" ":$port" )

                i=$((i + 2))
                continue
                ;;

            --listen=*)

                listen_count=$((listen_count + 1))

                # Conserva la modalidad --listen=valor.
                final_args+=( "--listen=:$port" )

                i=$((i + 1))
                continue
                ;;

        esac

        final_args+=( "$arg" )
        i=$((i + 1))
    done

    if (( listen_count != 1 )); then
        error "No se pudo conservar la posición original de --listen."
        return 1
    fi

    # Devuelve los argumentos mediante un array global.
    PORT_EXEC_ARGS=( "${final_args[@]}" )

    return 0
}

# ============================================================
#                   CREAR SERVICIO SYSTEMD
# ============================================================

create_service() {
    local port="$1"
    local unit="${SERVICE_PREFIX}-${port}.service"
    local unit_path="$SERVICE_DIR/$unit"

    local temp_unit
    local exec_line
    local working_directory

    local -a PORT_EXEC_ARGS=()

    # Evitar sobrescribir unidades existentes.
    if service_file_exists "$port"; then
        error "Ya existe un servicio asociado al puerto $port."
        return 1
    fi

    # Construir los argumentos respetando el orden original.
    if ! build_port_arguments "$port"; then
        return 1
    fi

    # Recuperar el array preparado por build_port_arguments.
    # La función anterior utiliza el array global PORT_EXEC_ARGS.
    if ! exec_line="$(
        systemd_quote_arguments "${PORT_EXEC_ARGS[@]}"
    )"; then
        error "No se pudieron preparar los argumentos de $unit."
        return 1
    fi

    # WorkingDirectory no pasa por el escape de ExecStart.
    working_directory="$SOURCE_WORKDIR"

    if [[ "$working_directory" != /* ]]; then
        error "El directorio de trabajo no es una ruta absoluta: $working_directory"
        return 1
    fi

    if [[ ! -d "$working_directory" ]]; then
        error "El directorio de trabajo no existe: $working_directory"
        return 1
    fi

    temp_unit="$(mktemp "$SERVICE_DIR/.hcr-port-${port}.XXXXXX")" || {
        error "No se pudo crear el archivo temporal de $unit."
        return 1
    }

    if ! cat > "$temp_unit" <<EOF
[Unit]
Description=HCR Server EPRO DEV - Port ${port}
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${working_directory}
ExecStart=${exec_line}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    then
        rm -f -- "$temp_unit"
        error "No se pudo escribir la unidad $unit."
        return 1
    fi

    if ! chmod 0644 "$temp_unit"; then
        rm -f -- "$temp_unit"
        error "No se pudieron establecer los permisos de $unit."
        return 1
    fi

    # Creación exclusiva y atómica: nunca reemplaza una unidad existente.
    if ! ln -- "$temp_unit" "$unit_path"; then
        rm -f -- "$temp_unit"
        error "No se pudo instalar $unit. El archivo ya existe o no se puede crear."
        return 1
    fi

    rm -f -- "$temp_unit"

    # Registrar únicamente unidades creadas por este script.
    CREATED_SERVICES+=( "$unit" )

    return 0
}

# ============================================================
#                        ROLLBACK
# ============================================================

rollback_created_services() {
    local unit

    for unit in "${CREATED_SERVICES[@]}"; do

        systemctl disable --now "$unit" >/dev/null 2>&1 || true

        rm -f -- "$SERVICE_DIR/$unit"

    done

    systemctl daemon-reload >/dev/null 2>&1 || true
}

# ============================================================
#                   INSTALACIÓN MULTIPUERTO
# ============================================================

install_services() {
    local port
    local unit

    CREATED_SERVICES=()

    for port in "${PORTS[@]}"; do

        if ! create_service "$port"; then
            rollback_created_services
            return 1
        fi

    done

    if ! systemctl daemon-reload; then
        error "No se pudo actualizar la configuración de systemd."
        rollback_created_services
        return 1
    fi

    for port in "${PORTS[@]}"; do

        unit="${SERVICE_PREFIX}-${port}.service"

        if ! systemctl enable --now "$unit" >/dev/null 2>&1; then
            error "No se pudo habilitar o iniciar $unit."

            printf '\n'
            systemctl status "$unit" --no-pager --full 2>&1 || true

            if command -v journalctl >/dev/null 2>&1; then
                printf '\n'
                journalctl -u "$unit" -n 20 --no-pager 2>&1 || true
            fi

            rollback_created_services
            return 1
        fi

    done

    return 0
}

# ============================================================
#                 VERIFICACIÓN DE SERVICIOS
# ============================================================

verify_services() {
    local port
    local failed=0

    for port in "${PORTS[@]}"; do

        if ! wait_for_port "$port"; then
            failed=1
        fi

    done

    return "$failed"
}

# ============================================================
#                  CONSULTA DE PUERTOS
# ============================================================

read_ports() {
    local ports_input
    local prompt

    section "OPERACIONES"

    printf '  %b[%s]%b  %bSALIR%b\n' \
        "$YELLOW$BOLD" "0" "$RESET" \
        "$WHITE$BOLD" "$RESET"

    printf '\n'
    line

    section "CONFIGURACIÓN"

    prompt="  ${CYAN}${BOLD}Puertos HCR${RESET} ${DIM}[${DEFAULT_PORTS}]${RESET}: "

    while true; do

        ask_recyclable "$prompt" "$DEFAULT_PORTS" ports_input || return 1

        # Salir al seleccionar 0.
        if [[ "$ports_input" == "0" ]]; then
            printf '\r\033[2K'
            return 2
        fi

        if ! normalize_ports "$ports_input"; then
            wait_and_recycle "$VALIDATION_ERROR" || return 1
            continue
        fi

        if ! check_ports; then
            wait_and_recycle "$VALIDATION_ERROR" || return 1
            continue
        fi

        printf '\r\033[2K'
        return 0

    done
}

# ============================================================
#                 RESUMEN DE CONFIGURACIÓN
# ============================================================

show_configuration() {
    local transport_label
    local tls_status
    local cert=""
    local key=""
    local redirect_port=""

    cert="$(get_tls_value "--tls-cert" || true)"
    key="$(get_tls_value "--tls-key" || true)"
    redirect_port="$(get_redirect_port)"

    case "$SOURCE_TRANSPORT" in

        plain)
            transport_label="PLAIN"
            tls_status="CERRADO"
            ;;

        tls)
            transport_label="TLS"
            tls_status="ABIERTO"
            ;;

        auto)
            transport_label="AUTO"

            if [[ -n "$cert" && -n "$key" ]]; then
                tls_status="ABIERTO"
            else
                tls_status="SIN CERTIFICADOS"
            fi
            ;;

        *)
            transport_label="${SOURCE_TRANSPORT^^}"
            tls_status="NO DETERMINADO"
            ;;

    esac

    printf '\n'
    line

    section "RESUMEN DE CONFIGURACIÓN"

    printf '  %b%-28s%b %b%s%b\n' \
        "$CYAN" "Puertos HCR:" "$RESET" \
        "$WHITE$BOLD" "${PORTS[*]}" "$RESET"

    printf '  %b%-29s%b %b%s%b\n' \
        "$CYAN" "Puerto de redirección:" "$RESET" \
        "$WHITE$BOLD" "$redirect_port" "$RESET"

    printf '  %b%-28s%b %b%s%b\n' \
        "$CYAN" "Transporte:" "$RESET" \
        "$WHITE$BOLD" "$transport_label" "$RESET"

    printf '  %b%-28s%b ' \
        "$CYAN" "SSL/TLS:" "$RESET"

    case "$tls_status" in

        CERRADO|SIN\ CERTIFICADOS|NO\ DETERMINADO)
            printf '%b%s%b\n' "$YELLOW$BOLD" "$tls_status" "$RESET"
            ;;

        *)
            printf '%b%s%b\n' "$GREEN$BOLD" "$tls_status" "$RESET"
            ;;

    esac

    if [[ -n "$cert" && -n "$key" ]]; then
        printf '  %b%-28s%b %b%s%b\n' \
            "$CYAN" "Certificados:" "$RESET" \
            "$GREEN$BOLD" "REUTILIZADOS" "$RESET"
    fi

    printf '\n'
    line
    printf '\n'
}

# ============================================================
#                    RESUMEN FINAL
# ============================================================

show_summary() {
    local port
    local service
    local active_state
    local sub_state
    local result
    local exit_status
    local status_text
    local status_color
    local listener_open

    local active_count=0
    local open_count=0
    local closed_count=0
    local stopped_count=0
    local error_count=0
    local starting_count=0

    local total_count="${#PORTS[@]}"

    printf '\n'
    line

    section "ESTADO DE LOS SERVICIOS"

    for port in "${PORTS[@]}"; do

        service="${SERVICE_PREFIX}-${port}.service"

        active_state="$(
            systemctl show "$service" \
                --property=ActiveState \
                --value 2>/dev/null || true
        )"

        sub_state="$(
            systemctl show "$service" \
                --property=SubState \
                --value 2>/dev/null || true
        )"

        result="$(
            systemctl show "$service" \
                --property=Result \
                --value 2>/dev/null || true
        )"

        exit_status="$(
            systemctl show "$service" \
                --property=ExecMainStatus \
                --value 2>/dev/null || true
        )"

        listener_open=0

        case "$active_state" in

            active)

                active_count=$((active_count + 1))

                if port_in_use "$port"; then
                    listener_open=1
                    open_count=$((open_count + 1))

                    status_text="FUNCIONANDO"
                    status_color="$GREEN"
                else
                    closed_count=$((closed_count + 1))

                    status_text="SIN ESCUCHA"
                    status_color="$YELLOW"
                fi
                ;;

            activating)

                starting_count=$((starting_count + 1))

                status_text="INICIANDO"
                status_color="$CYAN"
                ;;

            inactive)

                stopped_count=$((stopped_count + 1))

                status_text="DETENIDO"
                status_color="$RED"
                ;;

            failed)

                error_count=$((error_count + 1))

                status_text="ERROR"
                status_color="$RED"
                ;;

            *)

                error_count=$((error_count + 1))

                status_text="ERROR"
                status_color="$RED"
                ;;

        esac

        printf '  %b●%b  %b%-34s%b  %b%-20s%b\n' \
            "$status_color" "$RESET" \
            "$WHITE" "$service" "$RESET" \
            "$status_color$BOLD" "$status_text" "$RESET"

        if [[ "$active_state" == "failed" ]]; then

            printf '     %b›%b  Resultado: %s | Código: %s | Subestado: %s\n' \
                "$RED" "$RESET" \
                "${result:-desconocido}" \
                "${exit_status:-desconocido}" \
                "${sub_state:-desconocido}"

        elif [[ "$active_state" == "active" ]] &&
             (( listener_open == 0 )); then

            printf '     %b›%b  systemd está activo, pero no se detecta un listener TCP en el puerto %s.\n' \
                "$YELLOW" "$RESET" "$port"

            printf '     %b›%b  Subestado: %s | Resultado: %s\n' \
                "$YELLOW" "$RESET" \
                "${sub_state:-desconocido}" \
                "${result:-desconocido}"

        elif [[ "$active_state" == "inactive" ]]; then

            printf '     %b›%b  Subestado: %s | Resultado: %s\n' \
                "$RED" "$RESET" \
                "${sub_state:-desconocido}" \
                "${result:-desconocido}"

        fi

    done

    # -------------------- TOTALES ----------------------------

    printf '\n'
    line
    printf '\n'

    printf '  %bTotal de servicios:%b          %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE$BOLD" "$total_count" "$RESET"

    printf '  %bServicios activos:%b           %b%s%b\n' \
        "$GRAY" "$RESET" "$GREEN$BOLD" "$active_count" "$RESET"

    printf '  %bPuertos escuchando:%b          %b%s%b\n' \
        "$GRAY" "$RESET" "$GREEN$BOLD" "$open_count" "$RESET"

    if (( closed_count > 0 )); then
        printf '  %bPuertos sin escucha:%b         %b%s%b\n' \
            "$GRAY" "$RESET" "$YELLOW$BOLD" "$closed_count" "$RESET"
    fi

    if (( stopped_count > 0 )); then
        printf '  %bServicios detenidos:%b         %b%s%b\n' \
            "$GRAY" "$RESET" "$RED$BOLD" "$stopped_count" "$RESET"
    fi

    if (( error_count > 0 )); then
        printf '  %bServicios con error:%b         %b%s%b\n' \
            "$GRAY" "$RESET" "$RED$BOLD" "$error_count" "$RESET"
    fi

    if (( starting_count > 0 )); then
        printf '  %bServicios iniciando:%b         %b%s%b\n' \
            "$GRAY" "$RESET" "$CYAN$BOLD" "$starting_count" "$RESET"
    fi

    printf '\n'

    if (( open_count == total_count )); then
        success "Todos los servicios funcionan y sus puertos están escuchando."
    elif (( closed_count > 0 || stopped_count > 0 || error_count > 0 )); then
        warning "Se detectaron servicios que requieren atención."
    elif (( starting_count > 0 )); then
        warning "Hay servicios que todavía están iniciando."
    else
        warning "No se pudo confirmar el funcionamiento de todos los servicios."
    fi

    printf '\n'
    line
    printf '\n'

    local message
    local width=58

    if (( open_count == total_count )); then
        message="APERTURA DE PUERTOS COMPLETADA"
        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$GREEN$BOLD" "$message" "$RESET"

    else
        message="APERTURA DE PUERTOS CON OBSERVACIONES"
        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$YELLOW$BOLD" "$message" "$RESET"
    fi

    printf '\n'
    line
    printf '\n'

    # Esperar ENTER sin mostrar ningún mensaje.
    IFS= read -r _
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
    # DETECCIÓN Y HERENCIA INTERNA
    # --------------------------------------------------------

    if ! discover_services; then
        error "No se encontraron servicios HCR instalados."
        exit 1
    fi

    if ! select_reference_service; then
        exit 1
    fi

    if [[ ! -x "${SOURCE_ARGS[0]}" ]]; then
        error "El binario HCR de referencia no existe o no es ejecutable."
        exit 1
    fi

    if ! prepare_arguments; then
        exit 1
    fi

    # --------------------------------------------------------
    # CONFIGURACIÓN DE PUERTOS
    # --------------------------------------------------------

    if read_ports; then
        :
    else
        result=$?

        if (( result == 2 )); then
            exit 0
        fi

        exit 1
    fi

    # --------------------------------------------------------
    # RESUMEN DE CONFIGURACIÓN
    # --------------------------------------------------------

    show_configuration

    # --------------------------------------------------------
    # CREACIÓN DE SERVICIOS
    # --------------------------------------------------------

    if ! spinner "Creando servicios HCR" install_services; then
        error "No se pudo completar la instalación de los servicios."
        exit 1
    fi

    # --------------------------------------------------------
    # VERIFICACIÓN DE PUERTOS
    # --------------------------------------------------------

    if ! spinner "Verificando puertos TCP" verify_services; then
        warning "Uno o más puertos no comenzaron a escuchar."
        warning "Los servicios creados se conservarán para su revisión."
    fi

    # --------------------------------------------------------
    # RESUMEN FINAL
    # --------------------------------------------------------

    show_summary
}

main "$@"
