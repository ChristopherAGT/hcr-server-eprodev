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
# SPINNER
# ------------------------------------------------------------

spinner() {

    local pid="$1"
    local message="Reiniciando los servicios HCR"
    local width=58
    local frame=0

    local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴')

    while kill -0 "$pid" 2>/dev/null; do

        printf '\r\033[K  %b%s%b  %b%s%b' \
            "$CYAN$BOLD" "${frames[$frame]}" "$RESET" \
            "$WHITE$BOLD" "$message" "$RESET"

        frame=$(( (frame + 1) % 6 ))

        sleep 0.15

    done

    printf '\r\033[K'

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

    # --------------------------------------------------------
    # COMPROBAR SI EXISTEN SERVICIOS HCR
    # --------------------------------------------------------

    if ((${#SERVICES[@]} == 0)); then

        message="NO HAY SERVICIOS HCR"
        padding=$(( (width - ${#message}) / 2 ))

        line

        printf '%*s%b%s%b\n' \
            "$padding" '' \
            "$YELLOW$BOLD" "$message" "$RESET"

        line

    else

        # ----------------------------------------------------
        # REINICIAR SERVICIOS CON SPINNER
        # ----------------------------------------------------

        (
            for unit in "${SERVICES[@]}"; do

                systemctl restart "$unit" >/dev/null 2>&1 || exit 1

            done

            for unit in "${SERVICES[@]}"; do

                systemctl is-active --quiet "$unit" || exit 1

            done

        ) &

        local restart_pid=$!

        spinner "$restart_pid"

        if wait "$restart_pid"; then
            failed=0
        else
            failed=1
        fi

        # ----------------------------------------------------
        # REINICIO COMPLETADO
        # ----------------------------------------------------

        padding=$(( (width - ${#message}) / 2 ))

        line

        if (( failed == 0 )); then

            printf '%*s%b%s%b\n' \
                "$padding" '' \
                "$GREEN$BOLD" "$message" "$RESET"

        else

            message="ERROR EN EL REINICIO"
            padding=$(( (width - ${#message}) / 2 ))

            printf '%*s%b%s%b\n' \
                "$padding" '' \
                "$RED$BOLD" "$message" "$RESET"

        fi

        line

    fi

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

        printf '\r\033[K%*s%b%s%b' \
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
