🚀 HCR Server

Instalador y administrador de HCR Server para Linux con systemd.

"🇪🇸 Español" (#español) | "🇬🇧 English" (#english)

---

🇪🇸 Español

📌 Descripción

HCR Server incluye un instalador para sistemas Linux que utilizan "systemd".

Para instalarlo, debes colocar el script "install.sh" y el binario "hcr-server", correspondiente a la arquitectura de tu servidor, dentro de un mismo directorio. Por ejemplo:

/root/hcr

El directorio donde se encuentra el instalador se utiliza automáticamente como directorio de trabajo ("WorkingDirectory") del servicio.

📋 1. Requisitos y preparación

🖥️ Arquitecturas compatibles

Selecciona el paquete correspondiente a la arquitectura de tu servidor:

Arquitectura| Descripción
"386"| Procesadores x86 con SSE2
"amd64"| Procesadores x86-64
"arm"| ARMv7
"arm64"| ARM de 64 bits

Descarga el paquete desde una fuente confiable y extráelo en un directorio nuevo.

🔎 Comprobar la versión

Desde el directorio donde se encuentran los archivos, ejecuta:

./hcr-server --version

🔐 Configurar permisos

Asegúrate de que el directorio y sus archivos pertenezcan a "root" y que ningún otro usuario pueda modificarlos.

cd /root/hcr

sudo chown -R root:root /root/hcr
sudo chmod 755 /root/hcr install.sh hcr-server

Importante:

- Los certificados TLS y las claves privadas deben ser proporcionados por el administrador.
- Estos archivos no están incluidos en el paquete.
- Comprueba que el puerto seleccionado esté disponible y permitido por el firewall.

⚡ 2. Instalación

HCR Server admite diferentes modalidades de transporte.

🔹 Opción A: HCR Plain (sin TLS)

Para instalar HCR sin cifrado TLS, únicamente necesitas el instalador y el binario.

Ejecuta:

sudo ./install.sh --transport plain --port 8080 --target 127.0.0.1:22

Esta configuración utiliza:

Parámetro| Valor
Transporte| "plain"
Puerto| "8080"
Destino SSH| "127.0.0.1:22"

🔹 Opción B: HCR Auto (TLS y no TLS)

Permite recibir conexiones TLS y no TLS utilizando el mismo puerto.

Para utilizar esta modalidad, coloca los siguientes archivos dentro del directorio del instalador:

- "fullchain.pem" — Certificado TLS.
- "privkey.pem" — Clave privada TLS.

Configura los permisos de la clave privada:

sudo chmod 600 privkey.pem

Después, ejecuta el instalador:

sudo ./install.sh

🔹 Opción C: HCR TLS (solo TLS)

Permite aceptar únicamente conexiones TLS.

Ejecuta:

sudo ./install.sh --transport tls

Esta modalidad también requiere los archivos "fullchain.pem" y "privkey.pem", salvo que se especifiquen otras rutas mediante los parámetros correspondientes.

⚙️ Valores predeterminados

Cuando se ejecuta el instalador sin argumentos, utiliza los siguientes valores:

Parámetro| Valor predeterminado
Puerto| "8080"
Transporte| "auto"
Destino SSH| "127.0.0.1:22"
Certificado TLS| "fullchain.pem"
Clave privada TLS| "privkey.pem"

Nota: puedes modificar el puerto mediante "--port". El puerto seleccionado se utiliza en todas las direcciones de red del servidor.

⚙️ 3. Configuración del servidor

Para consultar todas las opciones disponibles, ejecuta:

./install.sh --help

🛠️ Parámetros disponibles

Parámetro| Descripción
"--port"| Puerto de escucha del servidor.
"--transport"| Modalidad de transporte: "auto", "tls" o "plain".
"--target"| Dirección y puerto del servidor SSH de destino.
"--tls-cert"| Ruta del certificado TLS.
"--tls-key"| Ruta de la clave privada TLS.
"--max-connections"| Límite global de conexiones.
"--max-sessions"| Límite global de sesiones.
"--max-sessions-per-ip"| Límite de sesiones por dirección IP.
"--session-stats-interval"| Intervalo de registro de estadísticas por sesión.
"--diagnostics-interval"| Intervalo de diagnóstico de conexión.
"--max-download-frame"| Tamaño máximo de los frames de descarga.
"--download-poll-timeout"| Tiempo máximo de espera de una conexión de descarga.
"--uninstall"| Desinstala el servicio.
"--version"| Muestra la versión del binario.
"--help"| Muestra la ayuda del instalador.

🔄 Modificar la configuración

Para cambiar los parámetros, vuelve a ejecutar el instalador incluyendo todas las opciones que deseas conservar.

Importante:

- El servicio se reiniciará al aplicar los cambios.
- Las conexiones activas se interrumpirán.
- Los parámetros omitidos volverán a sus valores predeterminados.
- El instalador comprueba el valor de Frame antes de escribir el archivo del servicio o reiniciarlo.
- Los demás parámetros se transmiten directamente a HCR Server.

Si el servicio no consigue iniciarse, consulta los registros:

journalctl -u hcr-server

Nota técnica: el instalador administra el servicio denominado "hcr-server", sin comprobar si originalmente pertenece a otro directorio.

El servicio se ejecuta como "root", utilizando la configuración predeterminada de systemd, sin límites adicionales de recursos ni aislamiento.

📦 4. Frames y compatibilidad

El tamaño máximo de los frames de descarga se configura mediante:

--max-download-frame

📊 Valores disponibles

Parámetro| Valor
Valor predeterminado| "16384" bytes
Valor mínimo| "1" byte
Valor máximo documentado| "262140" bytes

🔎 Validación de compatibilidad

Cuando se configura un Frame superior a "16384" bytes, el instalador comprueba el límite admitido por el binario "hcr-server" que se encuentra en el mismo directorio.

Si el valor no es válido o el binario no admite ese tamaño, el instalador se detiene sin modificar el servicio existente.

⚠️ Consideraciones importantes

- Los valores superiores a "16384" bytes requieren una versión actualizada de HC en todos los clientes que utilicen ese listener.
- Un Frame más grande no garantiza una mayor velocidad.
- Los tamaños superiores utilizan buffers más grandes.

🔎 5. Diagnósticos y registros

HCR Server permite activar diagnósticos para analizar el comportamiento de las conexiones y las condiciones de la ruta de comunicación.

⚙️ Activar diagnósticos

Añade el siguiente parámetro junto con las demás opciones de instalación:

--diagnostics-interval 10s

📊 Intervalos disponibles

Valor| Comportamiento
"0"| Diagnósticos desactivados
"10s"| Intervalo mínimo
"5m"| Intervalo máximo

Los registros contienen resúmenes técnicos y no incluyen contenido de los paquetes ni credenciales.

Importante: si deseas mantener los diagnósticos activos después de modificar la configuración, debes volver a incluir "--diagnostics-interval" al ejecutar el instalador.

📊 6. Estado y supervisión

Puedes consultar la versión, el estado del servicio y los registros utilizando los siguientes comandos.

🔹 Consultar versión

./install.sh --version

🔹 Consultar estado del servicio

systemctl status hcr-server

🔹 Consultar los últimos 50 registros

journalctl -u hcr-server -n 50

🔹 Consultar registros en tiempo real

journalctl -u hcr-server -f

🗑️ 7. Desinstalación

Para desinstalar HCR Server, ejecuta:

sudo ./install.sh --uninstall

📌 ¿Qué realiza la desinstalación?

- Detiene el servicio "hcr-server".
- Deshabilita el servicio de systemd.
- Elimina el enlace del servicio ubicado en "/etc/systemd/system/".

📁 Archivos que se conservan

La desinstalación no elimina los siguientes elementos:

- Script "install.sh".
- Binario "hcr-server".
- Certificados TLS.
- Claves privadas.
- Archivo de unidad "hcr-server.service".

Todos estos archivos permanecen en el directorio original del instalador.

---

🇬🇧 English

📌 Description

HCR Server includes an installer for Linux systems using "systemd".

To install it, place the "install.sh" script and the "hcr-server" binary matching your server architecture in the same directory. For example:

/root/hcr

The directory containing the installer is automatically used as the service working directory ("WorkingDirectory").

📋 1. Requirements and preparation

🖥️ Supported architectures

Choose the package matching your server architecture:

Architecture| Description
"386"| x86 processors with SSE2
"amd64"| x86-64 processors
"arm"| ARMv7
"arm64"| 64-bit ARM

Download the package from a trusted source and extract it into a new directory.

🔎 Check the version

From the directory containing the files, run:

./hcr-server --version

🔐 Configure permissions

Make sure the directory and its files are owned by "root" and cannot be modified by other users.

cd /root/hcr

sudo chown -R root:root /root/hcr
sudo chmod 755 /root/hcr install.sh hcr-server

Important:

- TLS certificates and private keys must be provided by the administrator.
- These files are not included in the package.
- Make sure the selected port is available and allowed by the firewall.

⚡ 2. Installation

HCR Server supports different transport modes.

🔹 Option A: HCR Plain (without TLS)

To install HCR without TLS encryption, you only need the installer and binary.

Run:

sudo ./install.sh --transport plain --port 8080 --target 127.0.0.1:22

This configuration uses:

Parameter| Value
Transport| "plain"
Port| "8080"
SSH target| "127.0.0.1:22"

🔹 Option B: HCR Auto (TLS and non-TLS)

This mode allows TLS and non-TLS connections on the same port.

To use this mode, place the following files in the installer directory:

- "fullchain.pem" — TLS certificate.
- "privkey.pem" — TLS private key.

Set the private key permissions:

sudo chmod 600 privkey.pem

Then run the installer:

sudo ./install.sh

🔹 Option C: HCR TLS (TLS only)

This mode allows TLS connections only.

Run:

sudo ./install.sh --transport tls

This mode also requires the "fullchain.pem" and "privkey.pem" files, unless different paths are specified using the corresponding parameters.

⚙️ Default values

When the installer runs without arguments, it uses the following values:

Parameter| Default value
Port| "8080"
Transport| "auto"
SSH target| "127.0.0.1:22"
TLS certificate| "fullchain.pem"
TLS private key| "privkey.pem"

Note: you can change the port using "--port". The selected port is used on all server network addresses.

⚙️ 3. Server configuration

To view all available options, run:

./install.sh --help

🛠️ Available parameters

Parameter| Description
"--port"| Server listening port.
"--transport"| Transport mode: "auto", "tls", or "plain".
"--target"| Destination SSH server address and port.
"--tls-cert"| TLS certificate path.
"--tls-key"| TLS private key path.
"--max-connections"| Global connection limit.
"--max-sessions"| Global session limit.
"--max-sessions-per-ip"| Session limit per IP address.
"--session-stats-interval"| Session statistics logging interval.
"--diagnostics-interval"| Connection diagnostics interval.
"--max-download-frame"| Maximum download frame size.
"--download-poll-timeout"| Maximum waiting time for a download connection.
"--uninstall"| Uninstalls the service.
"--version"| Displays the binary version.
"--help"| Displays installer help.

🔄 Change the configuration

To change the parameters, run the installer again with all the options you want to keep.

Important:

- The service will restart when changes are applied.
- Active connections will be interrupted.
- Omitted parameters will return to their default values.
- The installer validates the Frame value before writing the service file or restarting it.
- Other parameters are passed directly to HCR Server.

If the service fails to start, check the logs:

journalctl -u hcr-server

Technical note: the installer manages the service named "hcr-server" without checking whether it originally belongs to another directory.

The service runs as "root", using systemd default settings, without additional resource limits or isolation.

📦 4. Frames and compatibility

The maximum download frame size is configured using:

--max-download-frame

📊 Available values

Parameter| Value
Default value| "16384" bytes
Minimum value| "1" byte
Documented maximum value| "262140" bytes

🔎 Compatibility validation

When a Frame larger than "16384" bytes is configured, the installer checks the limit supported by the "hcr-server" binary located in the same directory.

If the value is invalid or the binary does not support that size, the installer stops without modifying the existing service.

⚠️ Important considerations

- Values above "16384" bytes require an updated HC version on every client using that listener.
- A larger Frame does not guarantee higher speeds.
- Larger frame sizes use larger buffers.

🔎 5. Diagnostics and logs

HCR Server allows diagnostics to be enabled to analyze connection behavior and communication path conditions.

⚙️ Enable diagnostics

Add the following parameter alongside the other installation options:

--diagnostics-interval 10s

📊 Available intervals

Value| Behavior
"0"| Diagnostics disabled
"10s"| Minimum interval
"5m"| Maximum interval

Logs contain technical summaries and do not include packet payloads or credentials.

Important: if you want diagnostics to remain enabled after changing the configuration, you must include "--diagnostics-interval" again when running the installer.

📊 6. Status and monitoring

You can check the version, service status, and logs using the following commands.

🔹 Check version

./install.sh --version

🔹 Check service status

systemctl status hcr-server

🔹 View the last 50 log entries

journalctl -u hcr-server -n 50

🔹 Follow logs in real time

journalctl -u hcr-server -f

🗑️ 7. Uninstallation

To uninstall HCR Server, run:

sudo ./install.sh --uninstall

📌 What does uninstallation do?

- Stops the "hcr-server" service.
- Disables the systemd service.
- Removes the service link located at "/etc/systemd/system/".

📁 Files that are preserved

Uninstallation does not delete the following items:

- "install.sh" script.
- "hcr-server" binary.
- TLS certificates.
- Private keys.
- "hcr-server.service" unit file.

All these files remain in the installer's original directory.

---

HCR Server — Linux systemd installer and service manager.
