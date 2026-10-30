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
#   - Comprobación real de puertos TCP en escucha.
#   - Verificación mediante ss y /proc/net/tcp.
#   - Espera del listener después del inicio.
#   - Resumen detallado de estados y totales.
#   - Spinner animado de seis puntos.
#   - Interfaz visual moderna con estados por color.
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

# Tiempo máximo para esperar el listener después del inicio.
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

# -------------------- ENCABEZADO ----------------------------

header() {
    clear 2>/dev/null || true

    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="I N S T A L A D O R"

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

    printf '  %b●%b  %bVALORES PREDETERMINADOS%b\n' \
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
    local listeners
    local port_hex

    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    (( port >= 1 && port <= 65535 )) || return 1

    # --------------------------------------------------------
    # 1. COMPROBACIÓN MEDIANTE SS
    # --------------------------------------------------------

    if command -v ss >/dev/null 2>&1; then

        listeners="$(ss -H -lnt 2>/dev/null || true)"

        if [[ -n "$listeners" ]]; then
            if awk -v port="$port" '
                {
                    address = $4

                    # Extraer el puerto de IPv4, IPv6 o comodín.
                    sub(/^.*:/, "", address)

                    if (address ~ /^[0-9]+$/ && address == port) {
                        found = 1
                        exit
                    }
                }

                END {
                    exit !found
                }
            ' <<< "$listeners"; then
                return 0
            fi
        fi
    fi

    # --------------------------------------------------------
    # 2. RESPALDO MEDIANTE /proc/net/tcp
    # --------------------------------------------------------

    printf -v port_hex '%04X' "$port"

    if [[ -r /proc/net/tcp ]]; then
        if awk -v port_hex="$port_hex" '
            FNR > 1 {
                split($2, address, ":")

                local_port = toupper(address[2])
                state = toupper($4)

                # 0A = TCP_LISTEN.
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

    # --------------------------------------------------------
    # 3. RESPALDO MEDIANTE /proc/net/tcp6
    # --------------------------------------------------------

    if [[ -r /proc/net/tcp6 ]]; then
        if awk -v port_hex="$port_hex" '
            FNR > 1 {
                split($2, address, ":")

                local_port = toupper(address[2])
                state = toupper($4)

                # 0A = TCP_LISTEN.
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

# -------------------- ESPERA DEL LISTENER -------------------

wait_for_port() {
    local port="$1"
    local attempt

    for (( attempt=0; attempt<PORT_CHECK_ATTEMPTS; attempt++ )); do

        if port_in_use "$port"; then
            return 0
        fi

        sleep "$PORT_CHECK_INTERVAL"
    done

    # Última comprobación antes de declarar el puerto cerrado.
    port_in_use "$port"
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

# -------------------- RESUMEN DE CONFIGURACIÓN ---------------

show_configuration() {
    local ssl_tls_status

    if [[ "${TRANSPORT,,}" == "plain" ]]; then
        ssl_tls_status="CERRADO"
    else
        ssl_tls_status="ACTIVO"
    fi

    printf '\n'
    line
    section "RESUMEN DE CONFIGURACIÓN"

    printf '  %b%-28s%b %b%s%b\n' \
        "$CYAN" "Puertos HCR:" "$RESET" \
        "$WHITE$BOLD" "${PORTS[*]}" "$RESET"

    printf '  %b%-29s%b %b%s%b\n' \
        "$CYAN" "Puerto de redirección:" "$RESET" \
        "$WHITE$BOLD" "$TARGET_PORT" "$RESET"

    if [[ "$ssl_tls_status" == "CERRADO" ]]; then
        printf '  %b%-28s%b %bCERRADO%b\n' \
            "$CYAN" "SSL/TLS:" "$RESET" \
            "$YELLOW$BOLD" "$RESET"
    else
        printf '  %b%-28s%b %bABIERTO%b\n' \
            "$CYAN" "SSL/TLS:" "$RESET" \
            "$GREEN$BOLD" "$RESET"
    fi

    printf '\n'
    line
    printf '\n'
}

# -------------------- RESUMEN FINAL -------------------------

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

        # Consultar el estado real de la unidad en systemd.
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

        # ----------------------------------------------------
        # CLASIFICACIÓN DEL SERVICIO Y SU PUERTO
        # ----------------------------------------------------

        listener_open=0

        case "$active_state" in

            active)
                active_count=$((active_count + 1))

                # Esperar brevemente si el proceso todavía está
                # terminando de inicializar su listener.
                if wait_for_port "$port"; then
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

        # ----------------------------------------------------
        # INFORMACIÓN ADICIONAL SEGÚN EL ESTADO
        # ----------------------------------------------------

        if [[ "$active_state" == "failed" ]]; then

            printf '     %b›%b  Resultado: %s | Código: %s | Subestado: %s\n' \
                "$RED" "$RESET" \
                "${result:-desconocido}" \
                "${exit_status:-desconocido}" \
                "${sub_state:-desconocido}"

        elif [[ "$active_state" == "active" ]] && (( listener_open == 0 )); then

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

    # -------------------- TOTALES DE SERVICIOS ----------------

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

    if (( closed_count > 0 || stopped_count > 0 || error_count > 0 )); then
        warning "Se detectaron servicios que requieren atención."
    elif (( starting_count > 0 )); then
        warning "Hay servicios que todavía están iniciando."
    else
        success "Todos los servicios funcionan correctamente."
    fi

    printf '\n'
    line
    printf '\n'

    local message="INSTALACIÓN COMPLETADA"
    local width=58

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

    if (( EUID != 0 )); then
        printf '%b✗%b  %bEjecuta el instalador como root.%b\n' \
            "$RED" "$RESET" "$WHITE" "$RESET"
        exit 1
    fi

    header

    if ! check_requirements; then
        exit 1
    fi

    section "CONFIGURACIÓN"

    prompt="  ${CYAN}${BOLD}Puertos HCR${RESET} ${DIM}[8080]${RESET}: "

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

    prompt="  ${CYAN}${BOLD}Puerto de redirección${RESET} ${DIM}[22]${RESET}: "

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

    show_configuration

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
