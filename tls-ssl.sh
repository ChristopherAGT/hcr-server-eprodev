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

ACME_HOME="/root/.acme.sh"
ACME_BIN="$ACME_HOME/acme.sh"
ACME_RELOAD="/usr/local/sbin/hcr-acme-reload"

CERT_PATH=""
KEY_PATH=""
BACKUP_DIR=""
SELECTED_MODE=""
EXPECTED_HOST=""
SCAN_TMP=""
CERTIFICATE_TYPE=""
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

OPTION_VALUE=""

read_option() {
    local prompt="$1"
    printf '%b' "$prompt"
    IFS= read -r OPTION_VALUE
}

invalid_option() {
    local ignored

    warning "Opción inválida."
    IFS= read -r ignored || true

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
        sort stat curl getent ss tr wc
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

get_global_transport() {
    local file transport first=""
    local initialized=0 different=0

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
    local file active=0 inactive=0

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
    local transport label color
    local width=56 left_text right_text spaces

    transport="$(get_global_transport)"

    case "$transport" in
        tls) label="ACTUAL: TLS"; color="$GREEN$BOLD" ;;
        auto) label="ACTUAL: AUTO"; color="$CYAN$BOLD" ;;
        plain) label="ACTUAL: PLAIN"; color="$RED$BOLD" ;;
        mixed) label="ACTUAL: MIXED"; color="$YELLOW$BOLD" ;;
        *) label="ACTUAL: N/D"; color="$YELLOW$BOLD" ;;
    esac

    left_text="Servicios detectados: $count"
    right_text="$label"
    spaces=$(( width - ${#left_text} - ${#right_text} - 4 ))
    (( spaces < 1 )) && spaces=1

    printf '  %b%s%b%*s%b%s%b  \n' \
        "$GRAY" "$left_text" "$RESET" \
        "$spaces" '' "$color" "$right_text" "$RESET"
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

    openssl pkey -in "$key" -passin pass: -pubout -outform DER 2>/dev/null |
        sha256sum | awk '{print $1}'
}

validate_dates() {
    local cert="$1"
    local start end now

    start="$(openssl x509 -in "$cert" -noout -startdate 2>/dev/null)"
    end="$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null)"

    start="${start#*=}"
    end="${end#*=}"

    [[ -n "$start" && -n "$end" ]] || return 1

    start="$(date -u -d "$start" +%s 2>/dev/null)" || return 1
    end="$(date -u -d "$end" +%s 2>/dev/null)" || return 1
    now="$(date -u +%s)"

    (( now >= start && now <= end ))
}

validate_server_certificate() {
    local cert="$1"
    local extensions eku san

    openssl x509 -in "$cert" -noout >/dev/null 2>&1 || return 1

    extensions="$(openssl x509 -in "$cert" -noout -ext basicConstraints 2>/dev/null || true)"
    grep -qi 'CA:TRUE' <<<"$extensions" && return 1

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
import ipaddress, sys
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
    openssl x509 -in "$1" -out "$2" 2>/dev/null
}

validate_chain() {
    local cert="$1"
    local leaf

    leaf="$(mktemp /tmp/hcr-tls-leaf.XXXXXXXX)" || return 1

    if ! extract_leaf_certificate "$cert" "$leaf"; then
        rm -f "$leaf"
        return 1
    fi

    if openssl verify \
        -purpose sslserver \
        -CApath /etc/ssl/certs \
        -untrusted "$cert" \
        "$leaf" >/dev/null 2>&1; then
        rm -f "$leaf"
        return 0
    fi

    rm -f "$leaf"
    return 1
}

# ------------------------------------------------------------
# VALIDACIÓN DE CERTIFICADOS AUTOFIRMADOS
# ------------------------------------------------------------

validate_self_signed_chain() {
    local cert="$1"
    local leaf=""
    local issuer=""
    local subject=""
    local result=1

    leaf="$(mktemp /tmp/hcr-tls-selfsigned.XXXXXXXX)" || return 1

    if ! extract_leaf_certificate "$cert" "$leaf"; then
        rm -f "$leaf"
        return 1
    fi

    issuer="$(
        openssl x509 -in "$leaf" -noout -issuer -nameopt RFC2253 2>/dev/null
    )" || {
        rm -f "$leaf"
        return 1
    }

    subject="$(
        openssl x509 -in "$leaf" -noout -subject -nameopt RFC2253 2>/dev/null
    )" || {
        rm -f "$leaf"
        return 1
    }

    if [[ "${issuer#issuer=}" != "${subject#subject=}" ]]; then
        rm -f "$leaf"
        return 1
    fi

    if openssl verify \
        -check_ss_sig \
        -purpose sslserver \
        -CAfile "$leaf" \
        "$leaf" >/dev/null 2>&1; then
        result=0
    fi

    rm -f "$leaf"
    return "$result"
}

# ------------------------------------------------------------
# VALIDACIÓN GENERAL
# ------------------------------------------------------------

validate_certificate() {
    local cert="$1"
    local key="$2"
    local expected="${3:-}"
    local certificate_type="${4:-acme}"
    local cert_hash key_hash

    [[ -f "$cert" && -r "$cert" ]] || return 1
    [[ -f "$key" && -r "$key" ]] || return 1

    openssl x509 -in "$cert" -noout >/dev/null 2>&1 || return 1
    openssl pkey -in "$key" -passin pass: -noout >/dev/null 2>&1 || return 1

    validate_server_certificate "$cert" || return 1
    validate_dates "$cert" || return 1
    validate_hostname_match "$cert" "$expected" || return 1

    cert_hash="$(certificate_hash "$cert")" || return 1
    key_hash="$(private_key_hash "$key")" || return 1

    [[ -n "$cert_hash" && "$cert_hash" == "$key_hash" ]] || return 1

    case "$certificate_type" in
        acme)
            validate_chain "$cert" || return 1
            ;;
        selfsigned)
            validate_self_signed_chain "$cert" || return 1
            ;;
        *)
            return 1
            ;;
    esac

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
    local directory file hash

    KEY_HASHES=()
    KEY_SEEN=()

    local directories=(
        /etc /root /home /usr/local /opt
        /var/lib /var/www /srv
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
                \( -iname '*.key' -o -iname '*.pem' \
                -o -iname '*.p8' -o -iname '*.pk8' \
                -o -iname '*.priv' -o -iname 'privkey' \
                -o -iname 'private' \) \
                -print0 2>/dev/null
        )
    done
}

scan_certificates() {
    local directory cert hash key pair cert_type

    CERTIFICATES=()
    CERT_SEEN=()

    local directories=(
        /etc /root /home /usr/local /opt
        /var/lib /var/www /srv
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

            if validate_certificate "$cert" "$key" "$EXPECTED_HOST" "acme"; then
                cert_type="acme"
            elif validate_certificate "$cert" "$key" "$EXPECTED_HOST" "selfsigned"; then
                cert_type="selfsigned"
            else
                continue
            fi

            pair="$cert|$key|$cert_type"
            CERTIFICATES+=("$pair")
            CERT_SEEN["$hash"]="$cert"

        done < <(
            find -L "$directory" -maxdepth 10 -type f \
                \( -iname '*.pem' -o -iname '*.crt' \
                -o -iname '*.cer' -o -iname '*.cert' \) \
                -print0 2>/dev/null
        )
    done

    return 0
}

certificate_label() {
    local cert="$1"

    python3 - "$cert" <<'PY'
import re, subprocess, sys

try:
    output = subprocess.check_output(
        ["openssl", "x509", "-in", sys.argv[1],
         "-noout", "-ext", "subjectAltName"],
        stderr=subprocess.DEVNULL,
        text=True
    )
    names = re.findall(r'(?:DNS|IP Address):([^,\s]+)', output)
    if names:
        print(names[0])
        sys.exit(0)
except Exception:
    pass

print("Certificado SSL")
PY
}

show_certificates() {
    local entry cert label cert_type index=0

    for entry in "${CERTIFICATES[@]}"; do
        cert="${entry%%|*}"
        cert_type="${entry##*|}"
        label="$(certificate_label "$cert")"
        index=$((index + 1))

        printf '  %b[%s]%b  %b%s%b' \
            "$CYAN$BOLD" "$index" "$RESET" "$WHITE" "$label" "$RESET"

        if [[ "$cert_type" == "selfsigned" ]]; then
            printf '  %b[AUTOFIRMADO]%b' "$YELLOW" "$RESET"
        else
            printf '  %b[ACME / CA]%b' "$GREEN" "$RESET"
        fi

        printf '\n'
    done
}

# ============================================================
#              VALIDACIÓN DE DOMINIOS Y CORREO
# ============================================================

validate_hostname() {
    python3 - "$1" <<'PY'
import ipaddress, re, sys

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

if "." not in value:
    sys.exit(1)
PY
}

validate_email() {
    python3 - "$1" <<'PY'
import re, sys
value = sys.argv[1]
if not value:
    sys.exit(0)
if not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+', value):
    sys.exit(1)
PY
}

get_san_type() {
    python3 - "$1" <<'PY'
import ipaddress, sys
try:
    ipaddress.ip_address(sys.argv[1])
    print("IP")
except ValueError:
    print("DNS")
PY
}

# ============================================================
#          INSTALACIÓN SEGURA DE CERTIFICADOS
# ============================================================

install_certificate_pair() {
    local source_cert="$1"
    local source_key="$2"
    local hostname="$3"
    local certificate_type="${4:-acme}"
    local temp_cert=""
    local temp_key=""
    local old_cert=""
    local old_key=""
    local had_cert=0
    local had_key=0
    local timestamp

    install -d -o root -g root -m 700 "$TLS_DIR" || return 1

    temp_cert="$(mktemp "$TLS_DIR/.fullchain.XXXXXXXX")" || return 1
    temp_key="$(mktemp "$TLS_DIR/.privkey.XXXXXXXX")" || {
        rm -f "$temp_cert"
        return 1
    }

    if ! cp "$source_cert" "$temp_cert" ||
       ! cp "$source_key" "$temp_key"; then
        rm -f "$temp_cert" "$temp_key"
        return 1
    fi

    chmod 644 "$temp_cert"
    chmod 600 "$temp_key"
    chown root:root "$temp_cert" "$temp_key"

    if ! validate_certificate "$temp_cert" "$temp_key" "$hostname" "$certificate_type"; then
        rm -f "$temp_cert" "$temp_key"
        return 1
    fi

    timestamp="$(date '+%Y%m%d-%H%M%S')"

    if [[ -e "$CERT_FILE" ]]; then
        old_cert="$(mktemp "$TLS_DIR/.previous-cert.XXXXXXXX")" || {
            rm -f "$temp_cert" "$temp_key"
            return 1
        }
        cp -a "$CERT_FILE" "$old_cert" || {
            rm -f "$temp_cert" "$temp_key" "$old_cert"
            return 1
        }
        had_cert=1
    fi

    if [[ -e "$KEY_FILE" ]]; then
        old_key="$(mktemp "$TLS_DIR/.previous-key.XXXXXXXX")" || {
            rm -f "$temp_cert" "$temp_key" "$old_cert"
            return 1
        }
        cp -a "$KEY_FILE" "$old_key" || {
            rm -f "$temp_cert" "$temp_key" "$old_cert" "$old_key"
            return 1
        }
        had_key=1
    fi

    if ! mv -f "$temp_cert" "$CERT_FILE"; then
        rm -f "$temp_cert" "$temp_key" "$old_cert" "$old_key"
        return 1
    fi

    if ! mv -f "$temp_key" "$KEY_FILE"; then
        if (( had_cert )); then
            cp -a "$old_cert" "$CERT_FILE" || true
        else
            rm -f "$CERT_FILE"
        fi

        if (( had_key )); then
            cp -a "$old_key" "$KEY_FILE" || true
        else
            rm -f "$KEY_FILE"
        fi

        rm -f "$old_cert" "$old_key" "$temp_key"
        return 1
    fi

    chmod 644 "$CERT_FILE"
    chmod 600 "$KEY_FILE"
    chown root:root "$CERT_FILE" "$KEY_FILE"

    if (( had_cert )); then
        cp -a "$old_cert" "$TLS_DIR/fullchain.pem.previous-$timestamp"
    fi

    if (( had_key )); then
        cp -a "$old_key" "$TLS_DIR/privkey.pem.previous-$timestamp"
    fi

    rm -f "$old_cert" "$old_key"

    CERT_PATH="$CERT_FILE"
    KEY_PATH="$KEY_FILE"
    EXPECTED_HOST="$hostname"
    CERTIFICATE_TYPE="$certificate_type"

    return 0
}

# ============================================================
#              CERTIFICADOS AUTOFIRMADOS
# ============================================================

create_self_signed() {
    local hostname san_type subject
    local temp_cert="" temp_key=""
    local answer

    edit_header
    printf '\033[1A\033[2K'
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

    printf '\n'
    edit_line
    section "VERIFICACIÓN DEL DOMINIO / IP"

    info "Destino: $hostname"

    if ! validate_host_points_to_server "$hostname"; then
        warning "No se puede continuar con la generación."
        warning "El dominio o IP debe coincidir con el VPS."
        return 1
    fi

    success "Validación del destino superada."

    san_type="$(get_san_type "$hostname")"
    subject="/CN=$hostname"

    install -d -o root -g root -m 700 "$TLS_DIR" || {
        error "No se pudo preparar el directorio TLS."
        return 1
    }

    if [[ -e "$CERT_FILE" || -e "$KEY_FILE" ]]; then
        warning "Ya existen archivos en el directorio TLS."
        printf '\n'
        printf '  %b[1]%b  Respaldar y reemplazar\n' "$GREEN$BOLD" "$RESET"
        printf '  %b[0]%b  Cancelar\n\n' "$RED$BOLD" "$RESET"

        while true; do
            read_option "  ${CYAN}${BOLD}Selecciona una opción:${RESET} " || return 1
            answer="$OPTION_VALUE"

            case "$answer" in
                1) break ;;
                0) return 2 ;;
                *) invalid_option ;;
            esac
        done
    fi

    temp_cert="$(mktemp "$TLS_DIR/.selfsigned-cert.XXXXXXXX")" || return 1
    temp_key="$(mktemp "$TLS_DIR/.selfsigned-key.XXXXXXXX")" || {
        rm -f "$temp_cert"
        return 1
    }

    chmod 600 "$temp_cert" "$temp_key"

    if ! spinner "Generando certificado autofirmado" \
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
       ! validate_hostname_match "$temp_cert" "$hostname" ||
       ! validate_self_signed_chain "$temp_cert"; then
        rm -f "$temp_cert" "$temp_key"
        error "Falló la validación del certificado generado."
        return 1
    fi

    if ! install_certificate_pair "$temp_cert" "$temp_key" "$hostname" "selfsigned"; then
        rm -f "$temp_cert" "$temp_key"
        error "No se pudo instalar el certificado generado."
        return 1
    fi

    rm -f "$temp_cert" "$temp_key"

    success "Certificado autofirmado creado correctamente."
    info "Certificado: $CERT_PATH"
    info "Clave privada: $KEY_PATH"
    warning "Un certificado autofirmado no tendrá confianza pública automática."
    warning "Los clientes deberán confiar expresamente en él."

    return 0
}

# ============================================================
#                 ADMINISTRACIÓN ACME
# ============================================================

get_public_ipv4() {
    local ip=""

    ip="$(curl -4fsS --connect-timeout 8 --max-time 15 https://api.ipify.org 2>/dev/null || true)"

    if [[ -z "$ip" ]]; then
        ip="$(curl -4fsS --connect-timeout 8 --max-time 15 https://icanhazip.com 2>/dev/null || true)"
    fi

    python3 - "$ip" <<'PY'
import ipaddress, sys
try:
    ip = ipaddress.ip_address(sys.argv[1].strip())
    if ip.version != 4 or ip.is_private or ip.is_loopback:
        sys.exit(1)
    print(ip)
except Exception:
    sys.exit(1)
PY
}

get_domain_ipv4() {
    local domain="$1"

    getent ahostsv4 "$domain" 2>/dev/null |
        awk '{print $1}' |
        sort -u
}

get_public_ipv6() {
    local ip=""

    ip="$(curl -6fsS --connect-timeout 8 --max-time 15 \
        https://api6.ipify.org 2>/dev/null || true)"

    python3 - "$ip" <<'PY'
import ipaddress, sys

try:
    ip = ipaddress.ip_address(sys.argv[1].strip())
    if ip.version != 6 or not ip.is_global:
        sys.exit(1)
    print(ip)
except Exception:
    sys.exit(1)
PY
}

get_server_public_ips() {
    local ipv4="" ipv6=""

    ipv4="$(get_public_ipv4 2>/dev/null || true)"
    ipv6="$(get_public_ipv6 2>/dev/null || true)"

    [[ -n "$ipv4" ]] && printf '%s\n' "$ipv4"
    [[ -n "$ipv6" ]] && printf '%s\n' "$ipv6"
}

get_domain_ips() {
    local domain="$1"

    {
        getent ahostsv4 "$domain" 2>/dev/null || true
        getent ahostsv6 "$domain" 2>/dev/null || true
    } |
    awk '{print $1}' |
    python3 -c '
import ipaddress
import sys

ips = set()

for line in sys.stdin:
    raw = line.strip()

    try:
        ip = ipaddress.ip_address(raw)

        if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped:
            ip = ip.ipv4_mapped

        ips.add(str(ip))
    except ValueError:
        continue

for ip in sorted(ips):
    print(ip)
'
}

validate_host_points_to_server() {
    local hostname="$1"
    local server_ips=""
    local domain_ips=""
    local ip=""
    local is_ip=0
    local matched=0

    server_ips="$(get_server_public_ips)"

    if [[ -z "$server_ips" ]]; then
        error "No se pudieron detectar las IP públicas del VPS."
        return 1
    fi

    if python3 - "$hostname" <<'PY'
import ipaddress, sys

try:
    ipaddress.ip_address(sys.argv[1])
    sys.exit(0)
except ValueError:
    sys.exit(1)
PY
    then
        is_ip=1
    fi

    if (( is_ip )); then
        if grep -Fxq "$hostname" <<<"$server_ips"; then
            success "La dirección IP coincide con el VPS."
            return 0
        fi

        error "La dirección IP introducida no pertenece al VPS."
        info "IP introducida: $hostname"
        info "IP públicas detectadas: $(tr '\n' ' ' <<<"$server_ips")"
        return 1
    fi

    domain_ips="$(get_domain_ips "$hostname")"

    if [[ -z "$domain_ips" ]]; then
        error "El dominio no tiene registros DNS resolubles."
        return 1
    fi

    info "IP públicas del VPS: $(tr '\n' ' ' <<<"$server_ips")"
    info "IP del dominio: $(tr '\n' ' ' <<<"$domain_ips")"

    while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue

        if grep -Fxq "$ip" <<<"$server_ips"; then
            matched=1
        else
            error "Se encontró una IP DNS que no pertenece al VPS."
            info "IP no coincidente: $ip"
            return 1
        fi
    done <<<"$domain_ips"

    if (( matched == 0 )); then
        error "Ninguna IP del dominio coincide con el VPS."
        return 1
    fi

    success "Las direcciones DNS coinciden con el VPS."
    return 0
}

check_port_80() {
    ! ss -H -ltn '( sport = :80 )' 2>/dev/null | grep -q .
}

install_acme_client() {
    local installer=""
    local install_status=0

    if [[ -x "$ACME_BIN" ]]; then
        return 0
    fi

    info "Instalando cliente ACME..."

    installer="$(mktemp /tmp/hcr-acme-installer.XXXXXXXX)" || {
        error "No se pudo preparar el instalador."
        return 1
    }

    if ! curl -fsSL --retry 3 --retry-delay 2 \
        https://get.acme.sh -o "$installer"; then
        rm -f "$installer"
        error "No se pudo descargar el instalador de acme.sh."
        return 1
    fi

    if [[ ! -s "$installer" ]]; then
        rm -f "$installer"
        error "El instalador descargado está vacío."
        return 1
    fi

    chmod 700 "$installer"

    install -d -o root -g root -m 700 "$ACME_HOME"

    if [[ -n "${ACME_EMAIL:-}" ]]; then
        HOME=/root bash "$installer" "email=$ACME_EMAIL" ||
            install_status=$?
    else
        HOME=/root bash "$installer" ||
            install_status=$?
    fi

    rm -f "$installer"

    if (( install_status != 0 )); then
        error "El instalador de acme.sh terminó con errores."
        return 1
    fi

    if [[ ! -x "$ACME_BIN" ]]; then
        error "La instalación terminó, pero no se encontró acme.sh."
        return 1
    fi

    success "Cliente acme.sh instalado correctamente."
    return 0
}

create_acme_reload_hook() {
    local temp_hook
    local status=0

    temp_hook="$(mktemp /tmp/hcr-acme-hook.XXXXXXXX)" || return 1

    cat > "$temp_hook" <<'HOOK'
#!/usr/bin/env bash
set -u

SERVICE_DIR="/etc/systemd/system"
SERVICE_PREFIX="hcr-server"

shopt -s nullglob

for unit in "$SERVICE_DIR/${SERVICE_PREFIX}"*.service; do
    [[ -f "$unit" ]] || continue

    if grep -Eq -- '--transport(=|[[:space:]])(tls|auto)([[:space:]]|$)' "$unit" &&
       grep -Fq -- '--tls-cert=/etc/hcr-server/tls/fullchain.pem' "$unit" &&
       grep -Fq -- '--tls-key=/etc/hcr-server/tls/privkey.pem' "$unit"; then
        systemctl restart "$(basename "$unit")" >/dev/null 2>&1 || true
    fi
done

exit 0
HOOK

    if install -o root -g root -m 700 "$temp_hook" "$ACME_RELOAD"; then
        status=0
    else
        status=1
    fi

    rm -f "$temp_hook"
    return "$status"
}

acme_http01() {
    local domain=""
    local public_ip=""
    local dns_ips=""
    local email=""
    local answer=""
    local acme_cert=""
    local acme_key=""
    local acme_fullchain=""
    local acme_args=()

    ACME_EMAIL=""

    edit_header
    printf '\033[1A\033[2K'
    section "CERTIFICADO ACME HTTP-01"

    info "Autoridad certificadora: Let's Encrypt"
    info "Validación: HTTP-01"
    info "Puerto requerido: 80"
    info "Renovación: automática"

    printf '\n'
    edit_line
    printf '\n'

    ask "  ${CYAN}Introduce el subdominio:${RESET} " "" domain || return 1
    domain="${domain,,}"

    if ! validate_hostname "$domain"; then
        error "El nombre de dominio no es válido."
        return 1
    fi

    if [[ "$(get_san_type "$domain")" == "IP" ]]; then
        error "ACME HTTP-01 requiere un nombre de dominio DNS."
        return 1
    fi
    
    printf '\n'
    edit_line
    printf '\n'
    
    warning "Se comprobará la resolución DNS antes de emitir el certificado."

    printf '\n'
    edit_line
    section "VERIFICACIÓN DEL DOMINIO"

    info "Dominio: $domain"

    public_ip="$(get_public_ipv4)" || {
        error "No se pudo detectar la IP pública IPv4 del VPS."
        return 1
    }

    dns_ips="$(get_domain_ipv4 "$domain")"

    info "IP pública del VPS: $public_ip"

    if [[ -z "$dns_ips" ]]; then
        error "El dominio no tiene un registro A resoluble."
        return 1
    fi

    info "IP A del dominio: $(tr '\n' ' ' <<<"$dns_ips")"

    if [[ "$(printf '%s\n' "$dns_ips" | grep -cxF "$public_ip")" -eq 0 ]] ||
       [[ "$(printf '%s\n' "$dns_ips" | grep -vFx "$public_ip" | wc -l)" -gt 0 ]]; then
        error "La resolución DNS no coincide con la IP pública del VPS."
        warning "Corrige el registro A antes de solicitar el certificado."
        return 1
    fi

    success "La dirección IP del dominio coincide con el VPS."
    success "Verificación DNS superada."

    if ! check_port_80; then
        error "El puerto 80 está ocupado."
        warning "Detén temporalmente el servicio que lo utiliza."
        return 1
    fi

    success "Puerto 80 disponible."

    warning "HTTP-01 necesita que el puerto 80 sea accesible desde Internet."
    warning "En Cloudflare utiliza DNS only durante la emisión."

    printf '\n'
    edit_line
    printf '\n'

    ask "  ${CYAN}Correo de contacto (opcional):${RESET} " "" email || return 1

    if ! validate_email "$email"; then
        error "La dirección de correo no tiene un formato válido."
        return 1
    fi

    ACME_EMAIL="$email"

    if ! install_acme_client; then
        return 1
    fi

    if [[ -n "$email" ]]; then
        "$ACME_BIN" --register-account -m "$email" --server letsencrypt >/dev/null 2>&1 || {
            warning "No se pudo registrar el correo; se continuará con la emisión."
        }
    fi

    section "EMISIÓN DEL CERTIFICADO"

    info "Dominio: $domain"
    info "Algoritmo: ECC 256 bits"
    info "Método: standalone HTTP-01"

    if ! check_port_80; then
        error "El puerto 80 dejó de estar disponible."
        return 1
    fi

    acme_args=(
        --issue
        --server letsencrypt
        --standalone
        --httpport 80
        --keylength ec-256
        -d "$domain"
    )

    if [[ -n "$email" ]]; then
        acme_args+=(--accountemail "$email")
    fi

    if ! "$ACME_BIN" "${acme_args[@]}"; then
        error "Let's Encrypt no pudo emitir el certificado."
        warning "Comprueba DNS, firewall, NAT y accesibilidad externa del puerto 80."
        return 1
    fi

    acme_cert="$ACME_HOME/${domain}_ecc/${domain}.cer"
    acme_key="$ACME_HOME/${domain}_ecc/${domain}.key"
    acme_fullchain="$ACME_HOME/${domain}_ecc/fullchain.cer"

    [[ -s "$acme_key" ]] || {
        error "No se encontró la clave privada generada por ACME."
        return 1
    }

    [[ -s "$acme_fullchain" ]] || {
        error "No se encontró el certificado fullchain generado por ACME."
        return 1
    }

    if ! validate_certificate "$acme_fullchain" "$acme_key" "$domain" "acme"; then
        error "El certificado emitido no superó la validación."
        return 1
    fi

    if ! create_acme_reload_hook; then
        error "No se pudo crear el hook de renovación."
        return 1
    fi

    if ! install_certificate_pair "$acme_fullchain" "$acme_key" "$domain" "acme"; then
        error "No se pudo instalar el certificado ACME en HCR."
        return 1
    fi

    if ! "$ACME_BIN" --install-cert -d "$domain" --ecc \
        --key-file "$KEY_FILE" \
        --fullchain-file "$CERT_FILE" \
        --reloadcmd "$ACME_RELOAD"; then
        warning "No se pudo registrar la instalación automática de renovación."
        warning "El certificado actual sí fue instalado; revisa acme.sh."
        return 1
    fi

    chmod 644 "$CERT_FILE"
    chmod 600 "$KEY_FILE"
    chown root:root "$CERT_FILE" "$KEY_FILE"

    if ! validate_certificate "$CERT_FILE" "$KEY_FILE" "$domain" "acme"; then
        error "La copia final del certificado no superó la validación."
        return 1
    fi

    CERT_PATH="$CERT_FILE"
    KEY_PATH="$KEY_FILE"
    EXPECTED_HOST="$domain"
    CERTIFICATE_TYPE="acme"

    success "Certificado Let's Encrypt instalado correctamente."
    success "Renovación automática configurada."
    info "Certificado: $CERT_PATH"
    info "Clave privada: $KEY_PATH"
    info "Hook de renovación: $ACME_RELOAD"

    return 0
}

# ============================================================
#                 SELECCIONAR CERTIFICADO
# ============================================================

select_certificate() {
    local entry cert key choice index total numeric_choice cert_type

    EXPECTED_HOST=""
    CERT_PATH=""
    KEY_PATH=""
    CERTIFICATE_TYPE=""

    if ! scan_certificates; then
        error "No se pudo completar la búsqueda."
        return 1
    fi

    total="${#CERTIFICATES[@]}"

    if (( total > 0 )); then
        printf '  %b◆%b  %bCERTIFICADOS DISPONIBLES%b\n\n' \
            "$CYAN" "$RESET" "$WHITE$BOLD" "$RESET"

        show_certificates

        printf '\n'
        edit_line
        printf '\n'
        printf '  %b[0]%b  Salir\n' "$RED$BOLD" "$RESET"
        printf '\n'
        edit_line
        printf '\n'

        while true; do
            read_option "  ${CYAN}${BOLD}Selecciona una opción:${RESET} " || return 1
            choice="$OPTION_VALUE"

            [[ "$choice" == "0" ]] && return 2

            if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
                invalid_option
                continue
            fi

            numeric_choice="$choice"
            numeric_choice="${numeric_choice#"${numeric_choice%%[!0]*}"}"
            numeric_choice="${numeric_choice:-0}"

            if (( numeric_choice < 1 || numeric_choice > total )); then
                invalid_option
                continue
            fi

            index=$((numeric_choice - 1))
            entry="${CERTIFICATES[index]}"

            cert="${entry%%|*}"
            entry="${entry#*|}"
            key="${entry%%|*}"
            cert_type="${entry#*|}"

            if ! validate_certificate "$cert" "$key" "$EXPECTED_HOST" "$cert_type"; then
                error "El certificado ya no supera la validación."
                wait_for_enter || return 1
                continue
            fi

            CERT_PATH="$cert"
            KEY_PATH="$key"
            CERTIFICATE_TYPE="$cert_type"

            return 0
        done
    fi

    warning "No se encontraron certificados compatibles."

    printf '\n'
    edit_line
    printf '\n'

    printf '  %b[1]%b  Obtener certificado ACME HTTP-01\n' \
        "$GREEN$BOLD" "$RESET"

    printf '  %b[2]%b  Crear certificado autofirmado\n' \
        "$CYAN$BOLD" "$RESET"

    printf '\n'
    edit_line
    printf '\n'

    printf '  %b[0]%b  Salir\n' "$RED$BOLD" "$RESET"

    printf '\n'
    edit_line
    printf '\n'

    while true; do
        read_option "  ${CYAN}${BOLD}Selecciona una opción:${RESET} " || return 1
        choice="$OPTION_VALUE"

        case "$choice" in
            1)
                acme_http01
                return $?
                ;;
            2)
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
    local cert="$1" key="$2"

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
    local file temp_file

    if [[ "$mode" == "tls" || "$mode" == "auto" ]]; then
        validate_tls_paths "$cert" "$key" || {
            error "Las rutas TLS contienen caracteres no permitidos."
            return 1
        }
    fi

    for file in "${SERVICES[@]}"; do
        temp_file="$(mktemp)" || return 1

        if ! python3 - "$file" "$temp_file" "$mode" "$cert" "$key" <<'PY'
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

    if len(transport_matches) > 1 or len(cert_matches) > 1 or len(key_matches) > 1:
        sys.exit(1)

    line = cert_pattern.sub('', line)
    line = key_pattern.sub('', line)

    if transport_matches:
        line = transport_pattern.sub('--transport=' + mode, line, count=1)
    else:
        line = line.rstrip('\n') + ' --transport=' + mode + '\n'

    if mode in ('tls', 'auto'):
        if not cert or not key:
            sys.exit(1)

        line = line.rstrip('\n')
        line += ' --tls-cert=' + cert
        line += ' --tls-key=' + key + '\n'

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
    local file failed=0

    for file in "${SERVICES[@]}"; do
        if ! systemctl restart "$(basename "$file")" >/dev/null 2>&1; then
            failed=1
        fi
    done

    return "$failed"
}

verify_services() {
    local file failed=0

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
    local file unit transport loaded_transport
    local cert key loaded_cert loaded_key

    for file in "${SERVICES[@]}"; do
        unit="$(basename "$file")"

        transport="$(get_argument "$file" "transport")" || return 1
        loaded_transport="$(get_loaded_argument "$unit" "transport")" || return 1

        [[ "$transport" == "$SELECTED_MODE" ]] || return 1
        [[ "$loaded_transport" == "$SELECTED_MODE" ]] || return 1

        systemctl is-active --quiet "$unit" || return 1

        if [[ "$SELECTED_MODE" == "plain" ]]; then
            get_argument "$file" "tls-cert" >/dev/null 2>&1 && return 1
            get_argument "$file" "tls-key" >/dev/null 2>&1 && return 1
            get_loaded_argument "$unit" "tls-cert" >/dev/null 2>&1 && return 1
            get_loaded_argument "$unit" "tls-key" >/dev/null 2>&1 && return 1
        else
            cert="$(get_argument "$file" "tls-cert")" || return 1
            key="$(get_argument "$file" "tls-key")" || return 1
            loaded_cert="$(get_loaded_argument "$unit" "tls-cert")" || return 1
            loaded_key="$(get_loaded_argument "$unit" "tls-key")" || return 1

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
    local file backup_file failed=0

    warning "Restaurando la configuración original..."

    for file in "${SERVICES[@]}"; do
        backup_file="$BACKUP_DIR/$(basename "$file")"

        if [[ ! -f "$backup_file" ]]; then
            failed=1
            continue
        fi

        cp -a "$backup_file" "$file" || failed=1
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
        if ! validate_certificate \
            "$CERT_PATH" \
            "$KEY_PATH" \
            "$EXPECTED_HOST" \
            "${CERTIFICATE_TYPE:-acme}"; then

            error "Certificado o clave privada no válidos."
            return 1
        fi
    fi

    if ! check_hcr_tls_support "$mode"; then
        warning "No se modificó ningún servicio."
        return 1
    fi

    printf '\n'
    edit_line
    section "APLICANDO CONFIGURACIÓN"

    case "$mode" in
        tls) info "Transporte seleccionado: TLS" ;;
        auto) info "Transporte seleccionado: AUTO" ;;
        plain) info "Transporte seleccionado: PLAIN" ;;
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
        modify_services "$mode" "$CERT_PATH" "$KEY_PATH"; then
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
    local file transport cert key
    local first_mode=""
    local initialized=0

    for file in "${SERVICES[@]}"; do
        [[ -f "$file" ]] || {
            printf 'unknown'
            return 0
        }

        transport="$(get_transport "$file")"

        case "$transport" in
            tls|auto|plain) ;;
            *)
                printf 'unknown'
                return 0
                ;;
        esac

        if (( initialized == 0 )); then
            first_mode="$transport"
            initialized=1
        elif [[ "$transport" != "$first_mode" ]]; then
            printf 'unknown'
            return 0
        fi

        if [[ "$transport" == "plain" ]]; then
            if get_argument "$file" "tls-cert" >/dev/null 2>&1 ||
               get_argument "$file" "tls-key" >/dev/null 2>&1; then
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

            [[ -n "$cert" && -n "$key" ]] || {
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
    local file backup_file failed=0

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
        reload_systemd >/dev/null 2>&1 || failed=1
    fi

    if (( failed == 0 )); then
        restart_services >/dev/null 2>&1 || failed=1
    fi

    if (( failed == 0 )); then
        verify_services >/dev/null 2>&1 || failed=1
    fi

    if (( failed == 0 )); then
        verify_configuration >/dev/null 2>&1 || failed=1
    fi

    if (( failed == 0 )) && [[ "$(get_verified_global_mode)" == "plain" ]]; then
        cleanup_backup >/dev/null 2>&1 || true
        return 0
    fi

    for file in "${SERVICES[@]}"; do
        backup_file="$BACKUP_DIR/$(basename "$file")"

        [[ -f "$backup_file" ]] || return 1
        cp -a "$backup_file" "$file" >/dev/null 2>&1 || return 1
    done

    systemctl daemon-reload >/dev/null 2>&1 || return 1
    restart_services >/dev/null 2>&1 || return 1
    verify_services >/dev/null 2>&1 || return 1

    cleanup_backup >/dev/null 2>&1 || true

    return 1
}

# ============================================================
#                 ACTIVAR MODALIDAD TLS / AUTO
# ============================================================

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
#             ADMINISTRADOR DE CERTIFICADO ACTUAL
# ============================================================

get_active_certificate_pair() {
    local file unit transport cert key
    local first_cert="" first_key=""
    local initialized=0

    CERT_PATH=""
    KEY_PATH=""

    for file in "${SERVICES[@]}"; do
        unit="$(basename "$file")"
        transport="$(get_argument "$file" "transport" 2>/dev/null || true)"

        case "$transport" in
            tls|auto) ;;
            *)
                error "HCR no está configurado globalmente con TLS/AUTO."
                return 1
                ;;
        esac

        cert="$(get_argument "$file" "tls-cert" 2>/dev/null)" || {
            error "No se pudo leer el certificado de $unit."
            return 1
        }

        key="$(get_argument "$file" "tls-key" 2>/dev/null)" || {
            error "No se pudo leer la clave privada de $unit."
            return 1
        }

        loaded_cert="$(get_loaded_argument "$unit" "tls-cert" 2>/dev/null)" || {
            error "No se pudo verificar el certificado cargado por systemd."
            return 1
        }

        loaded_key="$(get_loaded_argument "$unit" "tls-key" 2>/dev/null)" || {
            error "No se pudo verificar la clave cargada por systemd."
            return 1
        }

        if [[ "$cert" != "$loaded_cert" || "$key" != "$loaded_key" ]]; then
            error "La configuración cargada no coincide en $unit."
            return 1
        fi

        if (( initialized == 0 )); then
            first_cert="$cert"
            first_key="$key"
            initialized=1
        elif [[ "$cert" != "$first_cert" || "$key" != "$first_key" ]]; then
            error "Los servicios HCR utilizan certificados diferentes."
            warning "No se realizará ninguna operación global."
            return 1
        fi
    done

    (( initialized == 1 )) || return 1

    CERT_PATH="$first_cert"
    KEY_PATH="$first_key"

    [[ -f "$CERT_PATH" && -f "$KEY_PATH" ]] || {
        error "No se encontraron los archivos del certificado o la clave."
        return 1
    }

    return 0
}

get_certificate_domain() {
    local cert="$1"

    python3 - "$cert" <<'PY'
import re
import subprocess
import sys

try:
    output = subprocess.check_output(
        ["openssl", "x509", "-in", sys.argv[1],
         "-noout", "-ext", "subjectAltName"],
        stderr=subprocess.DEVNULL,
        text=True
    )

    names = re.findall(r'DNS:([^,\s]+)', output)
    if names:
        print(names[0])
        sys.exit(0)

    names = re.findall(r'IP Address:([^,\s]+)', output)
    if names:
        print(names[0])
        sys.exit(0)

except Exception:
    pass

try:
    subject = subprocess.check_output(
        ["openssl", "x509", "-in", sys.argv[1],
         "-noout", "-subject", "-nameopt", "RFC2253"],
        stderr=subprocess.DEVNULL,
        text=True
    )

    match = re.search(r'(?:^|,)CN=([^,]+)', subject.strip())
    if match:
        print(match.group(1))
        sys.exit(0)
except Exception:
    pass

sys.exit(1)
PY
}

get_certificate_type() {
    local cert="$1"
    local domain="$2"
    local issuer subject acme_conf

    issuer="$(openssl x509 -in "$cert" -noout -issuer -nameopt RFC2253 2>/dev/null || true)"
    subject="$(openssl x509 -in "$cert" -noout -subject -nameopt RFC2253 2>/dev/null || true)"

    if [[ "${issuer#issuer=}" == "${subject#subject=}" ]]; then
        printf 'selfsigned'
        return 0
    fi

    if [[ -n "$domain" ]]; then
        for acme_conf in \
            "$ACME_HOME/${domain}_ecc/${domain}.conf" \
            "$ACME_HOME/${domain}/${domain}.conf"
        do
            if [[ -f "$acme_conf" ]]; then
                printf 'acme'
                return 0
            fi
        done
    fi

    printf 'acme'
}

format_certificate_date() {
    local cert="$1"
    local raw

    raw="$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null)"
    raw="${raw#*=}"

    date -d "$raw" '+%d/%m/%Y' 2>/dev/null || printf 'NO DISPONIBLE'
}

get_certificate_status() {
    local cert="$1"
    local start end now

    start="$(openssl x509 -in "$cert" -noout -startdate 2>/dev/null)"
    end="$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null)"

    start="${start#*=}"
    end="${end#*=}"

    start="$(date -u -d "$start" +%s 2>/dev/null)" || {
        printf 'INVALID'
        return 0
    }

    end="$(date -u -d "$end" +%s 2>/dev/null)" || {
        printf 'INVALID'
        return 0
    }

    now="$(date -u +%s)"

    if (( now < start )); then
        printf 'NOTYET'
    elif (( now > end )); then
        printf 'EXPIRED'
    else
        printf 'ACTIVE'
    fi
}

get_certificate_diagnostic() {
    local cert="$1"
    local key="$2"
    local cert_type="$3"
    local domain="$4"
    local status="$5"
    local cert_hash key_hash

    [[ -f "$cert" && -r "$cert" ]] || {
        printf 'No se encuentra el archivo del certificado.'
        return 0
    }

    [[ -f "$key" && -r "$key" ]] || {
        printf 'No se encuentra la clave privada.'
        return 0
    }

    if ! openssl x509 -in "$cert" -noout >/dev/null 2>&1; then
        printf 'El archivo del certificado no es válido.'
        return 0
    fi

    if ! openssl pkey -in "$key" -passin pass: -noout >/dev/null 2>&1; then
        printf 'La clave privada no es válida.'
        return 0
    fi

    cert_hash="$(certificate_hash "$cert" 2>/dev/null || true)"
    key_hash="$(private_key_hash "$key" 2>/dev/null || true)"

    if [[ -z "$cert_hash" || "$cert_hash" != "$key_hash" ]]; then
        printf 'La clave privada no coincide con el certificado.'
        return 0
    fi

    if ! validate_server_certificate "$cert"; then
        printf 'El certificado no cumple los requisitos TLS de servidor.'
        return 0
    fi

    if [[ -n "$domain" ]] && ! validate_hostname_match "$cert" "$domain"; then
        printf 'El dominio no coincide con los nombres SAN del certificado.'
        return 0
    fi

    case "$status" in
        EXPIRED)
            printf 'Certificado vencido; la clave privada coincide.'
            return 0
            ;;
        NOTYET)
            printf 'El certificado todavía no se encuentra vigente.'
            return 0
            ;;
        INVALID)
            printf 'No se pudieron interpretar las fechas del certificado.'
            return 0
            ;;
    esac

    if [[ "$cert_type" == "selfsigned" ]]; then
        if validate_self_signed_chain "$cert"; then
            printf 'Certificado autofirmado válido, vigente y con clave coincidente.'
        else
            printf 'La firma del certificado autofirmado no es válida.'
        fi
    else
        if validate_chain "$cert"; then
            printf 'Certificado válido, vigente y con clave coincidente.'
        else
            printf 'La cadena de confianza del certificado no es válida.'
        fi
    fi
}

show_current_certificate() {
    local cert="$1"
    local key="$2"
    local domain="$3"
    local cert_type="$4"
    local status="$5"
    local expiry issuer subject san diagnostic
    local type_label status_label status_color

    expiry="$(format_certificate_date "$cert")"
    issuer="$(openssl x509 -in "$cert" -noout -issuer -nameopt RFC2253 2>/dev/null)"
    subject="$(openssl x509 -in "$cert" -noout -subject -nameopt RFC2253 2>/dev/null)"
    issuer="${issuer#issuer=}"
    subject="${subject#subject=}"

    case "$cert_type" in
        selfsigned)
            type_label="AUTOFIRMADO"
            ;;
        *)
            type_label="ACME"
            ;;
    esac

    case "$status" in
        ACTIVE)
            status_label="ACTIVO"
            status_color="$GREEN$BOLD"
            ;;
        EXPIRED)
            status_label="VENCIDO"
            status_color="$RED$BOLD"
            ;;
        NOTYET)
            status_label="NO VIGENTE"
            status_color="$YELLOW$BOLD"
            ;;
        *)
            status_label="NO VÁLIDO"
            status_color="$RED$BOLD"
            ;;
    esac

    diagnostic="$(get_certificate_diagnostic "$cert" "$key" "$cert_type" "$domain" "$status")"
    
    printf '\033[1A\033[2K'
    section "INFORMACIÓN DEL CERTIFICADO"

    printf '  %bDominio:%b       %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE" "${domain:-NO DISPONIBLE}" "$RESET"

    printf '  %bTipo:%b          %b%s%b\n' \
        "$GRAY" "$RESET" "$CYAN$BOLD" "$type_label" "$RESET"

    printf '  %bVencimiento:%b   %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE" "$expiry" "$RESET"

    printf '  %bEmisor:%b        %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE" "$issuer" "$RESET"

    printf '  %bSujeto:%b        %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE" "$subject" "$RESET"

    printf '  %bEstado:%b        %b[%s]%b\n' \
        "$GRAY" "$RESET" "$status_color" "$status_label" "$RESET"

    printf '\n'
    printf '  %bDiagnóstico:%b   %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE" "$diagnostic" "$RESET"

    printf '  %bCertificado:%b   %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE" "$cert" "$RESET"

    printf '  %bClave:%b         %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE" "$key" "$RESET"

    san="$(openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null || true)"

    san_value="$(sed '1d' <<<"$san" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

    if [[ -n "$san_value" ]]; then
        printf '  %bSAN:%b           %s\n' "$GRAY" "$RESET" "$san_value"
    else
        printf '  %bSAN:%b           %bNo disponible%b\n' "$GRAY" "$RESET" "$RED" "$RESET"
    fi

    printf '\n'
    edit_line
    printf '\n'
}

# ------------------------------------------------------------
# LOCALIZAR CONFIGURACIÓN DE RENOVACIÓN ACME
# ------------------------------------------------------------

get_acme_config_for_domain() {
    local domain="$1"
    local candidate

    for candidate in \
        "$ACME_HOME/${domain}_ecc/${domain}.conf" \
        "$ACME_HOME/${domain}/${domain}.conf"
    do
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

is_managed_tls_path() {
    local path="$1"

    case "$path" in
        "$TLS_DIR/fullchain.pem"|"$TLS_DIR/privkey.pem")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# RENOVAR CERTIFICADO ACTUAL
# ------------------------------------------------------------

renew_current_certificate() {
    local acme_directory=""
    local acme_key=""
    local acme_fullchain=""
    local acme_args=()
    local install_args=()
    local cert="$1"
    local key="$2"
    local domain="$3"
    local cert_type="$4"
    local temp_cert=""
    local temp_key=""
    local san_type=""
    local subject=""
    local acme_conf=""

    edit_header
    printf '\033[1A\033[2K'
    section "RENOVACIÓN DEL CERTIFICADO"

    info "Dominio: $domain"
    info "Tipo: $([[ "$cert_type" == "selfsigned" ]] && printf 'AUTOFIRMADO' || printf 'ACME')"

        if [[ "$cert_type" == "acme" ]]; then
        acme_conf="$(get_acme_config_for_domain "$domain" 2>/dev/null || true)"

        if [[ -z "$acme_conf" || ! -s "$acme_conf" ]]; then
            error "No existe la configuración original de renovación ACME."
            warning "No se modificará el certificado instalado."
            warning "Es necesario recuperar o volver a emitir el certificado."
            return 1
        fi

        if [[ ! -x "$ACME_BIN" ]]; then
            error "No se encontró el ejecutable acme.sh."
            return 1
        fi

        if [[ ! -s "$ACME_HOME/account.conf" ]]; then
            warning "No se encontró account.conf; se comprobará la renovación."
        fi

        if [[ "$acme_conf" == *"_ecc/"* ]]; then
            acme_directory="$ACME_HOME/${domain}_ecc"
            acme_key="$acme_directory/${domain}.key"
            acme_fullchain="$acme_directory/fullchain.cer"
            acme_args=(--renew -d "$domain" --ecc --force)
            install_args=(--install-cert -d "$domain" --ecc)
        else
            acme_directory="$ACME_HOME/$domain"
            acme_key="$acme_directory/${domain}.key"
            acme_fullchain="$acme_directory/fullchain.cer"
            acme_args=(--renew -d "$domain" --force)
            install_args=(--install-cert -d "$domain")
        fi

        if [[ ! -s "$acme_key" || ! -s "$acme_fullchain" ]]; then
            warning "Faltan los archivos originales del certificado ACME."
            info "Directorio esperado: $acme_directory"
            error "No es posible renovar con la configuración incompleta."
            return 1
        fi

        printf '\n'
        warning "Se solicitará la renovación mediante la configuración original."
        warning "No se eliminará el directorio interno de acme.sh."
        printf '\n'

        if ! "$ACME_BIN" "${acme_args[@]}"; then
            error "ACME no pudo renovar el certificado."
            warning "Comprueba el método de validación original y sus recursos."
            return 1
        fi

        if [[ ! -s "$acme_key" || ! -s "$acme_fullchain" ]]; then
            error "ACME no generó los archivos esperados."
            return 1
        fi

        if ! validate_certificate \
            "$acme_fullchain" "$acme_key" "$domain" "acme"; then
            error "El certificado renovado no superó la validación."
            return 1
        fi

        if ! create_acme_reload_hook; then
            error "No se pudo preparar el hook de renovación."
            return 1
        fi

        if ! install_certificate_pair \
            "$acme_fullchain" "$acme_key" "$domain" "acme"; then
            error "No se pudo instalar el certificado renovado."
            return 1
        fi

        if ! "$ACME_BIN" "${install_args[@]}" \
            --key-file "$KEY_FILE" \
            --fullchain-file "$CERT_FILE" \
            --reloadcmd "$ACME_RELOAD"; then
            error "No se pudo registrar la instalación automática."
            warning "Los archivos de renovación ACME se conservarán."
            return 1
        fi

        chmod 644 "$CERT_FILE"
        chmod 600 "$KEY_FILE"
        chown root:root "$CERT_FILE" "$KEY_FILE"

        if ! validate_certificate "$CERT_FILE" "$KEY_FILE" "$domain" "acme"; then
            error "La copia instalada no superó la validación."
            return 1
        fi

        CERT_PATH="$CERT_FILE"
        KEY_PATH="$KEY_FILE"
        EXPECTED_HOST="$domain"
        CERTIFICATE_TYPE="acme"

    else
        san_type="$(get_san_type "$domain")"
        subject="/CN=$domain"

        install -d -o root -g root -m 700 "$TLS_DIR" || return 1

        temp_cert="$(mktemp "$TLS_DIR/.renew-cert.XXXXXXXX")" || return 1
        temp_key="$(mktemp "$TLS_DIR/.renew-key.XXXXXXXX")" || {
            rm -f "$temp_cert"
            return 1
        }

        chmod 600 "$temp_cert" "$temp_key"

        if ! spinner "Generando nuevo certificado autofirmado" \
            openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "$temp_key" \
            -out "$temp_cert" \
            -days 365 \
            -subj "$subject" \
            -addext "subjectAltName=$san_type:$domain" \
            -addext "extendedKeyUsage=serverAuth" \
            -addext "basicConstraints=critical,CA:FALSE"; then
            rm -f "$temp_cert" "$temp_key"
            error "No se pudo generar el nuevo certificado."
            return 1
        fi

        if ! validate_certificate "$temp_cert" "$temp_key" "$domain" "selfsigned"; then
            rm -f "$temp_cert" "$temp_key"
            error "El nuevo certificado autofirmado no superó la validación."
            return 1
        fi

        if ! install_certificate_pair "$temp_cert" "$temp_key" "$domain" "selfsigned"; then
            rm -f "$temp_cert" "$temp_key"
            error "No se pudo instalar el certificado renovado."
            return 1
        fi

        rm -f "$temp_cert" "$temp_key"
    fi

    if ! restart_services; then
        error "El certificado se renovó, pero no se pudieron reiniciar todos los servicios."
        warning "Verifica el estado de los servicios HCR."
        return 1
    fi

    if ! verify_services; then
        error "Uno o más servicios HCR no están activos."
        return 1
    fi
    
    printf '\n'
    edit_line
    printf '\n'

    success "Certificado renovado correctamente."
    info "Nuevo vencimiento: $(format_certificate_date "$CERT_PATH")"
    
    printf '\n'
    edit_line

    return 0
}

#----------------------‐--------------------------------------
#JAJAJAJAJAJA
#-------------------------------------------------------------

cleanup_acme_hook_if_unused() {
    local conf

    [[ -f "$ACME_RELOAD" ]] || return 0

    if [[ -d "$ACME_HOME" ]]; then
        while IFS= read -r -d '' conf; do
            if grep -Fq "$ACME_RELOAD" "$conf" 2>/dev/null; then
                return 0
            fi
        done < <(
            find "$ACME_HOME" -type f -name '*.conf' -print0 2>/dev/null
        )
    fi

    rm -f -- "$ACME_RELOAD"
}

cleanup_acme_domain() {
    local domain="$1"
    local acme_conf="$2"
    local acme_directory=""
    local expected_ecc="$ACME_HOME/${domain}_ecc"
    local expected_standard="$ACME_HOME/$domain"

    [[ -n "$acme_conf" && -f "$acme_conf" ]] || return 1

    case "$acme_conf" in
        "$expected_ecc/"*.conf)
            acme_directory="$expected_ecc"
            ;;
        "$expected_standard/"*.conf)
            acme_directory="$expected_standard"
            ;;
        *)
            error "La configuración ACME está fuera de la ruta esperada."
            return 1
            ;;
    esac

    # Solo se elimina el directorio exacto del dominio.
    [[ -d "$acme_directory" && ! -L "$acme_directory" ]] || return 1

    if [[ -x "$ACME_BIN" ]]; then
        if [[ "$acme_directory" == "$expected_ecc" ]]; then
            "$ACME_BIN" --remove -d "$domain" --ecc >/dev/null 2>&1 || true
        else
            "$ACME_BIN" --remove -d "$domain" >/dev/null 2>&1 || true
        fi
    fi

    rm -rf -- "$acme_directory" || return 1

    success "Archivos internos ACME del dominio eliminados."

    cleanup_acme_hook_if_unused || {
        warning "No se pudo eliminar el hook ACME."
    }

    return 0
}

# ------------------------------------------------------------
# REMOVER CERTIFICADO ACTUAL
# ------------------------------------------------------------

remove_current_certificate() {
    local cert="$1"
    local key="$2"
    local domain="$3"
    local cert_type="$4"
    local acme_conf=""
    local remove_managed_files=0
    local answer

    edit_header
    printf '\033[1A\033[2K'
    section "REMOVER CERTIFICADO"

    warning "Esta operación desactivará TLS/AUTO en todos los servicios HCR."
    warning "Se eliminarán los recursos del certificado administrado."
    printf '\n'

    info "Dominio: $domain"
    info "Certificado: $cert"
    info "Clave privada: $key"

    printf '\n'
    edit_line
    printf '\n'
    
    printf '  %b[1]%b  Confirmar eliminación\n' "$RED$BOLD" "$RESET"
    
    printf '\n'
    edit_line
    printf '\n'
    
    printf '  %b[0]%b  Cancelar\n\n' "$GRAY$BOLD" "$RESET"
    
    edit_line
    printf '\n'

    while true; do
        read_option "  ${CYAN}${BOLD}Selecciona una opción:${RESET} " || return 1
        answer="$OPTION_VALUE"

        case "$answer" in
            1) break ;;
            0) return 2 ;;
            *) invalid_option ;;
        esac
    done

    # No se eliminan archivos externos.
    if is_managed_tls_path "$cert" && is_managed_tls_path "$key"; then
        remove_managed_files=1
    fi

    # Localizar la configuración ACME únicamente si HCR administra
    # ambos destinos de instalación del certificado.
    if [[ "$cert_type" == "acme" && "$remove_managed_files" -eq 1 ]]; then
        acme_conf="$(get_acme_config_for_domain "$domain" 2>/dev/null || true)"

        if [[ -n "$acme_conf" ]]; then
            if ! grep -Fq "$CERT_FILE" "$acme_conf" ||
               ! grep -Fq "$KEY_FILE" "$acme_conf"; then
                warning "La configuración ACME no confirma las rutas administradas."
                warning "Se conservarán los recursos internos ACME."
                acme_conf=""
            fi
        else
            warning "No se encontró la configuración ACME del dominio."
            warning "Se eliminarán los archivos HCR, pero no se tocarán otros datos."
        fi
    fi

    printf '\n'
    edit_line
    section "ELIMINANDO CERTIFICADO"

    # Desactivar TLS antes de eliminar cualquier archivo.
    if ! disable_tls_silently; then
        error "No se pudo desactivar TLS correctamente."
        warning "Los archivos del certificado se conservarán."
        return 1
    fi

    if (( remove_managed_files )); then
        rm -f -- "$CERT_FILE" "$KEY_FILE" || {
            error "No se pudieron eliminar los archivos principales."
            return 1
        }

        # Copias anteriores y temporales creados por este administrador.
        rm -f -- \
            "$TLS_DIR"/fullchain.pem.previous-* \
            "$TLS_DIR"/privkey.pem.previous-* \
            "$TLS_DIR"/.fullchain.* \
            "$TLS_DIR"/.privkey.* \
            "$TLS_DIR"/.previous-cert.* \
            "$TLS_DIR"/.previous-key.* \
            "$TLS_DIR"/.selfsigned-cert.* \
            "$TLS_DIR"/.selfsigned-key.* \
            "$TLS_DIR"/.renew-cert.* \
            "$TLS_DIR"/.renew-key.*

        success "Certificado, clave y copias administradas eliminados."
    else
        warning "El certificado utiliza rutas externas."
        warning "Los archivos externos se conservaron para proteger recursos ajenos."
    fi

    # Eliminar el registro ACME y su directorio solo si se confirmó
    # que ese dominio instala los archivos administrados por HCR.
    if [[ -n "$acme_conf" ]]; then
        if ! cleanup_acme_domain "$domain" "$acme_conf"; then
            warning "No se pudo completar toda la limpieza ACME."
            info "Revisa manualmente: $ACME_HOME"
        fi
    fi

    rmdir "$TLS_DIR" 2>/dev/null || true

    success "El certificado dejó de estar asociado a los servicios HCR."
    success "Los servicios quedaron configurados en PLAIN."
    
    printf '\n'
    edit_line

    return 0
}

# ------------------------------------------------------------
# MENÚ DE INFORMACIÓN Y ADMINISTRACIÓN DEL CERTIFICADO
# ------------------------------------------------------------

certificate_manager() {
    local cert key domain cert_type status choice result

    MODE_LABEL="ADMINISTRACIÓN DE CERTIFICADO"
    edit_header

    if ! get_active_certificate_pair; then
        warning "No se encontró un certificado TLS activo y común a los servicios."
        printf '\n'
        info "Activa primero TLS o AUTO desde el menú principal."
        return 1
    fi

    domain="$(get_certificate_domain "$CERT_PATH" 2>/dev/null || true)"

    if [[ -z "$domain" ]]; then
        error "No se pudo identificar el dominio del certificado."
        return 1
    fi

    cert="$CERT_PATH"
    key="$KEY_PATH"
    cert_type="$(get_certificate_type "$cert" "$domain")"
    status="$(get_certificate_status "$cert")"

    show_current_certificate "$cert" "$key" "$domain" "$cert_type" "$status"

    printf '  %b[1]%b  Remover certificado\n' "$RED$BOLD" "$RESET"
    printf '  %b[2]%b  Renovar certificado\n' "$GREEN$BOLD" "$RESET"
    
    printf '\n'
    edit_line
    printf '\n'
    
    printf '  %b[0]%b  Salir\n' "$GRAY$BOLD" "$RESET"

    printf '\n'
    edit_line
    printf '\n'

    while true; do
        read_option "  ${CYAN}${BOLD}Selecciona una opción:${RESET} " || return 0
        choice="$OPTION_VALUE"

        case "$choice" in
            1)
                remove_current_certificate "$cert" "$key" "$domain" "$cert_type"
                result=$?
                return "$result"
                ;;
            2)
                renew_current_certificate "$cert" "$key" "$domain" "$cert_type"
                result=$?
                return "$result"
                ;;
            0)
                return 0
                ;;
                *)
                invalid_option
                ;;
        esac
    done
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
    printf '\n'

    printf '  %b[2]%b  Modo sin y con TLS/SSL' "$CYAN$BOLD" "$RESET"
    printf '  '
    show_option_state "auto"
    printf '\n'

    printf '  %b[3]%b  Certificado SSL\n' "$MAGENTA$BOLD" "$RESET"

    printf '\n'
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
    local option current_mode status

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
            if ! read_option "  ${CYAN}${BOLD}Selecciona una opción:${RESET} "; then
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

                3)
                    status=0

                    if certificate_manager; then
                        wait_for_enter || return 0
                    else
                        status=$?

                        if (( status != 2 )); then
                            warning "No se pudo completar la operación del certificado."
                            wait_for_enter || return 0
                        fi
                    fi
                    break
                    ;;

                0)
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
