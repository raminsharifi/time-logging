fn main() {
    prost_build::compile_protos(&["proto/time_logging.proto"], &["proto/"]).unwrap();

    #[cfg(all(feature = "ble", target_os = "macos"))]
    {
        cc::Build::new()
            .file("src/ble_peripheral.m")
            .flag("-fobjc-arc")
            .compile("ble_peripheral");
        println!("cargo:rustc-link-lib=framework=CoreBluetooth");
        println!("cargo:rustc-link-lib=framework=Foundation");
    }

    #[cfg(all(feature = "icloud", target_os = "macos"))]
    {
        cc::Build::new()
            .file("src/icloud_sync.m")
            .flag("-fobjc-arc")
            .compile("icloud_sync");
        println!("cargo:rustc-link-lib=framework=CloudKit");
        println!("cargo:rustc-link-lib=framework=Foundation");
    }

    // On macOS, embed an Info.plist into the `tl` binary so CoreBluetooth,
    // mDNS and other privacy-gated APIs can read NSBluetoothAlwaysUsageDescription
    // etc. Without this, macOS kills the process on the first CBPeripheralManager
    // call with no visible error.
    #[cfg(target_os = "macos")]
    {
        let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        let plist_path = format!("{}/macos/tl-info.plist", manifest_dir);
        if std::path::Path::new(&plist_path).exists() {
            println!("cargo:rerun-if-changed={}", plist_path);
            println!(
                "cargo:rustc-link-arg=-Wl,-sectcreate,__TEXT,__info_plist,{}",
                plist_path
            );
        }
    }
}
