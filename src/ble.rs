use std::ffi::CStr;
use std::os::raw::c_char;

unsafe extern "C" {
    fn ble_peripheral_start(http_port: u16);
    fn ble_peripheral_stop();
    fn ble_get_connected_devices() -> *const c_char;
    fn ble_free_string(ptr: *const c_char);
    fn ble_notify_change();
}

pub fn start(port: u16) {
    println!("Starting BLE peripheral (proxying to localhost:{port})");
    unsafe { ble_peripheral_start(port); }
}

pub fn stop() {
    unsafe { ble_peripheral_stop(); }
}

pub fn connected_devices_json() -> String {
    unsafe {
        let ptr = ble_get_connected_devices();
        if ptr.is_null() {
            return "[]".to_string();
        }
        let s = CStr::from_ptr(ptr).to_str().unwrap_or("[]").to_string();
        ble_free_string(ptr);
        s
    }
}

/// Push a lightweight "data changed" bump to every subscribed BLE central so
/// they resync immediately. No-op when the `ble` feature isn't compiled in.
pub fn notify_change() {
    unsafe { ble_notify_change(); }
}
