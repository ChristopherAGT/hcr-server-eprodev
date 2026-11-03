#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#                HCR SERVER EPRO DEV
#                    SSL / TLS MANAGER
# ============================================================

SERVICE_PREFIX="hcr-server"
SERVICE_DIR="/etc/systemd/system"

TLS_DIR="/etc/hcr-server/tls"
BACKUP_BASE="/var/backups/hcr-tls-manager"

CERT_FILE="$TLS_DIR/fullchain.pem"
KEY_FILE="$TLS_DIR/privkey.pem"

HCR_BIN="/usr/local/lib/hcr-server/hcr-server"

CERT_PATH=""
KEY_PATH=""
BACKUP_DIR=""
SELECTED_MODE=""
EXPECTED_HOST=""
SCAN_TMP=""
MODE_LABEL="MODO MAESTRO"

CERTIFICATES=()
SERVICES=()

declare -A KEY_HASHES=()
declare -A CERT_SEEN=()
declare -A KEY_SEEN=()

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
    printf '  %b◆%b  %b%s%b\n\n' "$CYAN" "$RESET" "$WHITE$BOLD" "$1" "$RESET"
}

# -------------------- ENCABEZADO ----------------------------

header() {
    clear 2>/dev/null || true

    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="S S L  /  T L S   M A N A G E R"

    printf '\n\n'

    printf '%*s%bHCR%b %bSERVER%b %bEPRO DEV%b\n' \
        "$(( (width - ${#title}) / 2 ))" '' \
        "$CYAN$BOLD" "$RESET" \
        "$WHITE$BOLD" "$RESET" \
        "$MAGENTA$BOLD" "$RESET"

    printf '%*s%b%s%b\n' \
        "$(( (width - ${#subtitle}) / 2 ))" '' \
        "$GRAY" "$subtitle" "$RESET"

    printf '\n'
    line
    printf '\n'

    printf '  %b●%b  %bACTIVACIÓN DE TLS/SSL%b\n' \
        "$GREEN" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
        "$YELLOW" "$RESET" "$GRAY" "$RESET"

    printf '\n'
    line
    printf '\n'
}

# -------------------- ENCABEZADO TLS ------------------------

edit_header() {
    clear 2>/dev/null || true

    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="C O N F I G U R A C I Ó N"

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

    printf '  %b●%b  %b%s%b\n' \
        "$MAGENTA" "$RESET" "$WHITE$BOLD" "$MODE_LABEL" "$RESET"

    printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
        "$YELLOW" "$RESET" "$MAGENTA$BOLD" "$RESET"

    printf '\n'
    edit_line
    printf '\n'
}

# -------------------- SPINNER -------------------------------

spinner() {
    local message="$1"
    shift

    local frames=('●' '○' '○' '○' '○' '○')
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
        sleep 0.12
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

# -------------------- CONSULTAS -----------------------------

wait_for_enter() {
    local ignored
    IFS= read -r ignored
}

ask() {
    local prompt="$1"
    local default="${2:-}"
    local variable="$3"
    local value

    printf '%b' "$prompt"
    IFS= read -r value || return 1

    value="${value:-$default}"
    printf -v "$variable" '%s' "$value"
}

# -------------------- ENTRADA DE OPCIONES -------------------

OPTION_VALUE=""

read_option() {
    local prompt="$1"

    printf '%b' "$prompt"

    IFS= read -r OPTION_VALUE
}

invalid_option() {
    local ignored

    # Mostrar advertencia inmediatamente debajo de la entrada.
    warning "Opción inválida."

    # Esperar ENTER sin mostrar mensajes adicionales.
    IFS= read -r ignored || true

    # Limpiar la línea de espera, la advertencia
    # y la entrada anterior.
    if [[ -t 0 && -t 1 ]]; then
        printf '\033[1A\r\033[2K'
        printf '\033[1A\r\033[2K'
        printf '\033[1A\r\033[2K'
    fi
}

# -------------------- DEPENDENCIAS --------------------------

check_requirements() {
    local command

    for command in \
        systemctl openssl python3 awk grep sed \
        find install cp rm date mktemp chmod chown \
        sha256sum cut hostname basename dirname sleep mv \
        sort stat
    do
        if ! command -v "$command" >/dev/null 2>&1; then
            error "Falta una dependencia: $command"
            return 1
        fi
    done

    return 0
}

# -------------------- TEMPORALES ----------------------------

cleanup() {
    if [[ -n "$SCAN_TMP" && -d "$SCAN_TMP" ]]; then
        rm -rf -- "$SCAN_TMP"
        SCAN_TMP=""
    fi
}

trap cleanup EXIT

# -------------------- DETECTAR SERVICIOS --------------------

detect_services() {
    local file

    SERVICES=()

    shopt -s nullglob

    for file in "$SERVICE_DIR/${SERVICE_PREFIX}"*.service; do
        [[ -f "$file" ]] || continue
        SERVICES+=("$file")
    done

    shopt -u nullglob

    if (( ${#SERVICES[@]} == 0 )); then
        error "No se encontraron servicios HCR."
        return 1
    fi

    return 0
}

# ============================================================
#             LECTURA DE PARÁMETROS SYSTEMD
# ============================================================

get_argument() {
    local file="$1"
    local argument="$2"

    python3 - "$file" "$argument" <<'PY'
import re
import sys

path, name = sys.argv[1:3]

pattern = re.compile(
    r'(?<!\S)-{1,2}' + re.escape(name) +
    r'(?:=|\s+)(?:"([^"]*)"|\'([^\']*)\'|([^\s]+))'
)

values = []

with open(path, encoding="utf-8") as f:
    for line in f:
        if re.match(r'^\s*ExecStart\s*=', line):
            for match in pattern.finditer(line):
                value = next(
                    (item for item in match.groups() if item is not None),
                    None
                )
                if value is not None:
                    values.append(value)

if len(values) != 1:
    sys.exit(1)

print(values[0])
PY
}

get_transport() {
    local file="$1"
    get_argument "$file" "transport" 2>/dev/null || printf 'DESCONOCIDO'
}

# ============================================================
#       LEER CONFIGURACIÓN REAL CARGADA POR SYSTEMD
# ============================================================

get_loaded_argument() {
    local unit="$1"
    local argument="$2"
    local output

    output="$(systemctl show "$unit" -p ExecStart --value 2>/dev/null)" ||
        return 1

    python3 - "$argument" "$output" <<'PY'
import re
import sys

name, value = sys.argv[1:3]

pattern = re.compile(
    r'(?<!\S)-{1,2}' + re.escape(name) +
    r'(?:=|\s+)(?:"([^"]*)"|\'([^\']*)\'|([^\s;]+))'
)

matches = []

for match in pattern.finditer(value):
    item = next(
        (part for part in match.groups() if part is not None),
        None
    )

    if item is not None:
        matches.append(item)

if len(matches) != 1:
    sys.exit(1)

print(matches[0])
PY
}

# -------------------- ESTADO GLOBAL -------------------------

get_global_transport() {
    local file
    local transport
    local first=""
    local initialized=0
    local different=0

    for file in "${SERVICES[@]}"; do
        transport="$(get_transport "$file")"

        if (( initialized == 0 )); then
            first="$transport"
            initialized=1
        elif [[ "$transport" != "$first" ]]; then
            different=1
        fi
    done

    if (( different )); then
        printf 'mixed'
    else
        printf '%s' "$first"
    fi
}

get_global_activity() {
    local file
    local active=0
    local inactive=0

    for file in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$(basename "$file")"; then
            active=$((active + 1))
        else
            inactive=$((inactive + 1))
        fi
    done

    if (( active == ${#SERVICES[@]} )); then
        printf 'ACTIVE'
    elif (( inactive == ${#SERVICES[@]} )); then
        printf 'INACTIVE'
    else
        printf 'MIXED'
    fi
}

show_services() {
    local count="${#SERVICES[@]}"
    local transport
    local label
    local color
    local width=56
    local left_text
    local right_text
    local spaces

    transport="$(get_global_transport)"

    case "$transport" in
        tls)
            label="ACTUAL: TLS"
            color="$GREEN$BOLD"
            ;;
        auto)
            label="ACTUAL: AUTO"
            color="$CYAN$BOLD"
            ;;
        plain)
            label="ACTUAL: PLAIN"
            color="$RED$BOLD"
            ;;
        mixed)
            label="ACTUAL: MIXED"
            color="$YELLOW$BOLD"
            ;;
        *)
            label="ACTUAL: N/D"
            color="$YELLOW$BOLD"
            ;;
    esac

    left_text="Servicios detectados: $count"
    right_text="$label"

    spaces=$(( width - ${#left_text} - ${#right_text} - 4 ))
    (( spaces < 1 )) && spaces=1

    printf '  %b%s%b%*s%b%s%b  \n' \
        "$GRAY" "$left_text" "$RESET" \
        "$spaces" '' \
        "$color" "$right_text" "$RESET"
}

# ============================================================
#             MOTOR DE VALIDACIÓN SSL / TLS
# ============================================================

certificate_hash() {
    local cert="$1"

    openssl x509 -in "$cert" -pubkey -noout 2>/dev/null |
        openssl pkey -pubin -outform DER 2>/dev/null |
        sha256sum | awk '{print $1}'
}

private_key_hash() {
    local key="$1"

    openssl pkey \
        -in "$key" \
        -passin pass: \
        -pubout \
        -outform DER 2>/dev/null |
        sha256sum | awk '{print $1}'
}

validate_dates() {
    local cert="$1"
    local start
    local end
    local now

    start="$(openssl x509 -in "$cert" -noout -startdate 2>/dev/null)"
    end="$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null)"

    start="${start#*=}"
    end="${end#*=}"

    [[ -n "$start" && -n "$end" ]] || return 1

    start="$(date -u -d "$start" +%s 2>/dev/null)" || return 1
    end="$(date -u -d "$end" +%s 2>/dev/null)" || return 1
    now="$(date -u +%s)"

    (( now >= start )) || return 1
    (( now <= end )) || return 1

    return 0
}

validate_server_certificate() {
    local cert="$1"
    local extensions
    local eku
    local san

    openssl x509 -in "$cert" -noout >/dev/null 2>&1 || return 1

    extensions="$(openssl x509 -in "$cert" -noout -ext basicConstraints 2>/dev/null || true)"

    if grep -qi 'CA:TRUE' <<<"$extensions"; then
        return 1
    fi

    eku="$(openssl x509 -in "$cert" -noout -ext extendedKeyUsage 2>/dev/null || true)"

    if [[ -n "$eku" ]] &&
       ! grep -Eqi 'TLS Web Server Authentication|serverAuth' <<<"$eku"; then
        return 1
    fi

    san="$(openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null || true)"

    grep -q 'Subject Alternative Name' <<<"$san" || return 1

    return 0
}

validate_hostname_match() {
    local cert="$1"
    local hostname="$2"

    [[ -z "$hostname" ]] && return 0

    if python3 - "$hostname" <<'PY'
import ipaddress
import sys

try:
    ipaddress.ip_address(sys.argv[1])
    sys.exit(0)
except ValueError:
    sys.exit(1)
PY
    then
        openssl x509 -in "$cert" -noout -checkip "$hostname" >/dev/null 2>&1
    else
        openssl x509 -in "$cert" -noout -checkhost "$hostname" >/dev/null 2>&1
    fi
}

extract_leaf_certificate() {
    local cert="$1"
    local output="$2"

    openssl x509 -in "$cert" -out "$output" 2>/dev/null
}

validate_chain() {
    local cert="$1"
    local leaf="$SCAN_TMP/leaf-$$.pem"

    extract_leaf_certificate "$cert" "$leaf" || return 1

    openssl verify \
        -purpose sslserver \
        -CApath /etc/ssl/certs \
        -untrusted "$cert" \
        "$leaf" >/dev/null 2>&1
}

validate_certificate() {
    local cert="$1"
    local key="$2"
    local expected="${3:-}"
    local cert_hash
    local key_hash

    [[ -f "$cert" && -r "$cert" ]] || return 1
    [[ -f "$key" && -r "$key" ]] || return 1

    openssl x509 -in "$cert" -noout >/dev/null 2>&1 || return 1

    openssl pkey \
        -in "$key" \
        -passin pass: \
        -noout >/dev/null 2>&1 || return 1

    validate_server_certificate "$cert" || return 1
    validate_dates "$cert" || return 1
    validate_hostname_match "$cert" "$expected" || return 1

    cert_hash="$(certificate_hash "$cert")" || return 1
    key_hash="$(private_key_hash "$key")" || return 1

    [[ -n "$cert_hash" && "$cert_hash" == "$key_hash" ]] || return 1

    validate_chain "$cert" || return 1

    return 0
}

show_certificate_info() {
    local cert="$1"

    printf '\n'

    printf '  %bTitular:%b\n' "$GRAY" "$RESET"
    openssl x509 -in "$cert" -noout -subject -nameopt multiline 2>/dev/null

    printf '\n'

    printf '  %bEmisor:%b\n' "$GRAY" "$RESET"
    openssl x509 -in "$cert" -noout -issuer -nameopt multiline 2>/dev/null

    printf '\n'

    printf '  %bVálido desde:%b ' "$GRAY" "$RESET"
    openssl x509 -in "$cert" -noout -startdate 2>/dev/null | cut -d= -f2-

    printf '  %bVálido hasta:%b ' "$GRAY" "$RESET"
    openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2-

    printf '\n'

    printf '  %bDominios SAN:%b\n' "$GRAY" "$RESET"
    openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null |
        sed '1d' | sed 's/^/      /'

    printf '\n'
}

# ============================================================
#                 BUSCADOR DE CERTIFICADOS
# ============================================================

scan_private_keys() {
    local directory
    local file
    local hash

    KEY_HASHES=()
    KEY_SEEN=()

    local directories=(
        /etc
        /root
        /home
        /usr/local
        /opt
        /var/lib
        /var/www
        /srv
    )

    for directory in "${directories[@]}"; do
        [[ -d "$directory" ]] || continue

        while IFS= read -r -d '' file; do
            [[ -r "$file" ]] || continue
            [[ "$file" =~ \.(pub|crt|cer)$ ]] && continue

            hash="$(private_key_hash "$file" 2>/dev/null || true)"
            [[ -n "$hash" ]] || continue

            if [[ -z "${KEY_HASHES[$hash]+x}" ]]; then
                KEY_HASHES["$hash"]="$file"
                KEY_SEEN["$file"]=1
            fi

        done < <(
            find -L "$directory" -maxdepth 10 -type f \
                \( -iname '*.key' \
                -o -iname '*.pem' \
                -o -iname '*.p8' \
                -o -iname '*.pk8' \
                -o -iname '*.priv' \
                -o -iname 'privkey' \
                -o -iname 'private' \) \
                -print0 2>/dev/null
        )
    done
}

scan_certificates() {
    local directory
    local cert
    local hash
    local key
    local pair

    CERTIFICATES=()
    CERT_SEEN=()

    local directories=(
        /etc
        /root
        /home
        /usr/local
        /opt
        /var/lib
        /var/www
        /srv
    )

    cleanup

    SCAN_TMP="$(mktemp -d /tmp/hcr-tls-scan.XXXXXXXX)" || return 1
    chmod 700 "$SCAN_TMP"

    scan_private_keys

    for directory in "${directories[@]}"; do
        [[ -d "$directory" ]] || continue

        while IFS= read -r -d '' cert; do
            [[ -r "$cert" ]] || continue

            openssl x509 -in "$cert" -noout >/dev/null 2>&1 || continue
            validate_server_certificate "$cert" || continue
            validate_dates "$cert" || continue
            validate_hostname_match "$cert" "$EXPECTED_HOST" || continue

            hash="$(certificate_hash "$cert" 2>/dev/null || true)"
            [[ -n "$hash" ]] || continue

            [[ -n "${CERT_SEEN[$hash]+x}" ]] && continue

            key="${KEY_HASHES[$hash]:-}"
            [[ -n "$key" ]] || continue

            if ! validate_certificate "$cert" "$key" "$EXPECTED_HOST"; then
                continue
            fi

            pair="$cert|$key"
            CERTIFICATES+=("$pair")
            CERT_SEEN["$hash"]="$cert"

        done < <(
            find -L "$directory" -maxdepth 10 -type f \
                \( -iname '*.pem' \
                -o -iname '*.crt' \
                -o -iname '*.cer' \
                -o -iname '*.cert' \) \
                -print0 2>/dev/null
        )
    done

    return 0
}

certificate_label() {
    local cert="$1"

    python3 - "$cert" <<'PY'
import re
import subprocess
import sys

cert = sys.argv[1]

try:
    output = subprocess.check_output(
        [
            "openssl",
            "x509",
            "-in", cert,
            "-noout",
            "-ext", "subjectAltName"
        ],
        stderr=subprocess.DEVNULL,
        text=True
    )

    names = re.findall(
        r'(?:DNS|IP Address):([^,\s]+)',
        output
    )

    if names:
        print(names[0])
        sys.exit(0)

except Exception:
    pass

print("Certificado SSL")
PY
}

show_certificates() {
    local entry
    local cert
    local label
    local index=0

    for entry in "${CERTIFICATES[@]}"; do
        cert="${entry%%|*}"
        label="$(certificate_label "$cert")"

        index=$((index + 1))

        printf '  %b[%s]%b  %b%s%b\n' \
            "$CYAN$BOLD" "$index" "$RESET" \
            "$WHITE" "$label" "$RESET"
    done
}

# ============================================================
#                 CERTIFICADOS AUTOFIRMADOS
# ============================================================

validate_hostname() {
    local hostname="$1"

    python3 - "$hostname" <<'PY'
import ipaddress
import re
import sys

value = sys.argv[1]

try:
    ipaddress.ip_address(value)
    sys.exit(0)
except ValueError:
    pass

if len(value) > 253:
    sys.exit(1)

if not re.fullmatch(
    r'(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*',
    value
):
    sys.exit(1)
PY
}

get_san_type() {
    local hostname="$1"

    python3 - "$hostname" <<'PY'
import ipaddress
import sys

try:
    ipaddress.ip_address(sys.argv[1])
    print("IP")
except ValueError:
    print("DNS")
PY
}

create_self_signed() {
    local hostname
    local san_type
    local subject
    local timestamp
    local temp_cert=""
    local temp_key=""
    local old_cert=""
    local old_key=""
    local answer

    edit_header
    section "CREAR CERTIFICADO AUTOFIRMADO"

    info "Vigencia: 365 días."
    info "Clave privada: RSA de 2048 bits."
    info "SAN incluido para dominio o dirección IP."

    printf '\n'
    edit_line
    printf '\n'

    ask "  ${CYAN}Dominio o IP del servidor:${RESET} " \
        "$(hostname -f 2>/dev/null || hostname)" hostname || return 1

    if ! validate_hostname "$hostname"; then
        error "Dominio o IP no válido."
        return 1
    fi

    san_type="$(get_san_type "$hostname")"
    subject="/CN=$hostname"

    if ! install -d -o root -g root -m 700 "$TLS_DIR"; then
        error "No se pudo preparar el directorio TLS."
        return 1
    fi

    timestamp="$(date '+%Y%m%d-%H%M%S')"

    if [[ -e "$CERT_FILE" || -e "$KEY_FILE" ]]; then
        warning "Ya existen archivos en el directorio TLS."

        printf '\n'
        printf '  %b[1]%b  Respaldar y reemplazar\n' "$GREEN$BOLD" "$RESET"
        printf '  %b[0]%b  Cancelar\n' "$RED$BOLD" "$RESET"
        printf '\n'

        while true; do
            if ! read_option \
                "  ${CYAN}${BOLD}Selecciona una opción:${RESET} "; then
                return 1
            fi

            answer="$OPTION_VALUE"

            case "$answer" in
                1)
                    break
                    ;;
                0)
                    return 2
                    ;;
                *)
                    invalid_option
                    ;;
            esac
        done

        if [[ -e "$CERT_FILE" ]]; then
            old_cert="$TLS_DIR/fullchain.pem.previous-$timestamp"
            cp -a "$CERT_FILE" "$old_cert" || return 1
        fi

        if [[ -e "$KEY_FILE" ]]; then
            old_key="$TLS_DIR/privkey.pem.previous-$timestamp"
            cp -a "$KEY_FILE" "$old_key" || return 1
        fi
    fi

    temp_cert="$(mktemp "$TLS_DIR/.fullchain.XXXXXXXX")" || return 1

    temp_key="$(mktemp "$TLS_DIR/.privkey.XXXXXXXX")" || {
        rm -f "$temp_cert"
        return 1
    }

    chmod 600 "$temp_cert" "$temp_key"

    if ! spinner "Generando certificado SSL/TLS" \
        openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$temp_key" \
        -out "$temp_cert" \
        -days 365 \
        -subj "$subject" \
        -addext "subjectAltName=$san_type:$hostname" \
        -addext "extendedKeyUsage=serverAuth" \
        -addext "basicConstraints=critical,CA:FALSE"
    then
        rm -f "$temp_cert" "$temp_key"
        error "No se pudo generar el certificado."
        return 1
    fi

    if ! openssl x509 -in "$temp_cert" -noout >/dev/null 2>&1 ||
       ! openssl pkey -in "$temp_key" -noout >/dev/null 2>&1 ||
       [[ "$(certificate_hash "$temp_cert")" != "$(private_key_hash "$temp_key")" ]] ||
       ! validate_dates "$temp_cert" ||
       ! validate_server_certificate "$temp_cert" ||
       ! validate_hostname_match "$temp_cert" "$hostname"
    then
        rm -f "$temp_cert" "$temp_key"
        error "Falló la validación del certificado generado."
        return 1
    fi

    chmod 644 "$temp_cert"
    chmod 600 "$temp_key"
    chown root:root "$temp_cert" "$temp_key"

    if ! mv -f "$temp_cert" "$CERT_FILE"; then
        rm -f "$temp_cert" "$temp_key"
        error "No se pudo instalar el certificado."
        return 1
    fi

    if ! mv -f "$temp_key" "$KEY_FILE"; then
        rm -f "$temp_key"
        error "No se pudo instalar la clave privada."
        return 1
    fi

    chmod 644 "$CERT_FILE"
    chmod 600 "$KEY_FILE"
    chown root:root "$CERT_FILE" "$KEY_FILE"

    CERT_PATH="$CERT_FILE"
    KEY_PATH="$KEY_FILE"
    EXPECTED_HOST="$hostname"

    success "Certificado autofirmado creado correctamente."
    info "Certificado: $CERT_PATH"
    info "Clave privada: $KEY_PATH"

    warning "Un certificado autofirmado no tendrá confianza pública automática."
    warning "Los clientes deberán confiar expresamente en él."

    return 0
}

# ============================================================
#                 SELECCIONAR CERTIFICADO
# ============================================================

# Códigos de retorno:
#   0 = certificado seleccionado correctamente.
#   1 = error real.
#   2 = usuario canceló y debe volver al menú principal.

select_certificate() {
    local entry
    local cert
    local key
    local choice
    local index
    local total
    local numeric_choice

    EXPECTED_HOST=""
    CERT_PATH=""
    KEY_PATH=""

    if ! scan_certificates; then
        error "No se pudo completar la búsqueda."
        return 1
    fi

    total="${#CERTIFICATES[@]}"

    # --------------------------------------------------------
    # SIN CERTIFICADOS COMPATIBLES
    # --------------------------------------------------------

    if (( total == 0 )); then

        warning "No se encontraron certificados compatibles."

        printf '\n'
        printf '  %b[1]%b  Crear un certificado SSL\n' \
            "$GREEN$BOLD" "$RESET"

        printf '  %b[0]%b  Salir\n' \
            "$RED$BOLD" "$RESET"

        printf '\n'
        edit_line
        printf '\n'

        while true; do

            if ! read_option \
                "  ${CYAN}${BOLD}Selecciona una opción:${RESET} "; then
                return 1
            fi

            choice="$OPTION_VALUE"

            case "$choice" in
                1)
                    create_self_signed
                    return $?
                    ;;

                0)
                    return 2
                    ;;

                *)
                    invalid_option
                    ;;
            esac
        done
    fi

    # --------------------------------------------------------
    # MOSTRAR TODOS LOS CERTIFICADOS DETECTADOS
    # --------------------------------------------------------

    printf '  %b◆%b  %bCERTIFICADOS DISPONIBLES%b\n\n' \
    "$CYAN" "$RESET" "$WHITE$BOLD" "$RESET"

    show_certificates

    printf '\n'
    printf '  %b[0]%b  Salir\n' "$RED$BOLD" "$RESET"

    printf '\n'
    edit_line
    printf '\n'

    # --------------------------------------------------------
    # SELECCIÓN DINÁMICA
    # --------------------------------------------------------

    while true; do

        if ! read_option \
            "  ${CYAN}${BOLD}Selecciona una opción:${RESET} "; then
            return 1
        fi

        choice="$OPTION_VALUE"

        if [[ "$choice" == "0" ]]; then
            return 2
        fi

        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            invalid_option
            continue
        fi

        numeric_choice="$choice"
        numeric_choice="${numeric_choice#"${numeric_choice%%[!0]*}"}"
        numeric_choice="${numeric_choice:-0}"

        if [[ "$numeric_choice" == "0" ]] ||
           (( ${#numeric_choice} > ${#total} )) ||
           {
               (( ${#numeric_choice} == ${#total} )) &&
               [[ "$numeric_choice" > "$total" ]]
           } ||
           (( numeric_choice < 1 || numeric_choice > total )); then

            invalid_option
            continue
        fi

        index=$((numeric_choice - 1))
        entry="${CERTIFICATES[index]}"

        cert="${entry%%|*}"
        key="${entry#*|}"

        if ! validate_certificate "$cert" "$key" "$EXPECTED_HOST"; then
            error "El certificado ya no supera la validación."
            wait_for_enter || return 1
            continue
        fi

        CERT_PATH="$cert"
        KEY_PATH="$key"

        return 0
    done
}

# ============================================================
#                 SOPORTE TLS DEL BINARIO HCR
# ============================================================

check_hcr_tls_support() {
    local mode="$1"
    local help_output=""

    if [[ ! -x "$HCR_BIN" ]]; then
        error "No se encontró el binario HCR:"
        info "$HCR_BIN"
        return 1
    fi

    help_output="$("$HCR_BIN" --help 2>&1 || true)"

    if ! grep -Eq '^[[:space:]]+-{1,2}transport([=[:space:]]|$)' <<<"$help_output"; then
        error "El binario no anuncia soporte para transport."
        return 1
    fi

    if [[ "$mode" == "tls" || "$mode" == "auto" ]]; then

        if ! grep -Eq '^[[:space:]]+-{1,2}tls-cert([=[:space:]]|$)' <<<"$help_output"; then
            error "El binario no anuncia el parámetro tls-cert."
            return 1
        fi

        if ! grep -Eq '^[[:space:]]+-{1,2}tls-key([=[:space:]]|$)' <<<"$help_output"; then
            error "El binario no anuncia el parámetro tls-key."
            return 1
        fi
    fi

    return 0
}

# ============================================================
#                 COPIAS DE SEGURIDAD
# ============================================================

prepare_backup() {
    local timestamp

    install -d -o root -g root -m 700 "$BACKUP_BASE"

    timestamp="$(date '+%Y%m%d-%H%M%S')"

    BACKUP_DIR="$(mktemp -d "$BACKUP_BASE/tls-$timestamp-XXXXXXXX")"

    chmod 700 "$BACKUP_DIR"
}

create_backup() {
    local file

    for file in "${SERVICES[@]}"; do
        cp -a "$file" "$BACKUP_DIR/" || return 1
    done

    return 0
}

cleanup_backup() {
    [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || return 0

    case "$BACKUP_DIR" in
        "$BACKUP_BASE"/*)
            rm -rf -- "$BACKUP_DIR" || return 1
            BACKUP_DIR=""
            ;;
        *)
            error "Ruta de respaldo no autorizada."
            return 1
            ;;
    esac
}

validate_tls_paths() {
    local cert="$1"
    local key="$2"

    [[ "$cert" == /* && "$key" == /* ]] || return 1
    [[ "$cert" =~ ^/[A-Za-z0-9_./+-]+$ ]] || return 1
    [[ "$key" =~ ^/[A-Za-z0-9_./+-]+$ ]] || return 1

    return 0
}

# ============================================================
#           MODIFICADOR DE SERVICIOS
# ============================================================

modify_services() {
    local mode="$1"
    local cert="${2:-}"
    local key="${3:-}"

    local file
    local temp_file

    if [[ "$mode" == "tls" || "$mode" == "auto" ]]; then
        validate_tls_paths "$cert" "$key" || {
            error "Las rutas TLS contienen caracteres no permitidos."
            return 1
        }
    fi

    for file in "${SERVICES[@]}"; do

        temp_file="$(mktemp)" || return 1

        if ! python3 - \
            "$file" \
            "$temp_file" \
            "$mode" \
            "$cert" \
            "$key" <<'PY'
import re
import sys

source, destination, mode, cert, key = sys.argv[1:6]

with open(source, encoding="utf-8") as f:
    lines = f.readlines()

transport_pattern = re.compile(
    r'(?<!\S)-{1,2}transport(?:=|\s+)(?:"[^"]*"|\'[^\']*\'|[^\s]+)'
)

cert_pattern = re.compile(
    r'(?<!\S)-{1,2}tls-cert(?:=|\s+)(?:"[^"]*"|\'[^\']*\'|[^\s]+)'
)

key_pattern = re.compile(
    r'(?<!\S)-{1,2}tls-key(?:=|\s+)(?:"[^"]*"|\'[^\']*\'|[^\s]+)'
)

updated = []
exec_count = 0

for line in lines:

    if not re.match(r'^\s*ExecStart\s*=', line):
        updated.append(line)
        continue

    exec_count += 1

    if exec_count != 1:
        sys.exit(1)

    transport_matches = list(transport_pattern.finditer(line))
    cert_matches = list(cert_pattern.finditer(line))
    key_matches = list(key_pattern.finditer(line))

    if len(transport_matches) > 1:
        sys.exit(1)

    if len(cert_matches) > 1:
        sys.exit(1)

    if len(key_matches) > 1:
        sys.exit(1)

    line = cert_pattern.sub('', line)
    line = key_pattern.sub('', line)

    if transport_matches:
        line = transport_pattern.sub(
            '--transport=' + mode,
            line,
            count=1
        )
    else:
        line = line.rstrip('\n')
        line += ' --transport=' + mode + '\n'

    if mode in ('tls', 'auto'):

        if not cert or not key:
            sys.exit(1)

        line = line.rstrip('\n')
        line += ' --tls-cert=' + cert
        line += ' --tls-key=' + key
        line += '\n'

    updated.append(line)

if exec_count != 1:
    sys.exit(1)

with open(destination, 'w', encoding="utf-8") as f:
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

reload_systemd() {
    systemctl daemon-reload
}

restart_services() {
    local file
    local failed=0

    for file in "${SERVICES[@]}"; do
        if ! systemctl restart "$(basename "$file")" >/dev/null 2>&1; then
            failed=1
        fi
    done

    return "$failed"
}

verify_services() {
    local file
    local failed=0

    for file in "${SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$(basename "$file")"; then
            failed=1
        fi
    done

    return "$failed"
}

# ============================================================
#      VERIFICAR CONFIGURACIÓN EN ARCHIVO Y SYSTEMD
# ============================================================

verify_configuration() {
    local file
    local unit
    local transport
    local loaded_transport
    local cert
    local key
    local loaded_cert
    local loaded_key

    for file in "${SERVICES[@]}"; do

        unit="$(basename "$file")"

        transport="$(get_argument "$file" "transport")" || return 1

        loaded_transport="$(get_loaded_argument "$unit" "transport")" ||
            return 1

        [[ "$transport" == "$SELECTED_MODE" ]] || return 1
        [[ "$loaded_transport" == "$SELECTED_MODE" ]] || return 1

        systemctl is-active --quiet "$unit" || return 1

        if [[ "$SELECTED_MODE" == "plain" ]]; then

            if get_argument "$file" "tls-cert" >/dev/null 2>&1; then
                return 1
            fi

            if get_argument "$file" "tls-key" >/dev/null 2>&1; then
                return 1
            fi

            if get_loaded_argument "$unit" "tls-cert" >/dev/null 2>&1; then
                return 1
            fi

            if get_loaded_argument "$unit" "tls-key" >/dev/null 2>&1; then
                return 1
            fi

        else

            cert="$(get_argument "$file" "tls-cert")" || return 1
            key="$(get_argument "$file" "tls-key")" || return 1

            loaded_cert="$(get_loaded_argument "$unit" "tls-cert")" ||
                return 1

            loaded_key="$(get_loaded_argument "$unit" "tls-key")" ||
                return 1

            [[ "$cert" == "$CERT_PATH" ]] || return 1
            [[ "$key" == "$KEY_PATH" ]] || return 1

            [[ "$loaded_cert" == "$CERT_PATH" ]] || return 1
            [[ "$loaded_key" == "$KEY_PATH" ]] || return 1
        fi
    done

    return 0
}

# ============================================================
#                 RESTAURACIÓN AUTOMÁTICA
# ============================================================

rollback() {
    local file
    local backup_file
    local failed=0

    warning "Restaurando la configuración original..."

    for file in "${SERVICES[@]}"; do

        backup_file="$BACKUP_DIR/$(basename "$file")"

        if [[ ! -f "$backup_file" ]]; then
            failed=1
            continue
        fi

        if ! cp -a "$backup_file" "$file"; then
            failed=1
        fi
    done

    if (( failed )); then
        error "No se pudieron restaurar todos los servicios."
        info "Respaldo conservado: $BACKUP_DIR"
        return 1
    fi

    if ! systemctl daemon-reload >/dev/null 2>&1; then
        error "No se pudo actualizar systemd."
        info "Respaldo conservado: $BACKUP_DIR"
        return 1
    fi

    if ! restart_services; then
        error "Falló el reinicio de la configuración original."
        info "Respaldo conservado: $BACKUP_DIR"
        return 1
    fi

    if ! verify_services; then
        error "La restauración no recuperó todos los servicios."
        info "Respaldo conservado: $BACKUP_DIR"
        return 1
    fi

    success "Configuración original restaurada."

    return 0
}

# ============================================================
#                 APLICAR CONFIGURACIÓN
# ============================================================

is_plain_active() {
    [[ "$(get_verified_global_mode)" == "plain" ]]
}

apply_configuration() {
    local mode="$1"

    SELECTED_MODE="$mode"

    if [[ "$mode" == "tls" || "$mode" == "auto" ]]; then
        if ! validate_certificate "$CERT_PATH" "$KEY_PATH" "$EXPECTED_HOST"; then
            error "Certificado o clave privada no válidos."
            return 1
        fi
    fi

    if ! check_hcr_tls_support "$mode"; then
        warning "No se modificó ningún servicio."
        return 1
    fi

    # Se conserva visible la lista de certificados elegida.

    printf '\n'
    edit_line
    section "APLICANDO CONFIGURACIÓN"

    case "$mode" in
        tls)
            info "Transporte seleccionado: TLS"
            ;;
        auto)
            info "Transporte seleccionado: AUTO"
            ;;
        plain)
            info "Transporte seleccionado: PLAIN"
            ;;
    esac

    if [[ "$mode" != "plain" ]]; then
        info "Certificado: $CERT_PATH"
        info "Clave privada: $KEY_PATH"
    fi

    printf '\n'
    warning "Las conexiones activas se interrumpirán al reiniciar."
    printf '\n'

    if ! prepare_backup; then
        error "No se pudo preparar el respaldo."
        return 1
    fi

    if ! spinner "Creando copias de seguridad" create_backup; then
        error "No se pudieron respaldar los servicios."
        info "Respaldo conservado: $BACKUP_DIR"
        return 1
    fi

    if ! spinner "Modificando configuración TLS de HCR" \
        modify_services "$mode" "$CERT_PATH" "$KEY_PATH"
    then
        error "No se pudieron modificar todos los servicios."
        rollback || true
        return 1
    fi

    if ! spinner "Actualizando configuración de systemd" reload_systemd; then
        error "No se pudo actualizar systemd."
        rollback || true
        return 1
    fi

    if ! spinner "Reiniciando servicios HCR" restart_services; then
        error "Falló el reinicio de los servicios."
        rollback || true
        return 1
    fi

    if ! spinner "Verificando servicios activos" verify_services; then
        error "Se detectaron servicios que no iniciaron."
        rollback || true
        return 1
    fi

    if ! spinner "Verificando configuración aplicada" verify_configuration; then
        error "La configuración activa de systemd no coincide."
        rollback || true
        return 1
    fi

    if cleanup_backup; then
        success "Respaldo temporal eliminado tras verificar."
    else
        warning "No se pudo eliminar el respaldo."
        info "Respaldo: $BACKUP_DIR"
    fi

    printf '\n'
    edit_line
    section "RESUMEN DE CONFIGURACIÓN"

    case "$mode" in
        tls)
            success "MODO SOLO TLS ACTIVADO"
            info "Únicamente conexiones TLS."
            ;;
        auto)
            success "MODO TLS Y PLAIN ACTIVADO"
            info "Conexiones TLS y sin TLS."
            ;;
        plain)
            if is_plain_active; then
                success "TLS DESACTIVADO"
                info "Todos los servicios están ejecutándose en PLAIN."
            else
                error "NO SE PUDO CONFIRMAR LA DESACTIVACIÓN TLS"
                info "El estado de los servicios no permite confirmar PLAIN."
                return 1
            fi
            ;;
    esac

    if [[ "$mode" != "plain" ]]; then
        printf '\n'
        info "Certificado: $CERT_PATH"
        info "Clave privada: $KEY_PATH"
    fi

    printf '\n'
    info "Servicios procesados: ${#SERVICES[@]}"

    if verify_services; then
        success "Todos los servicios están funcionando."
    else
        warning "Hay servicios que requieren atención."
    fi

    printf '\n'
    edit_line
    printf '\n'

    return 0
}

# ============================================================
#                 ESTADO GLOBAL VERIFICADO
# ============================================================

get_verified_global_mode() {
    local file
    local unit
    local transport
    local loaded_transport
    local cert
    local key
    local loaded_cert
    local loaded_key
    local first_mode=""
    local initialized=0

    for file in "${SERVICES[@]}"; do

        unit="$(basename "$file")"
        transport="$(get_transport "$file")"

        case "$transport" in
            tls|auto|plain)
                ;;
            *)
                printf 'unknown'
                return 0
                ;;
        esac

        loaded_transport="$(
            get_loaded_argument "$unit" "transport" 2>/dev/null
        )" || {
            printf 'unknown'
            return 0
        }

        [[ "$loaded_transport" == "$transport" ]] || {
            printf 'unknown'
            return 0
        }

        systemctl is-active --quiet "$unit" || {
            printf 'unknown'
            return 0
        }

        if (( initialized == 0 )); then
            first_mode="$transport"
            initialized=1
        elif [[ "$transport" != "$first_mode" ]]; then
            printf 'unknown'
            return 0
        fi

        if [[ "$transport" == "plain" ]]; then

            if get_argument "$file" "tls-cert" >/dev/null 2>&1; then
                printf 'unknown'
                return 0
            fi

            if get_argument "$file" "tls-key" >/dev/null 2>&1; then
                printf 'unknown'
                return 0
            fi

            if get_loaded_argument "$unit" "tls-cert" >/dev/null 2>&1; then
                printf 'unknown'
                return 0
            fi

            if get_loaded_argument "$unit" "tls-key" >/dev/null 2>&1; then
                printf 'unknown'
                return 0
            fi

        else

            cert="$(get_argument "$file" "tls-cert" 2>/dev/null)" || {
                printf 'unknown'
                return 0
            }

            key="$(get_argument "$file" "tls-key" 2>/dev/null)" || {
                printf 'unknown'
                return 0
            }

            loaded_cert="$(
                get_loaded_argument "$unit" "tls-cert" 2>/dev/null
            )" || {
                printf 'unknown'
                return 0
            }

            loaded_key="$(
                get_loaded_argument "$unit" "tls-key" 2>/dev/null
            )" || {
                printf 'unknown'
                return 0
            }

            [[ -n "$cert" && -n "$key" ]] || {
                printf 'unknown'
                return 0
            }

            [[ "$cert" == "$loaded_cert" ]] || {
                printf 'unknown'
                return 0
            }

            [[ "$key" == "$loaded_key" ]] || {
                printf 'unknown'
                return 0
            }
        fi
    done

    if (( initialized == 0 )); then
        printf 'unknown'
    else
        printf '%s' "$first_mode"
    fi
}

# -------------------- ESTADO DE CADA OPCIÓN -----------------

show_option_state() {
    local requested="$1"
    local current

    current="$(get_verified_global_mode)"

    if [[ "$current" == "$requested" ]]; then
        printf '%b[ON]%b' "$GREEN$BOLD" "$RESET"
    elif [[ "$current" == "tls" ||
            "$current" == "auto" ||
            "$current" == "plain" ]]; then
        printf '%b[OFF]%b' "$GRAY" "$RESET"
    else
        printf '%b[N/D]%b' "$YELLOW$BOLD" "$RESET"
    fi
}

# ============================================================
#        DESACTIVACIÓN SILENCIOSA CON COPIA DE SEGURIDAD
# ============================================================

disable_tls_silently() {
    local file
    local backup_file
    local failed=0

    SELECTED_MODE="plain"

    check_hcr_tls_support plain >/dev/null 2>&1 || return 1

    prepare_backup >/dev/null 2>&1 || return 1

    if ! create_backup >/dev/null 2>&1; then
        cleanup_backup >/dev/null 2>&1 || true
        return 1
    fi

    if ! modify_services plain "" "" >/dev/null 2>&1; then
        failed=1
    fi

    if (( failed == 0 )); then
        if ! reload_systemd >/dev/null 2>&1; then
            failed=1
        fi
    fi

    if (( failed == 0 )); then
        if ! restart_services >/dev/null 2>&1; then
            failed=1
        fi
    fi

    if (( failed == 0 )); then
        if ! verify_services >/dev/null 2>&1; then
            failed=1
        fi
    fi

    if (( failed == 0 )); then
        if ! verify_configuration >/dev/null 2>&1; then
            failed=1
        fi
    fi

    if (( failed == 0 )); then
        if [[ "$(get_verified_global_mode)" != "plain" ]]; then
            failed=1
        fi
    fi

    if (( failed == 0 )); then
        cleanup_backup >/dev/null 2>&1 || true
        return 0
    fi

    # -------------------- ROLLBACK SILENCIOSO ---------------

    for file in "${SERVICES[@]}"; do

        backup_file="$BACKUP_DIR/$(basename "$file")"

        if [[ ! -f "$backup_file" ]]; then
            failed=2
            continue
        fi

        if ! cp -a "$backup_file" "$file" >/dev/null 2>&1; then
            failed=2
        fi
    done

    if (( failed == 2 )); then
        return 1
    fi

    if ! systemctl daemon-reload >/dev/null 2>&1; then
        return 1
    fi

    if ! restart_services >/dev/null 2>&1; then
        return 1
    fi

    if ! verify_services >/dev/null 2>&1; then
        return 1
    fi

    cleanup_backup >/dev/null 2>&1 || true

    return 1
}

# ============================================================
#                 ACTIVAR MODALIDAD TLS / AUTO
# ============================================================

# Códigos:
#   0 = operación completada.
#   1 = error.
#   2 = cancelación del usuario.

toggle_tls_mode() {
    local mode="$1"
    local label="$2"
    local status=0

    MODE_LABEL="$label"

    edit_header

    if select_certificate; then
        :
    else
        status=$?
        return "$status"
    fi

    apply_configuration "$mode"
}

# ============================================================
#                 MENÚ PRINCIPAL
# ============================================================

show_menu() {
    header

    show_services

    printf '\n'
    line

    section "ADMINISTRACIÓN SSL / TLS"

    printf '  %b[1]%b  Modo solo TLS/SSL' "$GREEN$BOLD" "$RESET"
    printf '  '
    show_option_state "tls"
    printf '\n\n'

    printf '  %b[2]%b  Modo sin y con TLS/SSL' "$CYAN$BOLD" "$RESET"
    printf '  '
    show_option_state "auto"
    printf '\n\n'

    line
    printf '\n'

    printf '  %b[0]%b  Salir\n' "$RED$BOLD" "$RESET"

    printf '\n'
    line
    printf '\n'
}

# ============================================================
#                 EJECUCIÓN PRINCIPAL
# ============================================================

main() {
    local option
    local current_mode
    local status

    if (( EUID != 0 )); then
        printf '%b✗%b  Ejecuta este administrador como root.\n' "$RED" "$RESET"
        exit 1
    fi

    if ! check_requirements; then
        exit 1
    fi

    if ! detect_services; then
        exit 1
    fi

    while true; do

        if ! detect_services; then
            error "No se pudieron detectar los servicios HCR."
            break
        fi

        show_menu

        while true; do

            if ! read_option \
                "  ${CYAN}${BOLD}Selecciona una opción:${RESET} "; then
                printf '\n'
                return 0
            fi

            option="$OPTION_VALUE"

            case "$option" in

                1)
                    current_mode="$(get_verified_global_mode)"

                    if [[ "$current_mode" == "tls" ]]; then

                        if ! disable_tls_silently; then
                            error "No se pudo desactivar TLS. Revisa los servicios y el respaldo."
                            wait_for_enter || return 0
                        fi

                        break
                    fi

                    status=0

                    if toggle_tls_mode "tls" "MODO SOLO TLS/SSL"; then
                        wait_for_enter || return 0
                    else
                        status=$?

                        if (( status != 2 )); then
                            warning "No se pudo completar la operación."
                            wait_for_enter || return 0
                        fi
                    fi

                    break
                    ;;

                2)
                    current_mode="$(get_verified_global_mode)"

                    if [[ "$current_mode" == "auto" ]]; then

                        if ! disable_tls_silently; then
                            error "No se pudo desactivar AUTO. Revisa los servicios y el respaldo."
                            wait_for_enter || return 0
                        fi

                        break
                    fi

                    status=0

                    if toggle_tls_mode "auto" "MODO SIN Y CON TLS/SSL"; then
                        wait_for_enter || return 0
                    else
                        status=$?

                        if (( status != 2 )); then
                            warning "No se pudo completar la operación."
                            wait_for_enter || return 0
                        fi
                    fi

                    break
                    ;;

                0)
                    printf '\n'
                    success "Saliendo del administrador SSL/TLS."
                    printf '\n'
                    return 0
                    ;;

                *)
                    invalid_option
                    ;;
            esac
        done
    done
}

main "$@"
