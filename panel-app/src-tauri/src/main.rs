#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::fs;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::Path;
use std::process::Command;
use std::time::Duration;
#[cfg(windows)]
use std::os::windows::process::CommandExt;

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x08000000;

// Scripts embebidos en el .exe (generado por build.rs)
include!(concat!(env!("OUT_DIR"), "/scripts_embed.rs"));

fn nuevo_powershell() -> Command {
    let mut cmd = Command::new("PowerShell.exe");
    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);
    cmd
}

// Crea la estructura de carpetas y extrae los scripts si hace falta.
// Asi el .exe funciona solo, desde una carpeta vacia.
fn asegurar_estructura() {
    let base = ruta_base_interna();
    for d in ["Scripts", "Estado", "Instancia", "Registros", "Configuracion"] {
        let _ = fs::create_dir_all(format!("{}\\{}", base, d));
    }
    // Extraer/actualizar scripts cuando cambia la version del programa
    let ver = env!("CARGO_PKG_VERSION");
    let marker = format!("{}\\Estado\\scripts_version.txt", base);
    let actual = fs::read_to_string(&marker).unwrap_or_default();
    if actual.trim() != ver {
        for (name, content) in SCRIPTS_EMBED {
            let _ = fs::write(format!("{}\\Scripts\\{}", base, name), content);
        }
        let _ = fs::write(&marker, ver);
    }
    // Estado inicial
    let est = format!("{}\\Estado\\estado.json", base);
    if !Path::new(&est).exists() {
        let _ = fs::write(&est, "{\"servidor_activo\":false,\"pid_java\":null,\"inicio_sesion\":null,\"ultimo_backup\":null,\"ultima_sincronizacion\":null,\"version_mundo_local\":null,\"turno_actual\":null,\"ultimo_evento\":\"Instalado\",\"ultimo_evento_tiempo\":null}");
    }
    let lock = format!("{}\\Estado\\servidor.lock", base);
    if !Path::new(&lock).exists() {
        let _ = fs::write(&lock, "");
    }
}

// Directorio donde esta el .exe = raiz del proyecto (portable)
fn ruta_base_interna() -> String {
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            return dir.to_string_lossy().to_string();
        }
    }
    "C:\\ServidorTecnico".to_string()
}

#[tauri::command]
fn ruta_base() -> String {
    ruta_base_interna()
}

// Carpeta de configuracion del usuario (fuera del programa = portable)
#[tauri::command]
fn ruta_appdata() -> String {
    if let Ok(appdata) = std::env::var("APPDATA") {
        let dir = format!("{}\\Skeledex", appdata);
        let _ = fs::create_dir_all(&dir);
        return dir;
    }
    format!("{}\\Configuracion", ruta_base_interna())
}

// ---------- Archivos ----------
#[tauri::command]
fn leer_archivo(path: String) -> String {
    let contenido = fs::read_to_string(&path).unwrap_or_default();
    contenido.trim_start_matches('\u{feff}').to_string()
}

#[tauri::command]
fn escribir_archivo(path: String, contenido: String) -> bool {
    fs::write(&path, contenido).is_ok()
}

#[tauri::command]
fn escribir_debug(texto: String) {
    let ruta = format!("{}\\Estado\\panel_debug.log", ruta_base_interna());
    if let Ok(mut f) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&ruta)
    {
        let _ = writeln!(f, "{}", texto);
    }
}

// ---------- Proceso (nativo, sin PowerShell) ----------
// Devuelve JSON: {"vivo":bool,"ram_mb":u64}
#[tauri::command]
fn estado_proceso(pid: u32) -> String {
    use sysinfo::{Pid, ProcessesToUpdate, System};
    let mut sys = System::new();
    let p = Pid::from_u32(pid);
    sys.refresh_processes(ProcessesToUpdate::Some(&[p]), true);
    if let Some(proc_) = sys.process(p) {
        let ram_mb = proc_.memory() / 1024 / 1024; // bytes -> MB
        format!("{{\"vivo\":true,\"ram_mb\":{}}}", ram_mb)
    } else {
        "{\"vivo\":false,\"ram_mb\":0}".to_string()
    }
}

// ---------- Salud (nativo) ----------
#[tauri::command]
fn info_salud(ruta_base: String) -> String {
    use sysinfo::Disks;
    // Disco
    let mut disco_gb: f64 = -1.0;
    let disks = Disks::new_with_refreshed_list();
    let unidad = ruta_base.chars().next().unwrap_or('C').to_ascii_uppercase();
    for d in disks.list() {
        let mp = d.mount_point().to_string_lossy().to_uppercase();
        if mp.starts_with(&format!("{}:", unidad)) {
            disco_gb = (d.available_space() as f64) / 1_073_741_824.0;
            break;
        }
    }
    if disco_gb < 0.0 {
        if let Some(d) = disks.list().first() {
            disco_gb = (d.available_space() as f64) / 1_073_741_824.0;
        }
    }
    // Internet: intentar conectar a 1.1.1.1:53
    let net = match TcpStream::connect_timeout(
        &"1.1.1.1:53".parse().unwrap(),
        Duration::from_millis(1500),
    ) {
        Ok(_) => "ok",
        Err(_) => "fail",
    };
    format!(
        "{{\"disco_gb\":{:.1},\"internet\":\"{}\"}}",
        disco_gb.max(0.0),
        net
    )
}

// ---------- RCON nativo (protocolo Source) ----------
fn rcon_paquete(id: i32, tipo: i32, cuerpo: &str) -> Vec<u8> {
    let body = cuerpo.as_bytes();
    let len = (4 + 4 + body.len() + 2) as i32;
    let mut p = Vec::with_capacity(len as usize + 4);
    p.extend_from_slice(&len.to_le_bytes());
    p.extend_from_slice(&id.to_le_bytes());
    p.extend_from_slice(&tipo.to_le_bytes());
    p.extend_from_slice(body);
    p.push(0);
    p.push(0);
    p
}

fn rcon_interno(host: &str, port: u16, password: &str, comando: &str) -> Result<String, String> {
    let dir = format!("{}:{}", host, port);
    let mut stream = TcpStream::connect_timeout(
        &dir.parse().map_err(|e| format!("addr: {}", e))?,
        Duration::from_millis(2000),
    )
    .map_err(|e| format!("conexion: {}", e))?;
    stream
        .set_read_timeout(Some(Duration::from_millis(2500)))
        .ok();
    stream
        .set_write_timeout(Some(Duration::from_millis(2500)))
        .ok();

    // Login (tipo 3)
    let login = rcon_paquete(1, 3, password);
    stream.write_all(&login).map_err(|e| format!("login write: {}", e))?;
    let (id_login, _, _) = rcon_leer(&mut stream)?;
    if id_login == -1 {
        return Err("password incorrecta".to_string());
    }

    // Comando (tipo 2)
    let cmd = rcon_paquete(2, 2, comando);
    stream.write_all(&cmd).map_err(|e| format!("cmd write: {}", e))?;
    let (_, _, body) = rcon_leer(&mut stream)?;
    Ok(body)
}

fn rcon_leer(stream: &mut TcpStream) -> Result<(i32, i32, String), String> {
    let mut lenbuf = [0u8; 4];
    stream.read_exact(&mut lenbuf).map_err(|e| format!("len: {}", e))?;
    let len = i32::from_le_bytes(lenbuf);
    if len < 10 || len > 8192 {
        return Err(format!("len invalido: {}", len));
    }
    let mut data = vec![0u8; len as usize];
    stream.read_exact(&mut data).map_err(|e| format!("data: {}", e))?;
    let id = i32::from_le_bytes([data[0], data[1], data[2], data[3]]);
    let tipo = i32::from_le_bytes([data[4], data[5], data[6], data[7]]);
    let body = String::from_utf8_lossy(&data[8..data.len() - 2]).to_string();
    Ok((id, tipo, body))
}

#[tauri::command]
fn rcon(host: String, port: u16, password: String, comando: String) -> String {
    match rcon_interno(&host, port, &password, &comando) {
        Ok(r) => {
            if r.is_empty() {
                "[sin respuesta]".to_string()
            } else {
                r
            }
        }
        Err(_) => "[RCON no responde]".to_string(),
    }
}

// ---------- Backups (PowerShell, fuera del loop) ----------
#[tauri::command]
fn listar_backups(ruta_backups: String) -> String {
    let script = format!(
        "$tipos=@('AntesDeIniciar','DespuesDeApagar','Diario','Emergencia','Manual'); $r=@(); foreach($t in $tipos){{ $d=Join-Path '{}' $t; if(Test-Path $d){{ Get-ChildItem $d -Filter *.zip -ErrorAction SilentlyContinue | ForEach-Object {{ $r += [PSCustomObject]@{{ tipo=$t; nombre=$_.Name; mb=[math]::Round($_.Length/1MB,1); fecha=$_.CreationTime.ToString('yyyy-MM-dd HH:mm') }} }} }} }}; $r | Sort-Object fecha -Descending | ConvertTo-Json -Compress",
        ruta_backups
    );
    let output = nuevo_powershell()
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", &script])
        .output();
    match output {
        Ok(o) => {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if s.is_empty() { "[]".to_string() } else { s }
        }
        Err(_) => "[]".to_string(),
    }
}

// ---------- Descargar jar (PowerShell, fuera del loop) ----------
#[tauri::command]
fn descargar_jar(tipo: String, ruta_instancia: String) -> String {
    let script = if tipo == "purpur" {
        format!(
            "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $v=(Invoke-RestMethod 'https://api.purpurmc.org/v2/purpur').versions[-1]; Invoke-WebRequest -Uri \"https://api.purpurmc.org/v2/purpur/$v/latest/download\" -OutFile '{}\\purpur.jar' -UseBasicParsing; \"Purpur $v descargado\"",
            ruta_instancia
        )
    } else {
        format!(
            "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $vs=(Invoke-RestMethod 'https://api.papermc.io/v2/projects/paper').versions; $l=$vs[-1]; $b=((Invoke-RestMethod \"https://api.papermc.io/v2/projects/paper/versions/$l\").builds)[-1]; Invoke-WebRequest -Uri \"https://api.papermc.io/v2/projects/paper/versions/$l/builds/$b/downloads/paper-$l-$b.jar\" -OutFile '{}\\paper.jar' -UseBasicParsing; \"Paper $l build $b descargado\"",
            ruta_instancia
        )
    };
    let output = nuevo_powershell()
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", &script])
        .output();
    match output {
        Ok(o) => {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if s.is_empty() {
                format!("Error: {}", String::from_utf8_lossy(&o.stderr).trim())
            } else {
                s
            }
        }
        Err(e) => format!("Error: {}", e),
    }
}

// ---------- Acciones (iniciar/apagar/reiniciar) ----------
#[tauri::command]
fn abrir_carpeta(ruta: String) {
    Command::new("explorer.exe").arg(&ruta).spawn().ok();
}

#[tauri::command]
fn ejecutar_accion(ruta_scripts: String, accion: String) {
    nuevo_powershell()
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-WindowStyle",
            "Hidden",
            "-File",
            &format!("{}\\_nucleo.ps1", ruta_scripts),
            "-Accion",
            &accion,
        ])
        .spawn()
        .ok();
}

// ---------- PowerShell generico (oculto), devuelve stdout ----------
#[tauri::command]
fn ps_comando(script: String) -> String {
    let output = nuevo_powershell()
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", &script])
        .output();
    match output {
        Ok(o) => {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if s.is_empty() {
                let err = String::from_utf8_lossy(&o.stderr).trim().to_string();
                if err.is_empty() { String::new() } else { format!("ERROR: {}", err) }
            } else {
                s
            }
        }
        Err(e) => format!("ERROR: {}", e),
    }
}

// ---------- PowerShell elevado (UAC) para tareas programadas ----------
#[tauri::command]
fn ps_elevado(script: String) -> bool {
    let arg = format!(
        "Start-Process PowerShell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command','{}'",
        script.replace('\'', "''")
    );
    nuevo_powershell()
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", &arg])
        .spawn()
        .is_ok()
}

// ---------- Reinicio limpio para aplicar el .exe nuevo ----------
#[tauri::command]
fn salir_y_actualizar(app: tauri::AppHandle, ruta_base: String) {
    // Reemplaza el exe actual (cualquier nombre) por el descargado (_update.exe)
    let exe = std::env::current_exe()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| format!("{}\\Skeledex.exe", ruta_base));
    let nuevo = format!("{}\\_update.exe", ruta_base);
    let script = format!(
        "for($i=0;$i -lt 40;$i++){{ Start-Sleep -Milliseconds 700; try{{ Move-Item -LiteralPath '{}' -Destination '{}' -Force -ErrorAction Stop; break }}catch{{}} }}; Start-Process -FilePath '{}'",
        nuevo, exe, exe
    );
    nuevo_powershell()
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", &script])
        .spawn()
        .ok();
    app.exit(0);
}

fn main() {
    asegurar_estructura();
    tauri::Builder::default()
        .setup(|app| {
            use tauri::menu::{Menu, MenuItem};
            use tauri::tray::TrayIconBuilder;
            use tauri::Manager;

            let mostrar = MenuItem::with_id(app, "mostrar", "Mostrar Panel", true, None::<&str>)?;
            let salir = MenuItem::with_id(app, "salir", "Salir", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&mostrar, &salir])?;

            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Skeledex")
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "salir" => {
                        app.exit(0);
                    }
                    "mostrar" => {
                        if let Some(w) = app.get_webview_window("main") {
                            let _ = w.show();
                            let _ = w.set_focus();
                        }
                    }
                    _ => {}
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .invoke_handler(tauri::generate_handler![
            leer_archivo,
            escribir_archivo,
            escribir_debug,
            ruta_base,
            ruta_appdata,
            estado_proceso,
            info_salud,
            rcon,
            listar_backups,
            descargar_jar,
            abrir_carpeta,
            ejecutar_accion,
            ps_comando,
            ps_elevado,
            salir_y_actualizar
        ])
        .run(tauri::generate_context!())
        .expect("error al ejecutar tauri");
}
