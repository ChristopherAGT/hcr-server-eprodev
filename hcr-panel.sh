
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#                  HCR SERVER EPRO DEV
#                       PANEL
# ============================================================

REPO="https://raw.githubusercontent.com/ChristopherAGT/hcr-server-eprodev/main"
SERVICE_PREFIX="hcr-server"

# ------------------------------------------------------------
# COLORES
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# FUNCIONES VISUALES
# ------------------------------------------------------------

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
    printf '\n  %b◆%b  %b%s%b\n\n' "$CYAN" "$RESET" "$WHITE$BOLD" "$1" "$RESET"
}

# ------------------------------------------------------------
# ENCABEZADO
# ------------------------------------------------------------

header() {
    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="$1"

    clear 2>/dev/null || true

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
    line
    printf '\n'

    printf '  %b●%b  %bADMINISTRACIÓN DE SERVICIOS HCR%b\n' \
        "$GREEN" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
        "$YELLOW" "$RESET" "$GRAY" "$RESET"

    printf '\n'
    line
}

# ------------------------------------------------------------
# DETECCIÓN DE SERVICIOS
# ------------------------------------------------------------

declare -a SERVICES=()
declare -a PORTS=()
declare -a STATES=()

discover_services() {
    local unit
    local port
    local state
    local seen=" "

    SERVICES=()
    PORTS=()
    STATES=()

    while IFS= read -r unit; do
        [[ "$unit" =~ ^hcr-server(-([0-9]{1,5}))?\.service$ ]] || continue

        if [[ "$unit" == "$SERVICE_PREFIX.service" ]]; then
            port="GENERAL"
        else
            port="${BASH_REMATCH[2]}"
            (( 10#$port >= 1 && 10#$port <= 65535 )) || continue
            port=$((10#$port))
        fi

        [[ "$seen" == *" $unit "* ]] && continue
        seen+="$unit "

        if systemctl is-active --quiet "$unit"; then
            state="ON"
        else
            state="OFF"
        fi

        SERVICES+=("$unit")
        PORTS+=("$port")
        STATES+=("$state")

    done < <(
        {
            systemctl list-unit-files --type=service --no-legend 2>/dev/null |
                awk '{print $1}'

            systemctl list-units --all --type=service --no-legend 2>/dev/null |
                awk '{print $1}'

            find /etc/systemd/system /run/systemd/system \
                /usr/lib/systemd/system /lib/systemd/system \
                -maxdepth 1 \( -type f -o -type l \) \
                -name 'hcr-server*.service' -printf '%f\n' 2>/dev/null || true
        } | sort -Vu
    )
}

# ------------------------------------------------------------
# ESTADO GENERAL
# ------------------------------------------------------------

show_status() {
    local total=0
    local active=0
    local inactive=0
    local i

    discover_services

    total="${#SERVICES[@]}"

    for ((i=0; i<total; i++)); do
        if [[ "${STATES[$i]}" == "ON" ]]; then
            ((active+=1))
        else
            ((inactive+=1))
        fi
    done

    printf '\n  %bESTADO DEL SERVIDOR%b\n\n' "$WHITE$BOLD" "$RESET"

    if (( total == 0 )); then
        warning "No se encontraron servicios HCR."
        return
    fi

    if (( active > 0 )); then
        printf '  Servicio HCR: %b[ ON ]%b\n' "$GREEN$BOLD" "$RESET"
    else
        printf '  Servicio HCR: %b[ OFF ]%b\n' "$YELLOW$BOLD" "$RESET"
    fi

    printf '\n'
    printf '  Total: %-8s Activos: %b%-8s%b Inactivos: %b%s%b\n' \
        "$total" "$GREEN" "$active" "$RESET" "$YELLOW" "$inactive" "$RESET"

    printf '\n'
    printf '  %bPUERTOS Y SERVICIOS%b\n\n' "$CYAN$BOLD" "$RESET"

    for ((i=0; i<total; i++)); do
        if [[ "${STATES[$i]}" == "ON" ]]; then
            printf '  %b●%b  %-12s %b[ ACTIVO ]%b\n' \
                "$GREEN" "$RESET" "${PORTS[$i]}" "$GREEN" "$RESET"
        else
            printf '  %b●%b  %-12s %b[ INACTIVO ]%b\n' \
                "$YELLOW" "$RESET" "${PORTS[$i]}" "$YELLOW" "$RESET"
        fi
    done
}

# ------------------------------------------------------------
# EJECUCIÓN DIRECTA DE SCRIPTS REMOTOS
# ------------------------------------------------------------

run_script() {
    local filename="$1"
    local description="$2"
    local source

    header "E J E C U C I Ó N   D E   S C R I P T S"

    printf '\n'
    info "$description"
    info "Archivo: $filename"
    printf '\n'

    if ! command -v curl >/dev/null 2>&1; then
        error "No se encuentra curl."
        read -r -p " " _
        return 1
    fi

    printf '  %b●%b  %bConectando con GitHub...%b\n' \
        "$CYAN" "$RESET" "$WHITE" "$RESET"

    if ! source="$(curl -fsSL --connect-timeout 15 --max-time 120 \
        "$REPO/$filename")"; then
        error "No fue posible descargar el script."
        read -r -p " " _
        return 1
    fi

    if [[ -z "$source" ]]; then
        error "El archivo recibido está vacío."
        read -r -p " " _
        return 1
    fi

    printf '\n'
    line
    printf '\n'

    # Ejecutar en memoria, conservando la entrada del terminal.
    bash -c "$source"
    local result=$?

    printf '\n'
    line
    printf '\n'

    if (( result == 0 )); then
        success "Operación finalizada."
    else
        error "La operación terminó con errores (código $result)."
    fi

    printf '\n'
    read -r -p " " _
}

# ------------------------------------------------------------
# MENÚ DE GESTIÓN DE PUERTOS
# ------------------------------------------------------------

ports_menu() {
    local option

    while true; do
        header "G E S T I Ó N   D E   P U E R T O S"

        show_status

        printf '\n'
        line
        section "MENÚ DE OPERACIONES"

        printf '  %b[1]%b  Abrir puertos\n\n' "$CYAN$BOLD" "$RESET"
        printf '  %b[2]%b  Remover puertos\n\n' "$CYAN$BOLD" "$RESET"
        printf '  %b[3]%b  Activar / desactivar puertos\n\n' "$CYAN$BOLD" "$RESET"
        printf '  %b[4]%b  Cambiar puerto de redirección\n\n' "$CYAN$BOLD" "$RESET"
        printf '  %b[0]%b  Volver al menú principal\n\n' "$YELLOW$BOLD" "$RESET"

        line
        printf '\n  %bSelecciona una opción:%b ' "$WHITE$BOLD" "$RESET"

        IFS= read -r option || return

        case "$option" in
            1)
                run_script "open-ports.sh" "APERTURA DE PUERTOS"
                ;;
            2)
                run_script "delete-ports.sh" "ELIMINACIÓN DE PUERTOS"
                ;;
            3)
                run_script "start-stop-ports.sh" "ACTIVACIÓN Y DESACTIVACIÓN"
                ;;
            4)
                run_script "change-port.sh" "CAMBIO DE PUERTO DE REDIRECCIÓN"
                ;;
            0)
                return
                ;;
            *)
                error "Opción no válida."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------
# MENÚ PRINCIPAL
# ------------------------------------------------------------

main_menu() {
    local option

    while true; do
        header "P A N E L   D E   A D M I N I S T R A C I Ó N"

        show_status

        printf '\n'
        line
        section "MENÚ PRINCIPAL"

        printf '  %b[1]%b  Instalar HCR\n\n' "$CYAN$BOLD" "$RESET"
        printf '  %b[2]%b  Desinstalar HCR\n\n' "$CYAN$BOLD" "$RESET"
        printf '  %b[3]%b  Gestión de puertos\n\n' "$CYAN$BOLD" "$RESET"
        printf '  %b[4]%b  Optimización HCR\n\n' "$CYAN$BOLD" "$RESET"

        printf '  %b[5]%b  Iniciar / detener servicio  ' "$CYAN$BOLD" "$RESET"

        local total=0
        local active=0
        local i

        total="${#SERVICES[@]}"

        for ((i=0; i<total; i++)); do
            [[ "${STATES[$i]}" == "ON" ]] && ((active+=1))
        done

        if (( active > 0 )); then
            printf '%b[ ON ]%b\n\n' "$GREEN$BOLD" "$RESET"
        else
            printf '%b[ OFF ]%b\n\n' "$YELLOW$BOLD" "$RESET"
        fi

        printf '  %b[6]%b  Reiniciar servicio\n\n' "$CYAN$BOLD" "$RESET"
        printf '  %b[0]%b  Salir\n\n' "$YELLOW$BOLD" "$RESET"

        line

        printf '\n  %bSelecciona una opción:%b ' "$WHITE$BOLD" "$RESET

        IFS= read -r option || break

        case "$option" in
            1)
                run_script "install.sh" "INSTALACIÓN HCR"
                ;;
            2)
                run_script "uninstall.sh" "DESINSTALACIÓN HCR"
                ;;
            3)
                ports_menu
                ;;
            4)
                run_script "optimizer.sh" "OPTIMIZACIÓN HCR"
                ;;
            5)
                run_script "start-stop-service" "CONTROL GENERAL DEL SERVICIO"
                ;;
            6)
                run_script "restart-service.sh" "REINICIO DEL SERVICIO"
                ;;
            0)
                clear 2>/dev/null || true
                exit 0
                ;;
            *)
                error "Opción no válida."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------
# INICIO
# ------------------------------------------------------------

if (( EUID != 0 )); then
    printf 'Ejecuta el panel como root.\n'
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    printf 'systemctl no está disponible.\n'
    exit 1
fi

main_menu
