#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#                  HCR SERVER EPRO DEV
#                 INICIAR / DETENER SERVICIOS
# ============================================================

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
# INICIAR / DETENER TODOS LOS SERVICIOS
# ------------------------------------------------------------

manage_services() {

    local unit
    local any_active=0
    local failed=0

    discover_services

    # --------------------------------------------------------
    # SI NO EXISTEN SERVICIOS, NO HACER NADA
    # --------------------------------------------------------

    ((${#SERVICES[@]} == 0)) && return 0

    # --------------------------------------------------------
    # COMPROBAR SI AL MENOS UN SERVICIO ESTÁ ACTIVO
    # --------------------------------------------------------

    for unit in "${SERVICES[@]}"; do

        if systemctl is-active --quiet "$unit" 2>/dev/null; then
            any_active=1
            break
        fi

    done

    # --------------------------------------------------------
    # SI ALGUNO ESTÁ ACTIVO, DETENER TODOS
    # --------------------------------------------------------

    if (( any_active == 1 )); then

        for unit in "${SERVICES[@]}"; do

            systemctl stop "$unit" >/dev/null 2>&1 || failed=1

        done

    # --------------------------------------------------------
    # SI TODOS ESTÁN INACTIVOS, INICIAR TODOS
    # --------------------------------------------------------

    else

        for unit in "${SERVICES[@]}"; do

            systemctl start "$unit" >/dev/null 2>&1 || failed=1

        done

    fi

    return "$failed"
}

# ------------------------------------------------------------
# INICIO
# ------------------------------------------------------------

if (( EUID != 0 )); then
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    exit 1
fi

manage_services
