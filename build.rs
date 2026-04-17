fn main() {
    prost_build::compile_protos(&["proto/time_logging.proto"], &["proto/"]).unwrap();

    #[cfg(feature = "ble")]
    {
        cc::Build::new()
            .file("src/ble_peripheral.m")
            .flag("-fobjc-arc")
            .compile("ble_peripheral");
        println!("cargo:rustc-link-lib=framework=CoreBluetooth");
        println!("cargo:rustc-link-lib=framework=Foundation");
    }

    #[cfg(feature = "icloud")]
    {
        cc::Build::new()
            .file("src/icloud_sync.m")
            .flag("-fobjc-arc")
            .compile("icloud_sync");
        println!("cargo:rustc-link-lib=framework=CloudKit");
        println!("cargo:rustc-link-lib=framework=Foundation");
    }
}
