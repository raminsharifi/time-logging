#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

// BLE Service and Characteristic UUIDs — must match iOS app
static NSString *const kServiceUUID = @"7B2C956E-9A32-4E00-9B8D-3C1A5E809F2A";
static NSString *const kRequestCharUUID = @"7B2C956E-9A32-4E00-9B8D-3C1A5E809F2B";
static NSString *const kResponseCharUUID = @"7B2C956E-9A32-4E00-9B8D-3C1A5E809F2C";

// Chunk flags
static const uint8_t CHUNK_FIRST = 0x01;
static const uint8_t CHUNK_LAST = 0x02;
// Server-initiated push event: payload-less marker telling the central that
// something on the Mac changed and it should run a sync.
static const uint8_t CHUNK_EVENT = 0x04;
static const int MAX_CHUNK_PAYLOAD = 500;

// --- BLE Request/Response JSON wrappers ---

@interface BLERequest : NSObject
@property (nonatomic, strong) NSString *method;
@property (nonatomic, strong) NSString *path;
@property (nonatomic, strong) NSString *body; // nullable
+ (instancetype)fromJSON:(NSData *)data;
@end

@implementation BLERequest
+ (instancetype)fromJSON:(NSData *)data {
    NSError *error = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || !dict) return nil;
    BLERequest *req = [[BLERequest alloc] init];
    req.method = dict[@"method"];
    req.path = dict[@"path"];
    req.body = dict[@"body"];
    return req;
}
@end

// --- BLE Peripheral Manager ---

@interface TLBLEPeripheral : NSObject <CBPeripheralManagerDelegate>
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, strong) CBMutableCharacteristic *requestChar;
@property (nonatomic, strong) CBMutableCharacteristic *responseChar;
@property (nonatomic, strong) CBMutableService *service;
@property (nonatomic, assign) uint16_t httpPort;

// Receive buffer for chunked requests
@property (nonatomic, strong) NSMutableData *receiveBuffer;
@property (nonatomic, assign) uint32_t expectedLength;
@property (nonatomic, assign) BOOL isReceiving;

// Subscribed centrals for notifications
@property (nonatomic, strong) NSMutableArray<CBCentral *> *subscribedCentrals;
// Track connected device info
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *connectedDevices;
@end

@implementation TLBLEPeripheral

- (instancetype)initWithPort:(uint16_t)port {
    self = [super init];
    if (self) {
        _httpPort = port;
        _receiveBuffer = [NSMutableData data];
        _subscribedCentrals = [NSMutableArray array];
        _connectedDevices = [NSMutableArray array];
        _isReceiving = NO;

        dispatch_queue_t queue = dispatch_queue_create("com.tl.ble", DISPATCH_QUEUE_SERIAL);
        _peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:queue];
    }
    return self;
}

- (void)setupService {
    // Request characteristic: iPhone writes chunks here
    self.requestChar = [[CBMutableCharacteristic alloc]
        initWithType:[CBUUID UUIDWithString:kRequestCharUUID]
        properties:CBCharacteristicPropertyWrite
        value:nil
        permissions:CBAttributePermissionsWriteable];

    // Response characteristic: Mac sends notifications here
    self.responseChar = [[CBMutableCharacteristic alloc]
        initWithType:[CBUUID UUIDWithString:kResponseCharUUID]
        properties:CBCharacteristicPropertyNotify
        value:nil
        permissions:CBAttributePermissionsReadable];

    self.service = [[CBMutableService alloc]
        initWithType:[CBUUID UUIDWithString:kServiceUUID]
        primary:YES];
    self.service.characteristics = @[self.requestChar, self.responseChar];

    [self.peripheralManager addService:self.service];
}

- (void)startAdvertising {
    [self.peripheralManager startAdvertising:@{
        CBAdvertisementDataServiceUUIDsKey: @[[CBUUID UUIDWithString:kServiceUUID]],
        CBAdvertisementDataLocalNameKey: @"tl-time-logger"
    }];
    NSLog(@"[BLE] Advertising started");
}

// MARK: - CBPeripheralManagerDelegate

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    if (peripheral.state == CBManagerStatePoweredOn) {
        NSLog(@"[BLE] Bluetooth powered on, setting up service");
        [self setupService];
    } else {
        NSLog(@"[BLE] Bluetooth state: %ld", (long)peripheral.state);
    }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
            didAddService:(CBService *)service
                    error:(NSError *)error {
    if (error) {
        NSLog(@"[BLE] Failed to add service: %@", error);
        return;
    }
    NSLog(@"[BLE] Service added, starting advertising");
    [self startAdvertising];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
                  central:(CBCentral *)central
didSubscribeToCharacteristic:(CBCharacteristic *)characteristic {
    NSLog(@"[BLE] Central subscribed to response characteristic");
    if (![self.subscribedCentrals containsObject:central]) {
        [self.subscribedCentrals addObject:central];
    }
    // Track device
    NSString *identifier = central.identifier.UUIDString;
    BOOL found = NO;
    for (NSDictionary *d in self.connectedDevices) {
        if ([d[@"identifier"] isEqualToString:identifier]) { found = YES; break; }
    }
    if (!found) {
        [self.connectedDevices addObject:@{
            @"identifier": identifier,
            @"name": @"iPhone",
            @"connected_at": @((long)[[NSDate date] timeIntervalSince1970])
        }];
    }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
                  central:(CBCentral *)central
didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic {
    [self.subscribedCentrals removeObject:central];
    NSString *identifier = central.identifier.UUIDString;
    NSMutableArray *toRemove = [NSMutableArray array];
    for (NSDictionary *d in self.connectedDevices) {
        if ([d[@"identifier"] isEqualToString:identifier]) [toRemove addObject:d];
    }
    [self.connectedDevices removeObjectsInArray:toRemove];
    NSLog(@"[BLE] Central unsubscribed");
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
    didReceiveWriteRequests:(NSArray<CBATTRequest *> *)requests {

    for (CBATTRequest *request in requests) {
        if ([request.characteristic.UUID isEqual:[CBUUID UUIDWithString:kRequestCharUUID]]) {
            NSData *data = request.value;
            if (data.length < 1) {
                [peripheral respondToRequest:request withResult:CBATTErrorInvalidAttributeValueLength];
                continue;
            }

            uint8_t flags;
            [data getBytes:&flags length:1];
            NSData *payload = [data subdataWithRange:NSMakeRange(1, data.length - 1)];

            if (flags & CHUNK_FIRST) {
                // First chunk: read 4-byte length, start receiving
                if (payload.length < 4) {
                    [peripheral respondToRequest:request withResult:CBATTErrorInvalidAttributeValueLength];
                    continue;
                }
                uint32_t length;
                [payload getBytes:&length length:4];
                self.expectedLength = CFSwapInt32BigToHost(length);
                self.receiveBuffer = [NSMutableData data];
                [self.receiveBuffer appendData:[payload subdataWithRange:NSMakeRange(4, payload.length - 4)]];
                self.isReceiving = YES;
            } else if (self.isReceiving) {
                [self.receiveBuffer appendData:payload];
            }

            [peripheral respondToRequest:request withResult:CBATTErrorSuccess];

            if ((flags & CHUNK_LAST) && self.isReceiving) {
                self.isReceiving = NO;
                NSData *completeRequest = [self.receiveBuffer copy];
                self.receiveBuffer = [NSMutableData data];

                // Process the request asynchronously
                [self processRequest:completeRequest];
            }
        } else {
            [peripheral respondToRequest:request withResult:CBATTErrorAttributeNotFound];
        }
    }
}

// MARK: - Request Processing

- (void)processRequest:(NSData *)requestData {
    BLERequest *bleReq = [BLERequest fromJSON:requestData];
    if (!bleReq) {
        NSLog(@"[BLE] Failed to parse request JSON");
        [self sendErrorResponse:@"Invalid request JSON"];
        return;
    }

    // Build URL
    NSString *urlString = [NSString stringWithFormat:@"http://127.0.0.1:%d%@", self.httpPort, bleReq.path];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self sendErrorResponse:@"Invalid path"];
        return;
    }

    NSMutableURLRequest *httpReq = [NSMutableURLRequest requestWithURL:url];
    httpReq.HTTPMethod = bleReq.method;
    httpReq.timeoutInterval = 5;
    [httpReq setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    if (bleReq.body) {
        httpReq.HTTPBody = [bleReq.body dataUsingEncoding:NSUTF8StringEncoding];
    }

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:httpReq
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"[BLE] HTTP request error: %@", error);
                [self sendErrorResponse:error.localizedDescription];
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSString *bodyStr = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
            if (!bodyStr) bodyStr = @"{}";

            // Wrap in BLE response
            NSDictionary *responseDict = @{
                @"status": @(httpResponse.statusCode),
                @"body": bodyStr
            };
            NSData *responseJSON = [NSJSONSerialization dataWithJSONObject:responseDict options:0 error:nil];
            if (responseJSON) {
                [self sendResponseData:responseJSON];
            }
        }];
    [task resume];
}

- (void)sendErrorResponse:(NSString *)message {
    NSDictionary *dict = @{@"status": @(500), @"body": [NSString stringWithFormat:@"{\"error\":\"%@\"}", message]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (data) {
        [self sendResponseData:data];
    }
}

- (void)sendResponseData:(NSData *)data {
    // Chunk the response and send as notifications
    NSMutableData *fullData = [NSMutableData data];
    uint32_t length = CFSwapInt32HostToBig((uint32_t)data.length);
    [fullData appendBytes:&length length:4];
    [fullData appendData:data];

    // Compute per-send chunk size from negotiated MTU. Use the smallest
    // maximumUpdateValueLength across currently-subscribed centrals and reserve
    // 1 byte for the flag byte. Clamp to a safe floor (BLE 4.0 min ATT_MTU=23,
    // so default payload is 20 bytes minus 1 for the flag = 19).
    NSUInteger mtuPayload = MAX_CHUNK_PAYLOAD;
    for (CBCentral *c in self.subscribedCentrals) {
        NSUInteger cap = c.maximumUpdateValueLength;
        if (cap > 0 && cap < mtuPayload + 1) mtuPayload = cap - 1;
    }
    if (mtuPayload < 19) mtuPayload = 19;

    NSUInteger totalChunks = (fullData.length + mtuPayload - 1) / mtuPayload;

    for (NSUInteger i = 0; i < totalChunks; i++) {
        NSUInteger start = i * mtuPayload;
        NSUInteger len = MIN(mtuPayload, fullData.length - start);
        NSData *payload = [fullData subdataWithRange:NSMakeRange(start, len)];

        uint8_t flags = 0;
        if (i == 0) flags |= CHUNK_FIRST;
        if (i == totalChunks - 1) flags |= CHUNK_LAST;

        NSMutableData *chunk = [NSMutableData dataWithBytes:&flags length:1];
        [chunk appendData:payload];

        BOOL sent = [self.peripheralManager updateValue:chunk
                                      forCharacteristic:self.responseChar
                                   onSubscribedCentrals:self.subscribedCentrals.count > 0 ? self.subscribedCentrals : nil];
        if (!sent) {
            // Queue is full — wait for peripheralManagerIsReadyToUpdateSubscribers callback
            // For simplicity, retry after a short delay
            [NSThread sleepForTimeInterval:0.01];
            [self.peripheralManager updateValue:chunk
                              forCharacteristic:self.responseChar
                           onSubscribedCentrals:nil];
        }
    }
}

- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral {
    // Called when the transmit queue has space again
}

- (void)stop {
    [self.peripheralManager stopAdvertising];
    [self.peripheralManager removeAllServices];
    NSLog(@"[BLE] Peripheral stopped");
}

- (void)notifyChange {
    if (self.subscribedCentrals.count == 0) return;
    uint8_t flags = CHUNK_EVENT;
    NSData *chunk = [NSData dataWithBytes:&flags length:1];
    [self.peripheralManager updateValue:chunk
                      forCharacteristic:self.responseChar
                   onSubscribedCentrals:self.subscribedCentrals];
}

@end

// --- C API ---

static TLBLEPeripheral *g_peripheral = nil;

void ble_peripheral_start(uint16_t http_port) {
    @autoreleasepool {
        NSLog(@"[BLE] Starting peripheral, proxying to localhost:%d", http_port);
        g_peripheral = [[TLBLEPeripheral alloc] initWithPort:http_port];
    }
}

void ble_peripheral_stop(void) {
    @autoreleasepool {
        if (g_peripheral) {
            [g_peripheral stop];
            g_peripheral = nil;
        }
    }
}

const char* ble_get_connected_devices(void) {
    @autoreleasepool {
        if (!g_peripheral) return strdup("[]");
        NSData *json = [NSJSONSerialization dataWithJSONObject:g_peripheral.connectedDevices options:0 error:nil];
        if (!json) return strdup("[]");
        char *str = (char *)malloc(json.length + 1);
        memcpy(str, json.bytes, json.length);
        str[json.length] = '\0';
        return str;
    }
}

void ble_free_string(const char *ptr) {
    if (ptr) free((void *)ptr);
}

void ble_notify_change(void) {
    @autoreleasepool {
        if (g_peripheral) {
            [g_peripheral notifyChange];
        }
    }
}
