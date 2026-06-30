use std::env;
use std::fs;
use std::path::Path;

fn main() {
    // Embeber todos los Scripts/*.ps1 dentro del binario
    let manifest = env::var("CARGO_MANIFEST_DIR").unwrap();
    let scripts_dir = Path::new(&manifest).join("..").join("..").join("Scripts");
    let out_dir = env::var("OUT_DIR").unwrap();
    let dest = Path::new(&out_dir).join("scripts_embed.rs");

    let mut code = String::from("pub static SCRIPTS_EMBED: &[(&str, &str)] = &[\n");
    if let Ok(entries) = fs::read_dir(&scripts_dir) {
        let mut files: Vec<_> = entries
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.extension().map(|x| x == "ps1").unwrap_or(false))
            .collect();
        files.sort();
        for p in files {
            let name = p.file_name().unwrap().to_string_lossy().to_string();
            let abs = p.to_string_lossy().replace('\\', "\\\\");
            code.push_str(&format!("    (\"{}\", include_str!(\"{}\")),\n", name, abs));
            println!("cargo:rerun-if-changed={}", p.to_string_lossy());
        }
    }
    code.push_str("];\n");
    fs::write(&dest, code).unwrap();
    println!("cargo:rerun-if-changed=../../Scripts");

    tauri_build::build()
}
