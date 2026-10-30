#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#                 HCR SERVER | MULTIPORT
#                  INSTALLER PRO
# ============================================================
#
# FUNCIONES:
#   - Descarga automática del binario HCR.
#   - Instalación multipuerto independiente.
#   - Un servicio systemd por cada puerto.
#   - Transporte PLAIN (sin TLS).
#   - Configuración explícita de parámetros del binario.
#   - Validación de puertos y conflictos.
#   - Spinner animado de seis puntos.
#   - Consultas reciclables sin duplicar líneas.
#
# ============================================================

# -------------------- CONFIGURACIÓN -------------------------

REPOSITORY_BINARY="https://raw.githubusercontent.com/ChristopherAGT/hcr-server-eprodev/main/hcr-server"

INSTALL_DIR="/usr/local/lib/hcr-server"
BINARY_PATH="$INSTALL_DIR/hcr-server"

SERVICE_PREFIX="hcr-server"

DEFAULT_PORTS="8080"
DEFAULT_TARGET_PORT="22"

TRANSPORT="plain"
TARGET_HOST="127.0.0.1"

MAX_CONNECTIONS=2048
MAX_SESSIONS=32
MAX_SESSIONS_PER_IP=16

MAX_DOWNLOAD_FRAME=16384
DOWNLOAD_POLL_TIMEOUT="25s"

DIAGNOSTICS_INTERVAL=0
SESSION_STATS_INTERVAL=0

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
    printf '%b\n' "${DIM}────────────────────────────────────────────────────────${RESET}"
}

success() {
    printf '  %b✓%b  %b\n' "$GREEN" "$RESET" "$1"
}

error() {
    printf '  %b✗%b  %b\n' "$RED" "$RESET" "$1"
}

info() {
    printf '  %b›%b  %b\n' "$CYAN" "$RESET" "$1"
}

warning() {
    printf '  %b!%b  %b%b%b\n' "$YELLOW" "$RESET" "$YELLOW" "$1" "$RESET"
}

section() {
    printf '\n'
    printf '  %b%s%b\n' "$BLUE$BOLD" "$1" "$RESET"
    printf '\n'
}

# -------------------- ENCABEZADO ----------------------------

header() {
    clear 2>/dev/null || true

    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="I N S T A L A D O R"

    printf '\n\n'

    printf '%*s%bHCR%b %bSERVER%b %bEPRO DEV%b\n' \
        "$(( (width - ${#title}) / 2 ))" '' \
        "$CYAN" "$RESET" \
        "$WHITE" "$RESET" \
        "$MAGENTA" "$RESET"

    printf '%*s%b%s%b\n' \
        "$(( (width - ${#subtitle}) / 2 ))" '' \
        "$DIM$GRAY" "$subtitle" "$RESET"

    printf '\n'
    line
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

    "$@" >/dev/null 2>&1 &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %b%s%b  %s' \
            "$CYAN" "${frames[i]}" "$RESET" "$message"

        i=$(( (i + 1) % 6 ))
        sleep 0.10
    done

    wait "$pid" || status=$?

    if (( status == 0 )); then
        printf '\r\033[2K  %b✓%b  %s\n' "$GREEN" "$RESET" "$message"
    else
        printf '\r\033[2K  %b✗%b  %s\n' "$RED" "$RESET" "$message"
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

# -------------------- ESPERA Y RECICLAJE --------------------

wait_and_recycle() {
    local message="$1"
    local ignored

    warning "$message"

    # Espera ENTER sin imprimir ningún texto.
    IFS= read -r ignored || return 1

    # Regresa al prompt original y limpia el área anterior.
    printf '\033[3A\r\033[J'
}

# -------------------- VALIDACIÓN DE PUERTOS -----------------

valid_port() {
    local port="$1"

    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1

    (( 10#$port >= 1 && 10#$port <= 65535 ))
}

normalize_ports() {
    local input="$1"
    local item
    local normalized=()
    local items=()
    local seen=" "

    input="${input//,/ }"

    read -r -a items <<< "$input"

    for item in "${items[@]}"; do
        if [[ ! "$item" =~ ^[0-9]+$ ]]; then
            VALIDATION_ERROR="Entrada inválida. Introduce puertos correctos (1-65535)."
            return 1
        fi

        if (( ${#item} > 5 )); then
            VALIDATION_ERROR="El puerto $item no es válido. El rango permitido es (1-65535)."
            return 1
        fi

        if ! valid_port "$item"; then
            VALIDATION_ERROR="El puerto $item no es válido. El rango permitido es (1-65535)."
            return 1
        fi

        item=$((10#$item))

        if [[ "$seen" == *" $item "* ]]; then
            continue
        fi

        normalized+=("$item")
        seen+="$item "
    done

    if (( ${#normalized[@]} == 0 )); then
        VALIDATION_ERROR="Debes introducir al menos un puerto."
        return 1
    fi

    PORTS=("${normalized[@]}")

    return 0
}

# -------------------- COMPROBACIÓN DE PUERTOS ---------------

port_in_use() {
    local port="$1"

    ss -H -lnt 2>/dev/null |
        awk -v port="$port" '
        {
            address=$4

            if (address ~ (":" port "$")) {
                found=1
            }
        }

        END {
            exit !found
        }
        '
}

check_ports() {
    local port
    local service
    local ports_text
    local occupied_ports=()
    local sorted_ports=()

    for port in "${PORTS[@]}"; do
        service="${SERVICE_PREFIX}-${port}.service"

        if [[ -e "/etc/systemd/system/$service" ]] || port_in_use "$port"; then
            occupied_ports+=("$port")
        fi
    done

    if (( ${#occupied_ports[@]} > 0 )); then

        # Ordenar los puertos numéricamente y eliminar duplicados.
        mapfile -t sorted_ports < <(
            printf '%s\n' "${occupied_ports[@]}" | sort -n -u
        )

        ports_text="$(printf '%s, ' "${sorted_ports[@]}")"
        ports_text="${ports_text%, }"

        VALIDATION_ERROR="Ya existe un servicio asociado al puerto: ${ports_text}."

        return 1
    fi

    return 0
}

# -------------------- REQUISITOS ----------------------------

check_requirements() {
    local command

    for command in curl file ss systemctl awk grep sort; do
        if ! command -v "$command" >/dev/null 2>&1; then
            error "Falta una dependencia: $command"
            return 1
        fi
    done

    if [[ "$(uname -m)" != "x86_64" ]]; then
        error "El binario disponible requiere arquitectura AMD64."
        return 1
    fi

    return 0
}

# -------------------- DESCARGA DEL BINARIO ------------------

download_binary() {
    local temp_binary

    temp_binary="$(mktemp)"

    if ! curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout 15 \
        --max-time 180 \
        "$REPOSITORY_BINARY" \
        -o "$temp_binary" 2>/dev/null; then

        rm -f "$temp_binary"
        return 1
    fi

    if ! file "$temp_binary" | grep -q 'ELF 64-bit.*x86-64'; then
        rm -f "$temp_binary"
        return 1
    fi

    install -d -m 755 "$INSTALL_DIR"

    if ! install -o root -g root -m 755 \
        "$temp_binary" "$BINARY_PATH"; then

        rm -f "$temp_binary"
        return 1
    fi

    rm -f "$temp_binary"

    "$BINARY_PATH" --version >/dev/null 2>&1
}

# -------------------- GENERAR SERVICIO ----------------------

create_service() {
    local port="$1"
    local unit="/etc/systemd/system/${SERVICE_PREFIX}-${port}.service"
    local temp_unit

    temp_unit="$(mktemp)"

    cat > "$temp_unit" <<EOF
[Unit]
Description=HCR Server - Port ${port}
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BINARY_PATH} --listen :${port} --target ${TARGET_HOST}:${TARGET_PORT} --transport ${TRANSPORT} --max-connections ${MAX_CONNECTIONS} --max-sessions ${MAX_SESSIONS} --max-sessions-per-ip ${MAX_SESSIONS_PER_IP} --max-download-frame ${MAX_DOWNLOAD_FRAME} --download-poll-timeout ${DOWNLOAD_POLL_TIMEOUT} --diagnostics-interval ${DIAGNOSTICS_INTERVAL} --session-stats-interval ${SESSION_STATS_INTERVAL}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    install -o root -g root -m 644 "$temp_unit" "$unit"
    rm -f "$temp_unit"
}

# -------------------- INSTALACIÓN MULTIPUERTO ---------------

install_services() {
    local port
    local service
    local created=()

    for port in "${PORTS[@]}"; do
        service="${SERVICE_PREFIX}-${port}.service"

        if ! create_service "$port"; then
            error "No se pudo generar el servicio $service"
            return 1
        fi

        created+=("$service")
    done

    if ! systemctl daemon-reload; then
        error "No se pudo actualizar systemd."
        return 1
    fi

    for service in "${created[@]}"; do
        if ! systemctl enable --now "$service" >/dev/null 2>&1; then
            error "Falló el inicio de $service"

            local rollback
            for rollback in "${created[@]}"; do
                systemctl disable --now "$rollback" >/dev/null 2>&1 || true
                rm -f "/etc/systemd/system/$rollback"
            done

            systemctl daemon-reload >/dev/null 2>&1 || true
            return 1
        fi
    done

    return 0
}

# -------------------- RESUMEN FINAL -------------------------

show_summary() {
    local port
    local service
    local message="INSTALACIÓN COMPLETADA"
    local width=58

    printf '\n'
    line

    section "ESTADO DE LOS SERVICIOS"

    for port in "${PORTS[@]}"; do
        service="${SERVICE_PREFIX}-${port}.service"

        if systemctl is-active --quiet "$service"; then
            printf '  %b●%b  %-34s  %b%-18s%b\n' \
                "$GREEN" "$RESET" \
                "$service" \
                "$GREEN" "En ejecución" "$RESET"
        else
            printf '  %b●%b  %-34s  %b%-18s%b\n' \
                "$RED" "$RESET" \
                "$service" \
                "$RED" "Detenido" "$RESET"
        fi
    done

    printf '\n'
    line
    printf '\n'

    printf '%*s%b%s%b\n' \
        "$(( (width - ${#message}) / 2 ))" '' \
        "$GREEN$BOLD" "$message" "$RESET"

    printf '\n'
    line
    printf '\n'
}

# -------------------- EJECUCIÓN PRINCIPAL -------------------

main() {
    local ports_input
    local target_input
    local prompt
    local ssl_tls_status

    if (( EUID != 0 )); then
        printf '%bEjecuta el instalador como root.%b\n' "$RED" "$RESET"
        exit 1
    fi

    header

    if ! check_requirements; then
        exit 1
    fi

    section "CONFIGURACIÓN"

    # Espaciado manual compacto.
    prompt="  ${CYAN}Puertos HCR${RESET} ${DIM}[8080]${RESET}: "

    while true; do
        ask_recyclable "$prompt" "$DEFAULT_PORTS" ports_input || exit 1

        if ! normalize_ports "$ports_input"; then
            wait_and_recycle "$VALIDATION_ERROR" || exit 1
            continue
        fi

        if ! check_ports; then
            wait_and_recycle "$VALIDATION_ERROR" || exit 1
            continue
        fi

        printf '\r\033[2K'
        break
    done

    # Espaciado manual compacto.
    prompt="  ${CYAN}Puerto de redirección${RESET} ${DIM}[22]${RESET}: "

    while true; do
        ask_recyclable "$prompt" "$DEFAULT_TARGET_PORT" target_input || exit 1

        if valid_port "$target_input"; then
            TARGET_PORT=$((10#$target_input))
            printf '\r\033[2K'
            break
        fi

        wait_and_recycle \
            "Ingresa un valor válido (1-65535)." || exit 1
    done

    printf '\n'
    line

    section "RESUMEN DE CONFIGURACIÓN"

    if [[ "${TRANSPORT,,}" == "plain" ]]; then
        ssl_tls_status="CERRADO"
    else
        ssl_tls_status="ACTIVO"
    fi

    printf '  %-28s %s\n' \
        "Puertos HCR:" "${PORTS[*]}"

    printf '  %-29s %s\n' \
        "Puerto de redirección:" "$TARGET_PORT"

    printf '  %-28s %b%s%b\n' \
        "SSL/TLS:" "$YELLOW$BOLD" "$ssl_tls_status" "$RESET"

    printf '\n'
    line
    printf '\n'

    if ! spinner "Descargando binario HCR" download_binary; then
        error "No se pudo descargar o validar el binario."
        exit 1
    fi

    if ! spinner "Instalando servicios HCR" install_services; then
        error "No se pudo completar la instalación."
        exit 1
    fi

    show_summary
}

main "$@"
