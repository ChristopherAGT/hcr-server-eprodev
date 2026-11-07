
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#                  HCR SERVER EPRO DEV
#                 REINICIO DE SERVICIOS
# ============================================================

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

# ------------------------------------------------------------
# ENCABEZADO
# ------------------------------------------------------------

header() {
    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="R E I N I C I O   D E   S E R V I C I O S"

    clear 2>/dev/null || true

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

    printf '  %b●%b  %bSERVICIO HCR%b\n' \
        "$GREEN" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
        "$YELLOW" "$RESET" "$GRAY" "$RESET"

    printf '\n'
    line
}

# ------------------------------------------------------------
# DETECCIÓN DE SERVICIOS HCR
# ------------------------------------------------------------

declare -a SERVICES=()

discover_services() {

    local unit

    SERVICES=()

    while IFS= read -r unit; do

        [[ "$unit" =~ ^hcr-server(-[0-9]{1,5})?\.service$ ]] || continue

        SERVICES+=("$unit")

    done < <(
        {
            systemctl list-unit-files \
                --type=service --no-legend 2>/dev/null |
                awk '{print $1}'

            systemctl list-units \
                --all --type=service --no-legend 2>/dev/null |
                awk '{print $1}'

            find \
                /etc/systemd/system \
                /run/systemd/system \
                /usr/lib/systemd/system \
                /lib/systemd/system \
                -maxdepth 1 \
                \( -type f -o -type l \) \
                -name 'hcr-server*.service' \
                -printf '%f\n' 2>/dev/null || true

        } | sort -Vu
    )
}

# ------------------------------------------------------------
# REINICIO DE TODOS LOS SERVICIOS
# ------------------------------------------------------------

restart_services() {

    local unit
    local failed=0
    local message="REINICIO COMPLETADO"
    local returning="Regresando"
    local width=58
    local padding
    local i

    discover_services

    printf '\n'
    printf '  %b›%b  %bReiniciando los servicios...%b\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$RESET"

    for unit in "${SERVICES[@]}"; do

        if ! systemctl restart "$unit" >/dev/null 2>&1; then
            failed=1
        fi

    done

    # Verificar que todos los servicios hayan iniciado.

    for unit in "${SERVICES[@]}"; do

        if ! systemctl is-active --quiet "$unit"; then
            failed=1
        fi

    done

    printf '\n'

    if (( failed == 0 )); then

        printf '  %b✓%b  %bReinicio exitoso.%b\n' \
            "$GREEN$BOLD" "$RESET" "$GREEN" "$RESET"

    else

        printf '  %b✗%b  %bError al reiniciar uno o más servicios.%b\n' \
            "$RED$BOLD" "$RESET" "$RED" "$RESET"

    fi

    printf '\n'

    # --------------------------------------------------------
    # REINICIO COMPLETADO CENTRADO
    # --------------------------------------------------------

    padding=$(( (width - ${#message}) / 2 ))

    line

    printf '%*s%b%s%b\n' \
        "$padding" '' \
        "$GREEN$BOLD" "$message" "$RESET"

    line

    printf '\n'

    # --------------------------------------------------------
    # REGRESANDO
    # --------------------------------------------------------

    padding=$(( (width - ${#returning}) / 2 ))

    printf '%*s%b%s%b\n' \
        "$padding" '' \
        "$WHITE$BOLD" "$returning" "$RESET"

    # --------------------------------------------------------
    # CUENTA REGRESIVA EN AMARILLO
    # --------------------------------------------------------

    for ((i=3; i>=1; i--)); do

        printf '\r%*s%b%s%b' \
            "$(( (width - 1) / 2 ))" '' \
            "$YELLOW$BOLD" "$i" "$RESET"

        sleep 1

    done

    printf '\n'

    # Salida automática sin esperar ENTER.

    clear 2>/dev/null || true

    return 0
}

# ------------------------------------------------------------
# INICIO
# ------------------------------------------------------------

if (( EUID != 0 )); then
    printf 'Ejecuta el script como root.\n'
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    exit 1
fi

header
restart_services
