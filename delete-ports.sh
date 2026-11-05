#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#              HCR SERVER EPRO DEV
#                ELIMINACIÓN DE PUERTOS
# ============================================================
#
# FUNCIONES:
#   - Detección automática de servicios HCR multipuerto.
#   - Enumeración de puertos y servicios instalados.
#   - Identificación visual de servicios ON y OFF.
#   - Selección múltiple mediante números.
#   - Detención de servicios antes de eliminarlos.
#   - Deshabilitación de servicios en systemd.
#   - Eliminación de archivos de unidades HCR.
#   - Eliminación de directorios drop-in del servicio.
#   - Actualización de la configuración de systemd.
#   - Limpieza de estados fallidos.
#   - Verificación de liberación de puertos TCP.
#   - Protección contra eliminación de servicios ajenos.
#   - Spinner animado.
#   - Consultas reciclables sin duplicar líneas.
#
# ============================================================

# -------------------- CONFIGURACIÓN -------------------------

SERVICE_PREFIX="hcr-server"

SERVICE_DIR="/etc/systemd/system"

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
declare -a SERVICE_PORTS=()
declare -a SERVICE_STATES=()

declare -a SELECTED_INDEXES=()
declare -a SELECTED_SERVICES=()
declare -a SELECTED_PORTS=()

declare -a REMOVED_SERVICES=()
declare -a FAILED_SERVICES=()
declare -a BUSY_PORTS=()

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
    local subtitle="E L I M I N A C I Ó N   D E   P U E R T O S"

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

    printf '  %b●%b  %bADMINISTRACIÓN DE SERVICIOS HCR%b\n' \
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

    for command in systemctl awk sort mktemp ss find; do
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
#                MOSTRAR SERVICIOS DETECTADOS
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

    section "SERVICIOS HCR DETECTADOS"

    printf '  %-7s %-9s %-27s  %-7s\n' \
        "N.º" "PUERTO" "SERVICIO" "ESTADO"

    line
    printf '\n'

    for (( i=0; i<${#SERVICES[@]}; i++ )); do

        number=$((i + 1))
        port="${SERVICE_PORTS[$i]}"
        unit="${SERVICES[$i]}"
        state="${SERVICE_STATES[$i]}"

        if [[ "$state" == "ON" ]]; then
            color="$GREEN"
        else
            color="$RED"
        fi

        # Corchetes sin relleno interno.
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
    line
    printf '\n'

    printf '  %b[0]%b  %bSalir%b\n' \
        "$YELLOW$BOLD" "$RESET" "$WHITE" "$RESET"

    printf '\n'
    line
    printf '\n'
}

# ============================================================
#                NORMALIZAR SELECCIÓN
# ============================================================

normalize_selection() {
    local input="$1"
    local item
    local number
    local seen=" "

    local -a items=()
    local -a normalized=()

    input="${input//,/ }"

    read -r -a items <<< "$input"

    if (( ${#items[@]} == 0 )); then
        VALIDATION_ERROR="Debes seleccionar al menos un servicio."
        return 1
    fi

    # El número 0 permite salir directamente.
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

        if (( number < 1 || number > ${#SERVICES[@]} )); then
            VALIDATION_ERROR="El número $number no corresponde a un servicio."
            return 1
        fi

        if [[ "$seen" == *" $number "* ]]; then
            continue
        fi

        normalized+=( "$number" )
        seen+="$number "
    done

    SELECTED_INDEXES=( "${normalized[@]}" )
    SELECTED_SERVICES=()
    SELECTED_PORTS=()

    for number in "${SELECTED_INDEXES[@]}"; do

        SELECTED_SERVICES+=( "${SERVICES[$((number - 1))]}" )
        SELECTED_PORTS+=( "${SERVICE_PORTS[$((number - 1))]}" )

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
#                MOSTRAR ELEMENTOS SELECCIONADOS
# ============================================================

show_selection() {
    local i
    local unit
    local port

    printf '\n'
    line

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
    line
}

# ============================================================
#                COMPROBACIÓN DE PUERTO TCP
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
#                OBTENER RUTA DE UNIDAD SYSTEMD
# ============================================================

get_fragment_path() {
    local unit="$1"

    systemctl show "$unit" \
        --property=FragmentPath \
        --value 2>/dev/null || true
}

# ============================================================
#                VALIDAR UBICACIÓN DE UNIDAD
# ============================================================

is_managed_unit_path() {
    local path="$1"

    case "$path" in

        /etc/systemd/system/*)
            return 0
            ;;

        /run/systemd/system/*)
            return 0
            ;;

        *)
            return 1
            ;;

    esac
}

# ============================================================
#                ELIMINAR SERVICIO COMPLETO
# ============================================================

remove_service() {
    local unit="$1"
    local port="$2"

    local fragment
    local etc_dropin
    local run_dropin
    local fallback_unit

    fallback_unit="$SERVICE_DIR/$unit"

    # --------------------------------------------------------
    # VALIDAR UBICACIÓN ANTES DE MODIFICAR EL SERVICIO
    # --------------------------------------------------------

    fragment="$(get_fragment_path "$unit")"

    if [[ -n "$fragment" && "$fragment" != "-" ]]; then

        if ! is_managed_unit_path "$fragment"; then
            error "La unidad $unit no está en una ubicación administrada."
            return 1
        fi

        if [[ "$(basename "$fragment")" != "$unit" ]]; then
            error "La ruta de la unidad no coincide con $unit."
            return 1
        fi

    elif [[ -e "$fallback_unit" || -L "$fallback_unit" ]]; then

        fragment="$fallback_unit"

    else

        error "No se encontró una unidad HCR administrada para $unit."
        return 1

    fi

    if [[ ! -e "$fragment" && ! -L "$fragment" ]]; then
        error "El archivo de unidad $unit no existe."
        return 1
    fi

    # --------------------------------------------------------
    # DETENER SERVICIO
    # --------------------------------------------------------

    systemctl stop "$unit" >/dev/null 2>&1 || true

    # --------------------------------------------------------
    # DESHABILITAR SERVICIO
    # --------------------------------------------------------

    systemctl disable "$unit" >/dev/null 2>&1 || true

    # --------------------------------------------------------
    # ELIMINAR UNIDAD SYSTEMD
    # --------------------------------------------------------

    rm -f -- "$fragment" || return 1

    # --------------------------------------------------------
    # ELIMINAR CONFIGURACIONES DROP-IN
    # --------------------------------------------------------

    etc_dropin="$SERVICE_DIR/${unit}.d"
    run_dropin="/run/systemd/system/${unit}.d"

    if [[ -d "$etc_dropin" || -L "$etc_dropin" ]]; then
        rm -rf -- "$etc_dropin" || return 1
    fi

    if [[ -d "$run_dropin" || -L "$run_dropin" ]]; then
        rm -rf -- "$run_dropin" || return 1
    fi

    # --------------------------------------------------------
    # ACTUALIZAR SYSTEMD
    # --------------------------------------------------------

    systemctl daemon-reload || return 1

    systemctl reset-failed "$unit" >/dev/null 2>&1 || true

    # --------------------------------------------------------
    # VERIFICAR ELIMINACIÓN
    # --------------------------------------------------------

    if systemctl cat "$unit" >/dev/null 2>&1; then
        error "Systemd todavía reconoce la unidad $unit."
        return 1
    fi

    return 0
}

# ============================================================
#                CONFIRMAR ELIMINACIÓN
# ============================================================

confirm_deletion() {
    local confirmation
    local prompt
    
    printf '\n'
    line
    printf '\n'
  
    prompt="  ${YELLOW}${BOLD}¿Deseas confirmar la eliminación?${RESET} ${WHITE}S/n:${RESET} "

    while true; do

        ask_recyclable "$prompt" "S" confirmation || return 1

        case "$confirmation" in

            S|s|"")
                printf '\r\033[2K'
                return 0
                ;;

            N|n)
                printf '\r\033[2K\n'
                line

                local message="OPERACIÓN CANCELADA"
                local width=58

                printf '%*s%b%s%b\n' \
                "$(( (width - ${#message}) / 2 ))" '' \
                "$YELLOW$BOLD" "$message" "$RESET"

                line
                printf '\n'

                return 1
                ;;

            *)
                warning "Entrada inválida."

                IFS= read -r _ || return 1

                printf '\033[u\033[J'
                ;;

        esac

    done
}

# ============================================================
#                ELIMINACIÓN DE SERVICIOS SELECCIONADOS
# ============================================================

delete_selected_services() {
    local i
    local unit
    local port

    REMOVED_SERVICES=()
    FAILED_SERVICES=()
    BUSY_PORTS=()

    for (( i=0; i<${#SELECTED_SERVICES[@]}; i++ )); do

        unit="${SELECTED_SERVICES[$i]}"
        port="${SELECTED_PORTS[$i]}"

        if remove_service "$unit" "$port"; then
            REMOVED_SERVICES+=( "$unit" )
        else
            FAILED_SERVICES+=( "$unit" )
        fi

    done

    return 0
}

# ============================================================
#                RECUPERAR RESULTADOS DE ELIMINACIÓN
# ============================================================

collect_deletion_results() {
    local unit
    local fragment

    REMOVED_SERVICES=()
    FAILED_SERVICES=()

    for unit in "${SELECTED_SERVICES[@]}"; do

        fragment="$(get_fragment_path "$unit")"

        if [[ -n "$fragment" && "$fragment" != "-" ]] &&
           { [[ -e "$fragment" ]] || [[ -L "$fragment" ]]; }; then

            FAILED_SERVICES+=( "$unit" )

        elif systemctl cat "$unit" >/dev/null 2>&1; then

            FAILED_SERVICES+=( "$unit" )

        else

            REMOVED_SERVICES+=( "$unit" )

        fi

    done
}

# ============================================================
#                VERIFICAR LIBERACIÓN DE PUERTOS
# ============================================================

verify_released_ports() {
    local i
    local unit
    local port

    local attempt
    local released

    BUSY_PORTS=()

    for (( i=0; i<${#REMOVED_SERVICES[@]}; i++ )); do

        unit="${REMOVED_SERVICES[$i]}"
        port=""

        local j

        for (( j=0; j<${#SELECTED_SERVICES[@]}; j++ )); do

            if [[ "${SELECTED_SERVICES[$j]}" == "$unit" ]]; then
                port="${SELECTED_PORTS[$j]}"
                break
            fi

        done

        [[ -n "$port" ]] || continue

        released=0

        for (( attempt=0; attempt<20; attempt++ )); do

            if ! port_in_use "$port"; then
                released=1
                break
            fi

            sleep 0.25
        done

        if (( released == 0 )); then
            BUSY_PORTS+=( "$port" )
        fi

    done
}

# ============================================================
#                RESUMEN FINAL
# ============================================================

show_summary() {
    local unit
    local port
    local i
    local busy
    local total
    local removed
    local failed
    local free_count

    total="${#SELECTED_SERVICES[@]}"
    removed="${#REMOVED_SERVICES[@]}"
    failed="${#FAILED_SERVICES[@]}"
    busy="${#BUSY_PORTS[@]}"

    free_count=$((removed - busy))

    printf '\n'
    line

    section "ESTADO DE ELIMINACIÓN"

    for (( i=0; i<${#SELECTED_SERVICES[@]}; i++ )); do

        unit="${SELECTED_SERVICES[$i]}"
        port="${SELECTED_PORTS[$i]}"

        if [[ " ${FAILED_SERVICES[*]} " == *" $unit "* ]]; then

            printf '  %b✗%b  %b%-30s%b  %bERROR%b\n' \
                "$RED" "$RESET" \
                "$WHITE" "$unit" "$RESET" \
                "$RED$BOLD" "$RESET"

            continue
        fi

        if [[ " ${BUSY_PORTS[*]} " == *" $port "* ]]; then

            printf '  %b✓%b  %b%-30s%b  %bELIMINADO%b\n' \
                "$GREEN" "$RESET" \
                "$WHITE" "$unit" "$RESET" \
                "$GREEN$BOLD" "$RESET"

            printf '     %b›%b  Puerto %s continúa ocupado por otro proceso.\n' \
                "$YELLOW" "$RESET" "$port"

        else

            printf '  %b✓%b  %b%-30s%b  %bELIMINADO%b\n' \
                "$GREEN" "$RESET" \
                "$WHITE" "$unit" "$RESET" \
                "$GREEN$BOLD" "$RESET"
      

        fi

    done

    printf '\n'
    line
    printf '\n'

    printf '  %bServicios seleccionados:%b  %b%s%b\n' \
        "$GRAY" "$RESET" "$WHITE$BOLD" "$total" "$RESET"

    printf '  %bServicios eliminados:%b     %b%s%b\n' \
        "$GRAY" "$RESET" "$GREEN$BOLD" "$removed" "$RESET"

    printf '  %bPuertos liberados:%b        %b%s%b\n' \
        "$GRAY" "$RESET" "$GREEN$BOLD" "$free_count" "$RESET"

    if (( busy > 0 )); then

        printf '  %bPuertos todavía ocupados:%b %b%s%b\n' \
            "$GRAY" "$RESET" "$YELLOW$BOLD" "$busy" "$RESET"

    fi

    if (( failed > 0 )); then

        printf '  %bServicios con errores:%b    %b%s%b\n' \
            "$GRAY" "$RESET" "$RED$BOLD" "$failed" "$RESET"

    fi

    printf '\n'

    if (( failed == 0 && busy == 0 )); then

        success "Todos los servicios fueron eliminados y sus puertos están libres."

    elif (( failed == 0 && busy > 0 )); then

        warning "Los servicios fueron eliminados, pero algunos puertos siguen ocupados."

    else

        warning "La eliminación terminó con errores. Revisa los servicios indicados."

    fi

    printf '\n'
    line
    printf '\n'

    local message
    local width=58

    if (( failed == 0 && busy == 0 )); then

        message="ELIMINACIÓN COMPLETADA"

        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$GREEN$BOLD" "$message" "$RESET"

    else

        message="ELIMINACIÓN CON OBSERVACIONES"

        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$YELLOW$BOLD" "$message" "$RESET"

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

        error "No se encontraron servicios HCR multipuerto."

        info "No se detectó ningún servicio con el formato:"
        info "hcr-server-PORT.service"

        exit 0
    fi

    # --------------------------------------------------------
    # MOSTRAR LISTA DE SERVICIOS
    # --------------------------------------------------------

    show_services

    # --------------------------------------------------------
    # SELECCIÓN DE SERVICIOS
    # --------------------------------------------------------

    if read_selection; then
        :
    else
        result=$?

        if (( result == 2 )); then
            exit 0
        fi

        exit 1
    fi

    # --------------------------------------------------------
    # CONFIRMAR ELIMINACIÓN
    # --------------------------------------------------------

    if ! confirm_deletion; then
        exit 0
    fi

    # --------------------------------------------------------
    # ELIMINAR SERVICIOS
    # --------------------------------------------------------

    if ! spinner "Eliminando servicios HCR" delete_selected_services; then

        error "No se pudo completar el proceso de eliminación."
        exit 1

    fi

    # Recuperar los resultados del proceso en el shell principal.
    collect_deletion_results

    # --------------------------------------------------------
    # VERIFICAR PUERTOS
    # --------------------------------------------------------

    if ! spinner "Verificando liberación de puertos" verify_released_ports; then
        warning "No se pudo completar la verificación de los puertos."
    fi

    # Recuperar los puertos ocupados después del spinner.
    # La función se ejecuta en segundo plano, por lo que
    # se vuelve a verificar en el proceso principal.
    verify_released_ports

    # --------------------------------------------------------
    # RESUMEN FINAL
    # --------------------------------------------------------

    show_summary
}

main "$@"
