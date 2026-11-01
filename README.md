# iOS 7 Assistant — 0.2.3

Aplicación sencilla de macOS para el método de downgrade y arranque asistido usado en este proyecto.

**Apple Silicon · macOS Sonoma 14 o posterior · iPhone 5s Global iPhone6,2 / n53ap · iOS 7.1.2.** Intel y iPhone6,1 no están incluidos en esta versión. La compilación y sus dependencias tienen un mínimo de macOS 14; la prueba de ejecución se realizó en macOS 27. Aún falta validar con dispositivos reales en las otras versiones de macOS.

## Abrir

Abre el DMG y arrastra **iOS 7 Assistant** a Aplicaciones. También puedes abrir la app descomprimida. **No necesitas instalar Legacy-iOS-Kit, 5sd7, Homebrew, Python, Rosetta ni otras herramientas.** Todos los ejecutables y bibliotecas necesarios están dentro de la app.

Esta compilación tiene firma local ad hoc y no está notarizada con Developer ID. Al descargarla por internet, macOS puede pedir autorización en Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente. No desactives Gatekeeper. Para una distribución pública sin ese aviso se necesita firmar y notarizar con una cuenta de desarrollador de Apple.

## Preparar una vez

1. Selecciona Español o English.
2. Elige los dos IPSW originales: `iPhone6,2_7.1.2_11D257_Restore.ipsw` e `iPhone_4.0_64bit_12.5.8_16H88_Restore.ipsw`. No se distribuye firmware de Apple dentro de la app.
3. Pulsa **Preparar archivos** y elige una carpeta nueva. Necesitas al menos 12 GB libres. La app verifica los SHA-256, prepara los componentes y guarda una carpeta reutilizable. Esta etapa no modifica el iPhone.
4. Conserva esa carpeta: sirve para instalar y para los arranques posteriores. En otro Mac, usa **Abrir carpeta preparada…** para verificarla y utilizarla.

La primera personalización necesita internet para solicitar un ticket a Apple. Las restauraciones y la activación también requieren conexión a sus servicios. La disponibilidad de estos servicios no está bajo control de la app.

## Instalar iOS 7

1. Selecciona **Instalar iOS 7** y pulsa **Empezar**.
2. Conecta **Lightning → USB-A + adaptador USB-C**. Mantén Inicio + encendido 10 s; suelta encendido y mantén Inicio otros 10 s. Pantalla negra. Pulsa **Comprobar DFU**.
3. Cambia a **Lightning → USB-C directo al Mac**, sin pulsar botones. La app comprueba el mismo iPhone, prepara sus archivos y carga iBSS.
4. Primera pausa: desconecta y reconecta **solo el extremo USB-C del Mac**. Pulsa **Ya reconecté: comprobar**. Solo entonces se carga iBEC.
5. Segunda pausa: reconecta otra vez solo el USB-C del Mac y pulsa el botón. La app comprueba Recovery y la versión de iBEC.
6. Lee y confirma el borrado. La instalación borra todos los datos. Mantén el cable conectado; reconéctalo durante la instalación únicamente cuando la app indique que espera al teléfono.
7. Tras finalizar, pulsa **Realizar primer arranque** y sigue el flujo de arranque.

Después del primer arranque, verifica iOS 7 y continúa con la activación y con **Continuar con jailbreak y parches**. Si se confirma `Activated`, la app muestra: **«El dispositivo ya está activado. Salta la configuración Wi-Fi para continuar»**. La consulta usa directamente el estado del iPhone; evita el código de salida engañoso de la herramienta anterior.

## Arrancar después de apagar

Selecciona **Arrancar iOS 7** con la misma carpeta preparada. Repite DFU con **USB-A + adaptador**, cambia a **USB-C directo** y completa las dos reconexiones de iBSS/iBEC. Pulsa **Arrancar iOS 7**. No reinstala ni borra el teléfono. Cuando aparezca iOS, pulsa **Verificar iOS 7**; la app consulta su versión y ECID. La activación opcional usa el servicio oficial de Apple y no elude el Bloqueo de activación.

Este método necesita el Mac tras cada apagado o reinicio. No configures código ni Touch ID. Conecta un solo iPhone durante el procedimiento. Una transferencia finalizada no demuestra por sí sola que iOS haya arrancado: comprueba la pantalla y usa la verificación.

## Cydia, Wi-Fi y suspensión

Después de activar, pulsa **Continuar con jailbreak y parches**. Si ya tienes iOS 7 encendido, también puedes seleccionar directamente **Cydia y parches** en la pantalla inicial y usar tu carpeta preparada.

1. Mantén el iPhone encendido mientras la app comprueba la activación y prepara los archivos. Si falta activar, lo intentará con el servicio de Apple usando internet del Mac. La primera preparación descarga componentes de mantenimiento desde Apple y paquetes desde los repositorios originales; verifica sus SHA-256. PreferenceLoader se incluye con su licencia y fuente porque el servidor de descarga original tiene el certificado vencido.
2. Entra en DFU con USB-A + adaptador, cambia a USB-C directo y sigue las dos pausas de reconexión tras iBSS/iBEC. La app espera un segundo tras cada reconexión antes de comprobar el modo.
3. Pulsa **Iniciar mantenimiento**. Espera a que aparezca texto, reconecta el USB-C si hace falta y pulsa **Conectar e instalar Cydia y parches**. Se verifica el ECID desde el entorno de mantenimiento, se respalda lo que se sustituye y se prepara Cydia sin formatear la partición de datos. Si ya encuentra Cydia, se detiene para conservar la instalación existente.
4. Pulsa **Continuar al arranque final**. Repite DFU con USB-A, cambia a USB-C, completa las dos reconexiones y arranca iOS 7. El instalador terminará durante ese arranque.
5. Pulsa **Verificar iOS 7** y luego **Completar y comprobar los parches**. La app comprueba los seis paquetes, Fiona habilitado y la activación; retira el instalador temporal y deshabilita SSH de mantenimiento. Las conexiones de mantenimiento se limitan a USB/localhost.
6. Abre Cydia, prueba una red WPA2 con contraseña y bloquea unos tres minutos sin cable. Marca las comprobaciones en la app cuando las hayas realizado. SCS WiFi Fix no añade WPA3. Fiona puede aumentar el consumo de batería. El Mac sigue siendo necesario tras apagar o reiniciar.

Los respaldos y registros quedan en `maintenance-session-*` dentro de la carpeta preparada. No se marcan como terminadas las instalaciones que no superan la comprobación de paquetes y activación.

## Registros

**Guardar registro…** exporta los detalles para diagnosticar fallos.

## Créditos

**@criss.repair_** · [YouTube: CrissRepair](https://www.youtube.com/@CrissRepair). Desarrollado con asistencia de **Codex**. Los exploits, herramientas y bibliotecas pertenecen a sus autores originales. La app incluye créditos, avisos, licencias, fuentes y el parche de idevicerestore. Consulta [CREDITS.md](Resources/Licenses/CREDITS.md).

## English

Standalone macOS app for **Apple Silicon, macOS 14+, iPhone6,2/n53ap and iOS 7.1.2**. Intel is not included. No Homebrew, Python, Rosetta or prerequisite tool installation is needed. Select English in the app.

Open the DMG and drag the app into Applications. This is an ad-hoc signed, unnotarized build; downloaded copies may need macOS “Open Anyway” approval. The original 7.1.2 and 12.5.8 IPSWs are selected separately. Prepare a reusable folder once, or import an existing prepared folder. Keep it for future boots.

Use **Lightning to USB-A + USB-C adapter for DFU entry**, then **Lightning to USB-C directly into the Mac for pwnDFU and uploads**. Manually reconnect the Mac USB-C end after iBSS and after iBEC, checking the device at each pause. Installation erases the phone and requires explicit confirmation. Boot mode preserves the installed system. After activation, choose **Continue to jailbreak & fixes**, or select **Cydia & fixes** from the start screen for an already booted phone. The app prepares maintenance, guides DFU and both reconnections, stages Cydia, SCS WiFi Fix and Fiona, guides the final boot, verifies the packages and activation, and closes maintenance access. Test Cydia, WPA2 Wi-Fi and sleep on the phone before marking the final checks. Never set a passcode or Touch ID with this method.

The current Mac was used for offline preparation, demo UI checks and workflow tests. Actual execution on older macOS releases and complete GUI-driven restore/maintenance runs still need hardware validation. This build reuses the procedure that worked on the phone during this project.

## Developer build

Sources are in `Sources/`, translations and metadata in `Resources/`. Third-party source archives and the modified restore source are under `Resources/Licenses/SourceArchives/`. `Vendor/bin` contains the development input binaries and their libraries; no Apple firmware or per-phone ticket is included.

Run `bash Scripts/build.sh` with Xcode/Command Line Tools and Python 3 on the development Mac. This compiles the Swift GUI and file-preparation engine, bundles the native tools, rewrites their dylib dependencies to relative paths, verifies deployment targets ≤14, and signs locally. Development requirements are not runtime requirements. Set `SIGN_IDENTITY` to a Developer ID identity when available, then notarize the final release separately.

`Scripts/build-portable-restore.py` links the verified restore source against the kit libraries and a static libzip built with `CMAKE_OSX_DEPLOYMENT_TARGET=14.0`, `BUILD_SHARED_LIBS=OFF`, `ENABLE_LZMA=OFF`, `ENABLE_ZSTD=OFF` and crypto backends disabled. Inputs and full build notes are documented in `Resources/Licenses/BUILD-NOTES.md`.

Tests: compile `Domain.swift`, `AssistantModel.swift`, `MaintenanceModel.swift` and `Tests/WorkflowTests.swift` together, then pass the Resources directory to the resulting executable. The integration test prepares original IPSWs entirely on the Mac; it never opens a USB device.

Interface/engine license: GPL-3.0-or-later. Third-party code retains its original licenses.
