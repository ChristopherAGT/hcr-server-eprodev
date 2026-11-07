#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#              HCR SERVER EPRO DEV
#             ADMINISTRACIÓN DE PUERTOS
# ============================================================
#
# FUNCIONES:
#   - Detección automática de servicios HCR.
#   - Menú de activación y desactivación.
#   - Identificación de servicios ON y OFF.
#   - Contador dinámico de servicios activos e inactivos.
#   - Listado dinámico según la operación seleccionada.
#   - Selección múltiple mediante números.
#   - Activación mediante systemctl start.
#   - Desactivación mediante systemctl stop.
#   - Verificación individual de cada servicio.
#   - Protección contra servicios ajenos.
#   - Spinner animado.
#   - Consultas reciclables sin duplicar líneas.
#
# ============================================================

# -------------------- CONFIGURACIÓN -------------------------

SERVICE_PREFIX="hcr-server"

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
declare -a SERVICE_PORTS=()
declare -a SERVICE_STATES=()

declare -a AVAILABLE_SERVICES=()
declare -a AVAILABLE_PORTS=()

declare -a SELECTED_SERVICES=()
declare -a SELECTED_PORTS=()
declare -a SELECTED_INDEXES=()

declare -a FAILED_SERVICES=()
declare -a SUCCESS_SERVICES=()

ACTION=""
ACTION_NAME=""
ACTION_VERB=""
ACTION_COLOR=""

VALIDATION_ERROR=""
OP_RESULT_FILE=""

# -------------------- FUNCIONES VISUALES --------------------

# Línea del menú principal: AZUL ATENUADO

line() {
    printf '%b\n' "${DIM}${BLUE}────────────────────────────────────────────────────────${RESET}"
}

# Línea de los menús secundarios: MAGENTA

edit_line() {
    printf '%b\n' "${MAGENTA}────────────────────────────────────────────────────────${RESET}"
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
    local subtitle

    # SUBTÍTULO SEGÚN LA PANTALLA

    if [[ "$ACTION" == "START" ]]; then
        subtitle="A C T I V A C I Ó N   D E   P U E R T O S"
    elif [[ "$ACTION" == "STOP" ]]; then
        subtitle="D E S A C T I V A C I Ó N   D E   P U E R T O S"
    else
        subtitle="A D M I N I S T R A C I Ó N   D E   P U E R T O S"
    fi

    printf '\n\n'

    # TÍTULO: COLORES ORIGINALES

    printf '%*s%bHCR%b %bSERVER%b %bEPRO DEV%b\n' \
        "$(( (width - ${#title}) / 2 ))" '' \
        "$CYAN$BOLD" "$RESET" \
        "$WHITE$BOLD" "$RESET" \
        "$MAGENTA$BOLD" "$RESET"

    # SUBTÍTULO

    if [[ -n "$ACTION" ]]; then

        printf '%*s%b%s%b\n' \
            "$(( (width - ${#subtitle}) / 2 ))" '' \
            "$MAGENTA$BOLD" "$subtitle" "$RESET"

    else

        printf '%*s%b%s%b\n' \
            "$(( (width - ${#subtitle}) / 2 ))" '' \
            "$DIM$GRAY" "$subtitle" "$RESET"

    fi

    printf '\n'

    # SEPARADORES SEGÚN LA PANTALLA

    if [[ -n "$ACTION" ]]; then
        edit_line
    else
        line
    fi

    printf '\n'

    # ADMINISTRACIÓN DE SERVICIOS HCR

    printf '  %b●%b  %bADMINISTRACIÓN DE SERVICIOS HCR%b\n' \
        "$GREEN" "$RESET" "$WHITE$BOLD" "$RESET"

    # FIRMA SEGÚN LA PANTALLA

    if [[ -n "$ACTION" ]]; then

        printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
            "$MAGENTA$BOLD" "$RESET" "$MAGENTA$BOLD" "$RESET"

    else

        printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
            "$YELLOW" "$RESET" "$GRAY" "$RESET"

    fi

    printf '\n'

    if [[ -n "$ACTION" ]]; then
        edit_line
    else
        line
    fi
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
    local message="${1:-}"
    local ignored

    # MOSTRAR ADVERTENCIA SOLO SI EXISTE UN MENSAJE

    if [[ -n "$message" ]]; then
        warning "$message"
    fi

    # ESPERAR ENTER SIN TEXTO ADICIONAL

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

    for command in systemctl awk sort find mktemp; do

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

    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1

    (( 10#$port >= 1 && 10#$port <= 65535 ))
}

# ============================================================
#                DETECCIÓN DE SERVICIOS HCR
# ============================================================

discover_services() {
    local unit
    local port
    local state
    local seen=" "

    SERVICES=()
    SERVICE_PORTS=()
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

        if systemctl is-active --quiet "$unit"; then
            state="ON"
        else
            state="OFF"
        fi

        SERVICES+=( "$unit" )
        SERVICE_PORTS+=( "$port" )
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
                /run/systemd/system \
                /usr/lib/systemd/system \
                /lib/systemd/system \
                -maxdepth 1 \
                \( -type f -o -type l \) \
                -name "${SERVICE_PREFIX}-*.service" \
                -printf '%f\n' 2>/dev/null || true

        } | sort -Vu
    )

    (( ${#SERVICES[@]} > 0 ))
}

# ============================================================
#                CONTADOR DE SERVICIOS
# ============================================================

show_service_counter() {
    local total
    local active=0
    local inactive=0
    local i

    local width=58
    local margin=4

    local left center right
    local left_end right_end
    local right_start center_start
    local gap_width

    total="${#SERVICES[@]}"

    for (( i=0; i<total; i++ )); do
        if [[ "${SERVICE_STATES[$i]}" == "ON" ]]; then
            ((active += 1))
        else
            ((inactive += 1))
        fi
    done

    left="Total: $total"
    center="Activos: $active"
    right="Inactivos: $inactive"

    # TOTAL: MARGEN IZQUIERDO DE 2 ESPACIOS
    left_end=$((2 + ${#left}))

    # INACTIVOS: MARGEN DERECHO DE 2 ESPACIOS
    right_end=$((width - margin))
    right_start=$((right_end - ${#right} + 1))

    # ACTIVOS: CENTRADO ENTRE LOS OTROS DOS
    gap_width=$((right_start - left_end - 1))
    center_start=$((left_end + 1 + (gap_width - ${#center}) / 2))

    printf '\n'

    # TOTAL
    printf '\033[3G%bTotal:%b %b%d%b' \
        "$GRAY$BOLD" "$RESET" \
        "$WHITE$BOLD" "$total" "$RESET"

    # ACTIVOS
    printf '\033[%dG%bActivos:%b %b%d%b' \
        "$center_start" \
        "$GRAY$BOLD" "$RESET" \
        "$GREEN$BOLD" "$active" "$RESET"

    # INACTIVOS
    printf '\033[%dG%bInactivos:%b %b%d%b\n' \
        "$right_start" \
        "$GRAY$BOLD" "$RESET" \
        "$RED$BOLD" "$inactive" "$RESET"

    printf '\n'
    line
}

# ============================================================
#                MENÚ PRINCIPAL
# ============================================================

show_menu() {
    show_service_counter

    section "OPERACIONES"

    printf '  %b[1]%b  %bACTIVAR PUERTOS%b\n' \
        "$GREEN$BOLD" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b[2]%b  %bDESACTIVAR PUERTOS%b\n' \
        "$RED$BOLD" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '\n'
    line
    printf '\n'

    printf '  %b[0]%b  %bSALIR%b\n' \
        "$YELLOW$BOLD" "$RESET" "$WHITE$RESET" "$RESET"

    printf '\n'
    line
    printf '\n'
}

read_menu_choice() {
    local choice
    local prompt

    prompt="  ${CYAN}${BOLD}Selecciona una opción:${RESET} "

    while true; do

        ask_recyclable "$prompt" "" choice || return 1

        case "$choice" in

            1)
                ACTION="START"
                ACTION_NAME="ACTIVACIÓN"
                ACTION_VERB="Activando"
                ACTION_COLOR="$GREEN"
                printf '\r\033[2K'
                return 0
                ;;

            2)
                ACTION="STOP"
                ACTION_NAME="DESACTIVACIÓN"
                ACTION_VERB="Desactivando"
                ACTION_COLOR="$RED"
                printf '\r\033[2K'
                return 0
                ;;

            0)
                printf '\r\033[2K'
                return 2
                ;;

            *)
                wait_and_recycle "Opción inválida." ||
                    return 1
                ;;

        esac

    done
}

# ============================================================
#                FILTRAR SERVICIOS DISPONIBLES
# ============================================================

filter_services() {
    local i
    local state

    AVAILABLE_SERVICES=()
    AVAILABLE_PORTS=()

    for (( i=0; i<${#SERVICES[@]}; i++ )); do

        state="${SERVICE_STATES[$i]}"

        if [[ "$ACTION" == "START" && "$state" == "OFF" ]]; then

            AVAILABLE_SERVICES+=( "${SERVICES[$i]}" )
            AVAILABLE_PORTS+=( "${SERVICE_PORTS[$i]}" )

        elif [[ "$ACTION" == "STOP" && "$state" == "ON" ]]; then

            AVAILABLE_SERVICES+=( "${SERVICES[$i]}" )
            AVAILABLE_PORTS+=( "${SERVICE_PORTS[$i]}" )

        fi

    done

    (( ${#AVAILABLE_SERVICES[@]} > 0 ))
}

# ============================================================
#                MOSTRAR MENSAJES SIN SERVICIOS
# ============================================================

show_no_available_services() {
    local message
    local width=58

    if [[ "$ACTION" == "START" ]]; then
        message="ACTUALMENTE TODOS LOS PUERTOS ESTÁN ACTIVADOS"
    else
        message="ACTUALMENTE TODOS LOS PUERTOS ESTÁN DESACTIVADOS"
    fi

    printf '\n'

    printf '%*s%b%s%b\n' \
        "$(( (width - ${#message}) / 2 ))" '' \
        "$YELLOW$BOLD" "$message" "$RESET"

    printf '\n'
    edit_line
    printf '\n'
}

# ============================================================
#                MOSTRAR SERVICIOS DISPONIBLES
# ============================================================

show_services() {
    local i
    local number
    local port
    local unit
    local state
    local color
    local number_field
    local number_column
    local state_field
    local state_column

    if [[ "$ACTION" == "START" ]]; then
        section "PUERTOS DESACTIVADOS"
    else
        section "PUERTOS ACTIVADOS"
    fi

    printf '  %-7s %-9s %-27s  %-7s\n' \
        "N.º" "PUERTO" "SERVICIO" "ESTADO"

    edit_line
    printf '\n'

    for (( i=0; i<${#AVAILABLE_SERVICES[@]}; i++ )); do

        number=$((i + 1))
        port="${AVAILABLE_PORTS[$i]}"
        unit="${AVAILABLE_SERVICES[$i]}"

        if [[ "$ACTION" == "START" ]]; then
            state="OFF"
            color="$RED"
        else
            state="ON"
            color="$GREEN"
        fi

        printf -v number_field '[%s]' "$number"
        printf -v number_column '%-6s' "$number_field"

        printf -v state_field '[%s]' "$state"
        printf -v state_column '%-7s' "$state_field"

        printf '  %b%s%b %-9s %-27s  %b%s%b\n' \
            "$CYAN$BOLD" "$number_column" "$RESET" \
            "$port" \
            "$unit" \
            "$color$BOLD" "$state_column" "$RESET"

    done

    printf '\n'
    edit_line
    printf '\n'

    printf '  %b[0]%b  %bSalir%b\n' \
        "$YELLOW$BOLD" "$RESET" "$WHITE" "$RESET"

    printf '\n'
    edit_line
    printf '\n'
}

# ============================================================
#                NORMALIZAR SELECCIÓN
# ============================================================

normalize_selection() {
    local input="$1"
    local item
    local number
    local i
    local invalid_list=""
    local seen=" "
    local invalid_seen=" "

    local -a items=()
    local -a normalized=()
    local -a invalid_numbers=()

    input="${input//,/ }"

    read -r -a items <<< "$input"

    if (( ${#items[@]} == 0 )); then
        VALIDATION_ERROR="Debes seleccionar al menos un servicio."
        return 1
    fi

    if (( ${#items[@]} == 1 )) && [[ "${items[0]}" =~ ^0+$ ]]; then
        return 2
    fi

    for item in "${items[@]}"; do

        if [[ ! "$item" =~ ^[0-9]+$ ]] ||
           (( ${#item} > 6 )); then

            VALIDATION_ERROR="Selección inválida. Introduce números de la lista."
            return 1
        fi

        number=$((10#$item))

        if (( number < 1 || number > ${#AVAILABLE_SERVICES[@]} )); then

            if [[ "$invalid_seen" != *" $number "* ]]; then
                invalid_numbers+=( "$number" )
                invalid_seen+="$number "
            fi

            continue
        fi

        if [[ "$seen" == *" $number "* ]]; then
            continue
        fi

        normalized+=( "$number" )
        seen+="$number "

    done

    # --------------------------------------------------------
    # RECOPILAR TODOS LOS NÚMEROS INEXISTENTES
    # --------------------------------------------------------

    if (( ${#invalid_numbers[@]} > 0 )); then

        for (( i=0; i<${#invalid_numbers[@]}; i++ )); do

            if (( i > 0 )); then
                invalid_list+=", "
            fi

            invalid_list+="${invalid_numbers[$i]}"

        done

        VALIDATION_ERROR="Los números $invalid_list no corresponden a ningún servicio."
        return 1
    fi

    SELECTED_INDEXES=( "${normalized[@]}" )
    SELECTED_SERVICES=()
    SELECTED_PORTS=()

    for number in "${SELECTED_INDEXES[@]}"; do

        SELECTED_SERVICES+=( "${AVAILABLE_SERVICES[$((number - 1))]}" )
        SELECTED_PORTS+=( "${AVAILABLE_PORTS[$((number - 1))]}" )

    done

    return 0
}

# ============================================================
#                CONSULTAR SELECCIÓN
# ============================================================

read_selection() {
    local selection
    local prompt
    local result

    prompt="  ${CYAN}${BOLD}Selecciona los servicios:${RESET} "

    while true; do

        ask_recyclable "$prompt" "" selection || return 1

        if normalize_selection "$selection"; then
            printf '\r\033[2K'
            return 0
        else
            result=$?
        fi

        if (( result == 2 )); then
            printf '\r\033[2K'
            return 2
        fi

        wait_and_recycle "$VALIDATION_ERROR" || return 1

    done
}

# ============================================================
#                MOSTRAR SERVICIOS SELECCIONADOS
# ============================================================

show_selection() {
    local i
    local unit
    local port

    printf '\n'
    edit_line

    section "SERVICIOS SELECCIONADOS"

    for (( i=0; i<${#SELECTED_SERVICES[@]}; i++ )); do

        unit="${SELECTED_SERVICES[$i]}"
        port="${SELECTED_PORTS[$i]}"

        printf '  %b●%b  %b%-30s%b  %bPUERTO %s%b\n' \
            "$YELLOW" "$RESET" \
            "$WHITE$BOLD" "$unit" "$RESET" \
            "$CYAN$BOLD" "$port" "$RESET"

    done

    printf '\n'
    edit_line
}

# ============================================================
#                APLICAR OPERACIONES
# ============================================================

apply_selected_services() {
    local i
    local unit

    : > "$OP_RESULT_FILE"

    for (( i=0; i<${#SELECTED_SERVICES[@]}; i++ )); do

        unit="${SELECTED_SERVICES[$i]}"

        if [[ "$ACTION" == "START" ]]; then

            if ! systemctl start "$unit" >/dev/null 2>&1; then
                printf '%s\n' "$unit" >> "$OP_RESULT_FILE"
            fi

        else

            if ! systemctl stop "$unit" >/dev/null 2>&1; then
                printf '%s\n' "$unit" >> "$OP_RESULT_FILE"
            fi

        fi

    done

    return 0
}

# ============================================================
#                VERIFICAR RESULTADOS
# ============================================================

verify_results() {
    local unit
    local active

    SUCCESS_SERVICES=()
    FAILED_SERVICES=()

    for unit in "${SELECTED_SERVICES[@]}"; do

        active=0

        if systemctl is-active --quiet "$unit"; then
            active=1
        fi

        if [[ "$ACTION" == "START" ]]; then

            if (( active == 1 )); then
                SUCCESS_SERVICES+=( "$unit" )
            else
                FAILED_SERVICES+=( "$unit" )
            fi

        else

            if (( active == 0 )); then
                SUCCESS_SERVICES+=( "$unit" )
            else
                FAILED_SERVICES+=( "$unit" )
            fi

        fi

    done

    (( ${#FAILED_SERVICES[@]} == 0 ))
}

# ============================================================
#                RESUMEN FINAL
# ============================================================

show_summary() {
    local i
    local unit
    local port
    local total
    local completed
    local failed
    local message
    local width=58
    local status
    local color

    total="${#SELECTED_SERVICES[@]}"
    completed="${#SUCCESS_SERVICES[@]}"
    failed=$((total - completed))

    printf '\n'
    edit_line

    if [[ "$ACTION" == "START" ]]; then
        section "ESTADO DE ACTIVACIÓN"
    else
        section "ESTADO DE DESACTIVACIÓN"
    fi

    for (( i=0; i<${#SELECTED_SERVICES[@]}; i++ )); do

        unit="${SELECTED_SERVICES[$i]}"
        port="${SELECTED_PORTS[$i]}"

        if [[ " ${SUCCESS_SERVICES[*]} " == *" $unit "* ]]; then

            if [[ "$ACTION" == "START" ]]; then
                status="ACTIVADO"
                color="$GREEN$BOLD"
            else
                status="DESACTIVADO"
                color="$GREEN$BOLD"
            fi

            printf '  %b✓%b  %b%-30s%b  %b%s%b\n' \
                "$GREEN" "$RESET" \
                "$WHITE" "$unit" "$RESET" \
                "$color" "$status" "$RESET"

        else

            if [[ "$ACTION" == "START" ]]; then
                status="ERROR AL ACTIVAR"
            else
                status="ERROR AL DESACTIVAR"
            fi

            printf '  %b✗%b  %b%-30s%b  %b%s%b\n' \
                "$RED" "$RESET" \
                "$WHITE" "$unit" "$RESET" \
                "$RED$BOLD" "$status" "$RESET"

        fi

    done

    printf '\n'
    edit_line
    printf '\n'

    printf '  %bServicios seleccionados:%b %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE$BOLD" "$total" "$RESET"

    printf '  %bOperaciones exitosas:%b    %b%s%b\n' \
        "$GRAY" "$RESET" "$GREEN$BOLD" "$completed" "$RESET"

    printf '  %bServicios con errores:%b.  %b%s%b\n' \
        "$GRAY" "$RESET" "$RED$BOLD" "$failed" "$RESET"

    printf '\n'

    if (( failed == 0 )); then

        if [[ "$ACTION" == "START" ]]; then
            success "Todos los servicios seleccionados están activos."
            message="ACTIVACIÓN COMPLETADA"
        else
            success "Todos los servicios seleccionados están detenidos."
            message="DESACTIVACIÓN COMPLETADA"
        fi

        color="$GREEN$BOLD"

    else

        warning "Algunos servicios no alcanzaron el estado solicitado."
        message="OPERACIÓN CON ERRORES"
        color="$YELLOW$BOLD"

    fi

    printf '\n'
    edit_line
    printf '\n'

    printf '%*s%b%s%b\n' \
        "$(( (width - ${#message}) / 2 ))" '' \
        "$color" "$message" "$RESET"

    printf '\n'
    edit_line
    printf '\n'
}

# ============================================================
#                LIMPIEZA
# ============================================================

cleanup() {
    if [[ -n "$OP_RESULT_FILE" && -f "$OP_RESULT_FILE" ]]; then
        rm -f -- "$OP_RESULT_FILE"
    fi
}

trap cleanup EXIT

# ============================================================
#                    EJECUCIÓN PRINCIPAL
# ============================================================

main() {
    local result

    check_root

    if ! check_requirements; then
        exit 1
    fi

    # --------------------------------------------------------
    # CICLO PRINCIPAL DEL MENÚ
    # --------------------------------------------------------

    while true; do

        # ----------------------------------------------------
        # RESTABLECER OPERACIÓN
        # ----------------------------------------------------

        ACTION=""
        ACTION_NAME=""
        ACTION_VERB=""
        ACTION_COLOR=""

        SELECTED_SERVICES=()
        SELECTED_PORTS=()
        SELECTED_INDEXES=()

        SUCCESS_SERVICES=()
        FAILED_SERVICES=()

        # ----------------------------------------------------
        # MOSTRAR MENÚ PRINCIPAL
        # ----------------------------------------------------

        header

        # ----------------------------------------------------
        # DETECCIÓN DE SERVICIOS
        # ----------------------------------------------------

        if ! discover_services; then

            error "No se encontró ningún servicio disponible."

            info "No se detectaron servicios HCR."
            info "Formato esperado: hcr-server-PORT.service"

            exit 0
        fi

        # ----------------------------------------------------
        # MENÚ PRINCIPAL
        # ----------------------------------------------------

        show_menu

        if read_menu_choice; then
            :
        else
            result=$?

            if (( result == 2 )); then
                exit 0
            fi

            exit 1
        fi

        # ----------------------------------------------------
        # REDIBUJAR ENCABEZADO SEGÚN LA OPERACIÓN
        # ----------------------------------------------------

        header

        # ----------------------------------------------------
        # FILTRAR SERVICIOS SEGÚN LA OPERACIÓN
        # ----------------------------------------------------

        if ! filter_services; then

            show_no_available_services

            # ESPERAR ENTER SIN MOSTRAR ADVERTENCIA

            wait_and_recycle "" || exit 1

            continue
        fi

        # ----------------------------------------------------
        # MOSTRAR SERVICIOS DISPONIBLES
        # ----------------------------------------------------

        show_services

        # ----------------------------------------------------
        # SELECCIONAR SERVICIOS
        # ----------------------------------------------------

        if read_selection; then
            :
        else
            result=$?

            if (( result == 2 )); then
                # [0] REGRESA AL MENÚ PRINCIPAL
                continue
            fi

            exit 1
        fi

        # ----------------------------------------------------
        # MOSTRAR SELECCIÓN
        # ----------------------------------------------------

        show_selection

        # ----------------------------------------------------
        # PREPARAR RESULTADOS
        # ----------------------------------------------------

        OP_RESULT_FILE="$(mktemp)" || {
            error "No se pudo preparar el archivo temporal."
            exit 1
        }

        # ----------------------------------------------------
        # EJECUTAR OPERACIÓN
        # ----------------------------------------------------

        printf '\n'
        edit_line
        printf '\n'

        if [[ "$ACTION" == "START" ]]; then

            if ! spinner "Activando servicios HCR" apply_selected_services; then
                error "No se pudo ejecutar la operación."
                exit 1
            fi

        else

            if ! spinner "Desactivando servicios HCR" apply_selected_services; then
                error "No se pudo ejecutar la operación."
                exit 1
            fi

        fi

        # ----------------------------------------------------
        # VERIFICAR ESTADOS FINALES
        # ----------------------------------------------------

        printf '\n'

        if verify_results; then
            success "Verificación de servicios completada."
        else
            warning "Se detectaron servicios que no alcanzaron el estado solicitado."
        fi

        # ----------------------------------------------------
        # RESUMEN FINAL
        # ----------------------------------------------------

        show_summary

        # ----------------------------------------------------
        # LIMPIAR ARCHIVO TEMPORAL DE LA OPERACIÓN
        # ----------------------------------------------------

        if [[ -n "$OP_RESULT_FILE" && -f "$OP_RESULT_FILE" ]]; then
            rm -f -- "$OP_RESULT_FILE"
        fi

        OP_RESULT_FILE=""

        # ----------------------------------------------------
        # VOLVER AL MENÚ PRINCIPAL
        # ----------------------------------------------------

        if (( ${#FAILED_SERVICES[@]} > 0 )); then
            warning "La operación terminó con errores."
        fi

        # ESPERAR ENTER SIN MOSTRAR TEXTO ADICIONAL

        wait_and_recycle "" || exit 1

    done
}

main "$@"
