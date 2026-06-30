# Skeledex — Estado del proyecto

Servidor de Minecraft (Purpur) de alta disponibilidad, compartido entre varios PCs
por turnos, con sincronizacion en la nube, backups automaticos, notificaciones de
Discord y un panel de control de escritorio (Tauri).

## Arquitectura actual

### Configuracion (portable)
- La config vive **fuera** de la carpeta del programa: `%APPDATA%\Skeledex\config.json`.
  Asi la carpeta es portable y cada PC tiene su propia identidad aunque compartan carpeta.
- Resolutor central: `Scripts\_config_path.ps1` (migra una config local antigua automaticamente).
- En el panel: `ruta_appdata` (Rust) + `ARCHIVO_CONFIG` (JS). Migracion al abrir.

### Primer uso (onboarding)
- Si no hay config, el panel muestra una pantalla de bienvenida:
  - **Crear un servidor nuevo** (eres owner). Opcion de preparar el servidor al instante
    (descarga Purpur, acepta EULA, crea server.properties con RCON) via `_primer_servidor.ps1`.
  - **Unirme a un grupo**: pegar codigo de vinculacion + nombre + rol.
- Ya no hay instaladores .bat: solo el `.exe`.

### Roles
- **owner**: control total, configura la nube, publica versiones (developer).
- **operador**: control total del panel, puede meter llaves de la nube, no publica.
- **miembro**: solo prender/apagar; sin acceso a archivos/ajustes.

### Multi-nube
- rclone abstrae el proveedor. Soportados con credenciales: Backblaze B2, Amazon S3,
  Wasabi, Cloudflare R2, Storj. Con OAuth (asistente rclone): Google Drive, Dropbox, OneDrive.
- `Scripts\_nube_conectar.ps1` genera el rclone.conf y auto-instala rclone si falta.
- `Scripts\_nube_info.ps1` reporta uso (% de almacenamiento) en la vista Stats.
- Cada **grupo** usa su propio bucket; el mundo/turnos/backups son privados por grupo.

### Codigo de vinculacion
- `ST1-...` : config del grupo SIN llaves (seguro). El amigo mete la llave aparte.
- `ST2-...` : codigo COMPLETO con llaves (un solo paso). Compartir solo con confianza.
- `_nube_export.ps1` lee las llaves del rclone.conf para el codigo completo.

### Canal central de actualizaciones (developer -> todos)
- El **programa** (scripts + .exe) se distribuye por **GitHub Releases** del developer.
- `config.actualizaciones`: { auto, canal:"github", repo:"usuario/repo" }.
- Consumer: `Scripts\_update_global.ps1` (compara version, descarga el .zip de la release,
  aplica Scripts + deja el .exe nuevo para el proximo arranque). Toggle "Actualizar
  automaticamente" en Ajustes (ON por defecto). El panel revisa al abrir.
- Reinicio limpio del .exe: comando Rust `salir_y_actualizar`.
- Developer publica con `PublicarVersionGlobal.bat` (usa `gh` si esta instalado, si no da pasos).
- Respaldo: tambien existe el canal por-grupo (`_autoupdate.ps1`) como red de seguridad.
- **PENDIENTE**: definir el repo de GitHub y hornearlo en los defaults.

## Panel (Tauri) — vistas
- **Dashboard**: estado, tarjetas (jugadores/TPS/RAM/uptime/backup), salud ampliada
  (disco, internet, servidor, Java, nube, RAM libre), acciones rapidas (dia/noche/clima/
  dificultad/guardar) cuando esta online.
- **Consola**: log en vivo, buscar/copiar/limpiar, **Diagnostico** (analizador de crash).
- **Jugadores**: op/deop/kick/ban/pardon/whitelist, mensaje al chat, reinicio con aviso.
- **Backups**: crear backup ahora, restaurar/abrir cada copia, colores por tipo.
- **Stats**: uso de la nube, historial TPS/RAM (sparklines), tiempo por PC/sesiones.
- **Mundo**: editor de server.properties + MOTD con preview de colores + editor avanzado con buscador + descargar/preparar motor.
- **Plugins**: buscar/instalar/eliminar (Modrinth) + BlueMap (mapa en vivo).
- **Ajustes**: identidad, servidor (RAM con recomendacion), red, Discord (con reporte
  periodico configurable), nube (multi-proveedor), avanzado, actualizaciones, mantenimiento
  (tareas programadas, export/import config, publicar). Buscador de ajustes.
- **Equipo**: rol, codigo de vinculacion (normal y completo), unirse a grupo.
- Extras: 5 temas + color de acento personalizado, i18n ES/EN, centro de notificaciones
  (campana), ayuda de atajos (tecla ?), gestor de instancias/grupo.

## Seguridad / robustez
- Ventanas ocultas: Java, Playit y scripts de fondo corren sin consola; el panel usa CREATE_NO_WINDOW.
- Candado anti-doble-operacion en nucleo (iniciar/apagar/reiniciar).
- Discord avisa OFFLINE apenas se apaga (antes de subir a la nube).
- Solo el owner puede publicar (guard en Publicar-Update).
- Eliminacion de plugins validada dentro de la carpeta plugins.

## Pendientes / ideas futuras
- Repo de GitHub para el canal central (requiere accion del usuario).
- Subir server-icon.png desde el panel (requiere dialogo de archivo nativo).
- Anuncios recurrentes automaticos al chat (cada X min).
- Traduccion EN completa (hoy: chrome principal traducido, base lista para extender).
- Probar el ciclo completo Apagar->Iniciar entre PCs y el onboarding real de un amigo.
