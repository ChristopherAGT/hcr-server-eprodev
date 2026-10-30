#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Desactivar job control para evitar mensajes [1] PID y [1] Done.
set +m 2>/dev/null || true

# ============================================================
#                 HCR SERVER | MULTIPORT
#                 UNINSTALLER PRO
# ============================================================
#
# FUNCIONES:
#   - Detección automática de servicios HCR multipuerto.
#   - Detección mediante archivos systemd y list-unit-files.
#   - Detención de todos los servicios encontrados.
#   - Desactivación del inicio automático en systemd.
#   - Eliminación de archivos de unidades systemd.
#   - Eliminación de enlaces de activación.
#   - Actualización de systemd.
#   - Limpieza de estados fallidos.
#   - Eliminación del binario HCR.
#   - Eliminación de la carpeta de instalación.
#   - Verificación de archivos y servicios restantes.
#   - Resumen detallado de la desinstalación.
#   - Spinner animado de seis puntos.
#   - Interfaz visual moderna con estados por color.
#
# ============================================================

# -------------------- CONFIGURACIÓN -------------------------

INSTALL_DIR="/usr/local/lib/hcr-server"
BINARY_PATH="$INSTALL_DIR/hcr-server"

SERVICE_PREFIX="hcr-server"
SYSTEMD_DIR="/etc/systemd/system"

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

# -------------------- CONTADORES ----------------------------

FOUND_SERVICES=()
REMOVED_SERVICES=()
FAILED_SERVICES=()

REMOVED_FILES=0
FAILED_FILES=0
REMOVED_DIRECTORIES=0
FAILED_DIRECTORIES=0

SPINNER_OUTPUT=""
RESULT_FILE=""

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
    printf '  %b◆%b  %b%s%b\n' "$CYAN" "$RESET" "$WHITE$BOLD" "$1" "$RESET"
    printf '\n'
}

# -------------------- ENCABEZADO ----------------------------

header() {
    clear 2>/dev/null || true

    local width=58
    local title="HCR SERVER EPRO DEV"
    local subtitle="D E S I N S T A L A D O R"

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

    printf '  %b●%b  %bLIMPIEZA COMPLETA DE HCR%b\n' \
        "$RED" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '  %b●%b  %bSCRIPT BY. ChristopherAGT%b\n' \
        "$YELLOW" "$RESET" "$GRAY" "$RESET"

    printf '\n'
    line
    printf '\n'
}

# -------------------- SPINNER --------------------------------

spinner() {
    local message="$1"
    shift

    local quiet_success=0

    # Permitir ocultar únicamente el mensaje de éxito del spinner.
    if [[ "${1:-}" == "--quiet-success" ]]; then
        quiet_success=1
        shift
    fi

    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴')
    local pid
    local status=0
    local i=0
    local output_file

    output_file=$(mktemp /tmp/hcr-uninstaller.XXXXXX) || return 1

    SPINNER_OUTPUT=""

    # Ejecutar la operación en segundo plano y capturar su salida.
    (
        set +m
        "$@" >"$output_file" 2>/dev/null
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

    if [[ -f "$output_file" ]]; then
        SPINNER_OUTPUT=$(<"$output_file")
        rm -f -- "$output_file"
    fi

    if (( status == 0 )); then
        if (( quiet_success == 0 )); then
            printf '\r\033[2K  %b✓%b  %b%s%b\n' \
                "$GREEN$BOLD" "$RESET" "$WHITE" "$message" "$RESET"
        else
            printf '\r\033[2K'
        fi
    else
        printf '\r\033[2K  %b✗%b  %b%s%b\n' \
            "$RED$BOLD" "$RESET" "$RED" "$message" "$RESET"
    fi

    return "$status"
}

# -------------------- RESULTADOS DE OPERACIONES -------------

# Las operaciones ejecutadas por spinner funcionan en un subshell.
# Este archivo permite conservar sus resultados en el proceso principal.

consume_results() {
    local type
    local value
    local extra
    local extra2
    local extra3

    [[ -n "$RESULT_FILE" && -f "$RESULT_FILE" ]] || return 0

    while IFS='|' read -r type value extra extra2 extra3; do
        case "$type" in
            STOP_OK)
                REMOVED_SERVICES+=("$value")
                ;;

            STOP_FAIL)
                FAILED_SERVICES+=("$value")
                ;;

            FILE_COUNTS)
                REMOVED_FILES=$((REMOVED_FILES + value))
                FAILED_FILES=$((FAILED_FILES + extra))
                ;;

            INSTALL_COUNTS)
                REMOVED_FILES=$((REMOVED_FILES + value))
                FAILED_FILES=$((FAILED_FILES + extra))
                REMOVED_DIRECTORIES=$((REMOVED_DIRECTORIES + extra2))
                FAILED_DIRECTORIES=$((FAILED_DIRECTORIES + extra3))
                ;;
        esac
    done < "$RESULT_FILE"

    # Evitar procesar dos veces los mismos resultados.
    : > "$RESULT_FILE"
}

# -------------------- DETECCIÓN DE SERVICIOS ----------------

detect_services() {
    local unit
    local service
    local unit_name

    local -a detected=()

    # Detectar archivos de unidades instalados directamente.
    if [[ -d "$SYSTEMD_DIR" ]]; then
        while IFS= read -r -d '' unit; do
            unit_name="${unit##*/}"

            [[ "$unit_name" == "${SERVICE_PREFIX}-"*.service ]] || continue

            detected+=("$unit_name")

        done < <(
            find "$SYSTEMD_DIR" \
                -maxdepth 1 \
                \( -type f -o -type l \) \
                -name "${SERVICE_PREFIX}-*.service" \
                -print0 2>/dev/null
        )
    fi

    # Detectar unidades registradas en systemd.
    while IFS= read -r service; do
        [[ "$service" == "${SERVICE_PREFIX}-"*.service ]] || continue

        detected+=("$service")

    done < <(
        systemctl list-unit-files \
            --type=service \
            --no-legend \
            --no-pager \
            2>/dev/null |
        awk '{print $1}'
    )

    # Detectar unidades actualmente cargadas.
    while IFS= read -r service; do
        [[ "$service" == "${SERVICE_PREFIX}-"*.service ]] || continue

        detected+=("$service")

    done < <(
        systemctl list-units \
            --all \
            --type=service \
            --plain \
            --no-legend \
            --no-pager \
            2>/dev/null |
        awk '{print $1}'
    )

    # Eliminar duplicados y ordenar.
    if (( ${#detected[@]} > 0 )); then
        printf '%s\n' "${detected[@]}" | sort -u
    fi

    return 0
}

# -------------------- CONFIRMACIÓN --------------------------

confirm_uninstall() {
    local answer
    local key

    printf '\n'
    line

    section "CONFIRMAR DESINSTALACIÓN"

    printf '  %bSe eliminarán los siguientes componentes:%b\n\n' \
        "$WHITE$BOLD" "$RESET"

    printf '  %b›%b  Todos los servicios HCR multipuerto detectados.\n' \
        "$CYAN" "$RESET"

    printf '  %b›%b  Archivos de unidades systemd correspondientes.\n' \
        "$CYAN" "$RESET"

    printf '  %b›%b  Enlaces de activación de dichos servicios.\n' \
        "$CYAN" "$RESET"

    printf '  %b›%b  Binario HCR: %s\n' \
        "$CYAN" "$RESET" "$BINARY_PATH"

    printf '  %b›%b  Carpeta de instalación: %s\n' \
        "$CYAN" "$RESET" "$INSTALL_DIR"

    printf '\n'

    while true; do

        printf '  %b¿Deseas continuar? [s/N]: %b' \
            "$YELLOW$BOLD" "$RESET"

        IFS= read -r answer || return 1

        case "${answer,,}" in
            s|si|sí|y|yes)
                return 0
                ;;

            ""|n|no)
                return 1
                ;;

            *)
                # Mostrar el error debajo de la pregunta.
                printf '  %b⚠ Entrada no válida. Ingrese una opción correcta.%b\n' \
                    "$RED$BOLD" "$RESET"

                # Esperar ENTER sin mostrar texto ni hacer eco.
                IFS= read -r -s key || return 1

                # Limpiar la línea vacía posterior al error.
                printf '\r\033[2K'

                # Limpiar el mensaje de error.
                printf '\033[1A\r\033[2K'

                # Limpiar la pregunta anterior.
                printf '\033[1A\r\033[2K'
                ;;
        esac
    done
}

# -------------------- DETENER Y DESHABILITAR ----------------

stop_services() {
    local service
    local failed

    for service in "${FOUND_SERVICES[@]}"; do
        failed=0

        # Detener y deshabilitar el servicio.
        systemctl disable --now "$service" \
            >/dev/null 2>&1 || true

        # Intentar detenerlo nuevamente por seguridad.
        systemctl stop "$service" \
            >/dev/null 2>&1 || true

        # Verificar que no siga activo.
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            failed=1
        fi

        # Verificar que no siga habilitado.
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            failed=1
        fi

        if (( failed == 0 )); then
            printf 'STOP_OK|%s\n' "$service" >> "$RESULT_FILE"
        else
            printf 'STOP_FAIL|%s\n' "$service" >> "$RESULT_FILE"
        fi
    done

    return 0
}

# -------------------- ELIMINAR UNIDADES SYSTEMD --------------

remove_service_files() {
    local service
    local path
    local failed
    local link

    local removed=0
    local failed_count=0

    for service in "${FOUND_SERVICES[@]}"; do
        failed=0

        # Archivo principal de la unidad.
        path="$SYSTEMD_DIR/$service"

        if [[ -e "$path" || -L "$path" ]]; then
            if rm -f -- "$path"; then
                removed=$((removed + 1))
            else
                failed_count=$((failed_count + 1))
                failed=1
            fi
        fi

        # Eliminar enlaces de activación del servicio.
        # Incluye directorios .wants y .requires.
        if [[ -d "$SYSTEMD_DIR" ]]; then
            while IFS= read -r -d '' link; do
                if rm -f -- "$link"; then
                    removed=$((removed + 1))
                else
                    failed_count=$((failed_count + 1))
                    failed=1
                fi
            done < <(
                find "$SYSTEMD_DIR" \
                    -mindepth 2 \
                    -maxdepth 2 \
                    -type l \
                    -name "$service" \
                    -print0 2>/dev/null
            )
        fi
    done

    printf 'FILE_COUNTS|%s|%s\n' \
        "$removed" "$failed_count" >> "$RESULT_FILE"

    return 0
}

# -------------------- ACTUALIZAR SYSTEMD --------------------

refresh_systemd() {
    systemctl daemon-reload || return 1

    if (( ${#FOUND_SERVICES[@]} > 0 )); then
        systemctl reset-failed "${FOUND_SERVICES[@]}" \
            >/dev/null 2>&1 || true
    fi

    return 0
}

# -------------------- ELIMINAR BINARIO Y CARPETA ------------

remove_installation() {
    local file_count=0
    local directory_count=0
    local failed_files=0
    local failed_directories=0

    # Eliminar la carpeta completa de instalación.
    if [[ -d "$INSTALL_DIR" && ! -L "$INSTALL_DIR" ]]; then

        file_count=$(
            find "$INSTALL_DIR" \
                \( -type f -o -type l \) \
                -printf '.' 2>/dev/null |
            wc -c
        ) || file_count=0

        directory_count=$(
            find "$INSTALL_DIR" \
                -type d \
                -printf '.' 2>/dev/null |
            wc -c
        ) || directory_count=0

        if rm -rf -- "$INSTALL_DIR"; then
            :
        else
            failed_directories=1
        fi

    elif [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then

        # Si la ruta es un enlace simbólico u otro archivo.
        if rm -f -- "$INSTALL_DIR"; then
            file_count=1
        else
            failed_files=1
        fi

    elif [[ -e "$BINARY_PATH" || -L "$BINARY_PATH" ]]; then

        if rm -f -- "$BINARY_PATH"; then
            file_count=1
        else
            failed_files=1
        fi
    fi

    printf 'INSTALL_COUNTS|%s|%s|%s|%s\n' \
        "$file_count" "$failed_files" \
        "$directory_count" "$failed_directories" >> "$RESULT_FILE"

    if (( failed_files > 0 || failed_directories > 0 )); then
        return 1
    fi

    return 0
}

# -------------------- VERIFICACIÓN FINAL -------------------

verify_uninstall() {
    local service
    local link
    local remaining=0
    local service_remaining

    for service in "${FOUND_SERVICES[@]}"; do
        service_remaining=0

        # Verificar que el servicio no siga activo.
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            error "El servicio continúa activo: $service"
            service_remaining=1
        fi

        # Verificar que el archivo principal no exista.
        if [[ -e "$SYSTEMD_DIR/$service" || -L "$SYSTEMD_DIR/$service" ]]; then
            error "Todavía existe la unidad: $service"
            service_remaining=1
        fi

        # Verificar que no queden enlaces de activación.
        if [[ -d "$SYSTEMD_DIR" ]]; then
            while IFS= read -r -d '' link; do
                error "Enlace de activación restante: $link"
                service_remaining=1
            done < <(
                find "$SYSTEMD_DIR" \
                    -mindepth 2 \
                    -maxdepth 2 \
                    -type l \
                    -name "$service" \
                    -print0 2>/dev/null
            )
        fi

        # Verificar que no siga habilitado.
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            error "El servicio todavía está habilitado: $service"
            service_remaining=1
        fi

        if (( service_remaining > 0 )); then
            remaining=$((remaining + 1))
        fi
    done

    # Verificar el binario.
    if [[ -e "$BINARY_PATH" || -L "$BINARY_PATH" ]]; then
        error "El binario HCR todavía existe."
        remaining=$((remaining + 1))
    fi

    # Verificar la carpeta.
    if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
        error "La carpeta de instalación todavía existe."
        remaining=$((remaining + 1))
    fi

    return "$remaining"
}

# -------------------- RESUMEN FINAL -------------------------

show_summary() {
    local removed_services="${#REMOVED_SERVICES[@]}"
    local failed_services="${#FAILED_SERVICES[@]}"

    # Anchos fijos para mantener alineadas las columnas.
    local label_width=28
    local value_width=5

    printf '\n'
    line

    section "RESULTADO DE DESINSTALACIÓN"

    # El total de archivos aparece siempre como primera línea.
    printf '  %b%-*s%b %b%*s%b\n' \
        "$GRAY" "$label_width" "Total archivos eliminados:" "$RESET" \
        "$GREEN$BOLD" "$value_width" "$REMOVED_FILES" "$RESET"

    printf '  %b%-*s%b %b%*s%b\n' \
        "$GRAY" "$label_width" "Servicios desactivados:" "$RESET" \
        "$GREEN$BOLD" "$value_width" "$removed_services" "$RESET"

    printf '  %b%-*s%b %b%*s%b\n' \
        "$GRAY" "$label_width" "Directorios eliminados:" "$RESET" \
        "$GREEN$BOLD" "$value_width" "$REMOVED_DIRECTORIES" "$RESET"

    if (( failed_services > 0 )); then
        printf '\n'
        printf '  %b%-*s%b %b%*s%b\n' \
            "$GRAY" "$label_width" "Servicios con problemas:" "$RESET" \
            "$RED$BOLD" "$value_width" "$failed_services" "$RESET"
    fi

    if (( FAILED_FILES > 0 )); then
        printf '  %b%-*s%b %b%*s%b\n' \
            "$GRAY" "$label_width" "Archivos con errores:" "$RESET" \
            "$RED$BOLD" "$value_width" "$FAILED_FILES" "$RESET"
    fi

    if (( FAILED_DIRECTORIES > 0 )); then
        printf '  %b%-*s%b %b%*s%b\n' \
            "$GRAY" "$label_width" "Directorios pendientes:" "$RESET" \
            "$YELLOW$BOLD" "$value_width" "$FAILED_DIRECTORIES" "$RESET"
    fi
}

# -------------------- EJECUCIÓN PRINCIPAL -------------------

main() {
    local verification_status=0
    local message
    local width=58

    # Desactivar job control para evitar mensajes de trabajos.
    set +m 2>/dev/null || true

    if (( EUID != 0 )); then
        printf '%b✗%b  %bEjecuta el desinstalador como root.%b\n' \
            "$RED" "$RESET" "$WHITE" "$RESET"
        exit 1
    fi

    for command in systemctl rm sort awk find mktemp wc; do
        if ! command -v "$command" >/dev/null 2>&1; then
            error "Falta una dependencia: $command"
            exit 1
        fi
    done

    header

    # La detección devuelve los servicios por salida estándar.
    # El spinner captura esa salida para recuperarla en el proceso principal.
    # Se oculta el mensaje de éxito para evitar una línea redundante
    # cuando no existen componentes HCR instalados.
    if ! spinner "Buscando servicios HCR instalados" --quiet-success detect_services; then
        error "No se pudieron detectar los servicios."
        exit 1
    fi

    if [[ -n "$SPINNER_OUTPUT" ]]; then
        mapfile -t FOUND_SERVICES <<< "$SPINNER_OUTPUT"
    fi

    # Si no existen servicios ni archivos de instalación,
    # no hay componentes que desinstalar.
    if (( ${#FOUND_SERVICES[@]} == 0 )) &&
       [[ ! -e "$BINARY_PATH" && ! -L "$BINARY_PATH" ]] &&
       [[ ! -e "$INSTALL_DIR" && ! -L "$INSTALL_DIR" ]]; then

        printf '\n'
        success "No se encontraron componentes de HCR para eliminar."
        printf '\n'
        line
        exit 0
    fi

    # No imprimir otra línea divisoria aquí.
    # El encabezado ya dejó la separación visual correspondiente.
    section "COMPONENTES DETECTADOS"

    if (( ${#FOUND_SERVICES[@]} > 0 )); then
        success "Servicios HCR encontrados: ${#FOUND_SERVICES[@]}"
    else
        info "No se encontraron servicios HCR registrados."
    fi

    if [[ -e "$BINARY_PATH" || -L "$BINARY_PATH" ]]; then
        info "Binario: $BINARY_PATH"
    fi

    if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
        info "Carpeta: $INSTALL_DIR"
    fi

    if ! confirm_uninstall; then
        printf '\n'
        line
        printf '\n'

        message="DESINSTALACIÓN CANCELADA"

        printf '%*s%b%s%b\n' \
            "$(( (width - ${#message}) / 2 ))" '' \
            "$RED$BOLD" "$message" "$RESET"

        printf '\n'
        line
        printf '\n'

        exit 0
    fi

    # Archivo temporal compartido por las operaciones del spinner.
    RESULT_FILE=$(mktemp /tmp/hcr-uninstaller-results.XXXXXX)
    trap '[[ -n "$RESULT_FILE" ]] && rm -f -- "$RESULT_FILE"' EXIT

    printf '\n'
    line
    printf '\n'

    if (( ${#FOUND_SERVICES[@]} > 0 )); then

        # Detener y desactivar servicios.
        spinner "Deteniendo y desactivando servicios HCR" stop_services || true
        consume_results

        # Eliminar unidades y enlaces systemd.
        spinner "Eliminando archivos de servicios systemd" remove_service_files || true
        consume_results

        if (( ${#FAILED_SERVICES[@]} > 0 )); then
            warning "Servicios con problemas: ${#FAILED_SERVICES[@]}"
        fi

    else
        info "No hay servicios HCR que desactivar."
    fi

    # Actualizar systemd.
    if ! spinner "Actualizando configuración de systemd" refresh_systemd; then
        error "No se pudo actualizar systemd."
    fi

    # Eliminar instalación.
    if ! spinner "Eliminando binario y carpeta HCR" remove_installation; then
        error "No se pudo eliminar completamente la instalación."
    fi

    consume_results

    # Actualizar systemd después de eliminar los archivos.
    if ! systemctl daemon-reload >/dev/null 2>&1; then
        warning "No se pudo completar la recarga final de systemd."
    fi

    # Verificación final.
    verify_uninstall || verification_status=$?

    # Mostrar los resultados una sola vez.
    show_summary

    if (( verification_status > 0 ||
          FAILED_FILES > 0 ||
          FAILED_DIRECTORIES > 0 ||
          ${#FAILED_SERVICES[@]} > 0 )); then

        error "La desinstalación terminó con elementos pendientes."
        exit 1
    fi

    printf '\n'
    line
    printf '\n'

    message="DESINSTALACIÓN COMPLETADA"

    printf '%*s%b%s%b\n' \
        "$(( (width - ${#message}) / 2 ))" '' \
        "$GREEN$BOLD" "$message" "$RESET"

    printf '\n'
    line
    printf '\n'
}

main "$@"
