#ifndef BLE_PERIPHERAL_H
#define BLE_PERIPHERAL_H

#include <stdint.h>

// Start the BLE peripheral, proxying requests to localhost HTTP on the given port.
void ble_peripheral_start(uint16_t http_port);

// Stop the BLE peripheral and clean up.
void ble_peripheral_stop(void);

// Get connected devices as JSON. Caller must free with ble_free_string.
// Returns: [{"name":"iPhone","connected_at":1234567890}, ...]
const char* ble_get_connected_devices(void);
void ble_free_string(const char *ptr);

#endif
