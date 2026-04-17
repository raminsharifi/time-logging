#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

static NSString *const kContainerID = @"iCloud.com.raminsharifi.TimeLogger";
static NSString *const kZoneName = @"TimeLoggerZone";

static CKContainer *g_container = nil;
static CKDatabase *g_database = nil;
static CKRecordZoneID *g_zoneID = nil;
static CKServerChangeToken *g_changeToken = nil;
static BOOL g_available = NO;

// Load/save change token to disk
static NSString* tokenPath(void) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    dir = [dir stringByAppendingPathComponent:@"time-logging"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"ck_token"];
}

static void loadToken(void) {
    NSData *data = [NSData dataWithContentsOfFile:tokenPath()];
    if (data) {
        g_changeToken = [NSKeyedUnarchiver unarchivedObjectOfClass:[CKServerChangeToken class] fromData:data error:nil];
    }
}

static void saveToken(void) {
    if (g_changeToken) {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:g_changeToken requiringSecureCoding:YES error:nil];
        [data writeToFile:tokenPath() atomically:YES];
    }
}

// Run async CloudKit operation synchronously using a semaphore
static void waitForBlock(void (^block)(dispatch_semaphore_t sem)) {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    block(sem);
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

int icloud_init(void) {
    @autoreleasepool {
        g_container = [CKContainer containerWithIdentifier:kContainerID];
        g_database = g_container.privateCloudDatabase;
        g_zoneID = [[CKRecordZoneID alloc] initWithZoneName:kZoneName ownerName:CKCurrentUserDefaultName];

        loadToken();

        // Check account status
        __block BOOL available = NO;
        waitForBlock(^(dispatch_semaphore_t sem) {
            [g_container accountStatusWithCompletionHandler:^(CKAccountStatus status, NSError *error) {
                available = (status == CKAccountStatusAvailable);
                dispatch_semaphore_signal(sem);
            }];
        });

        if (!available) {
            NSLog(@"[iCloud] Account not available");
            g_available = NO;
            return 0;
        }

        // Ensure zone exists
        CKRecordZone *zone = [[CKRecordZone alloc] initWithZoneID:g_zoneID];
        CKModifyRecordZonesOperation *op = [[CKModifyRecordZonesOperation alloc]
            initWithRecordZonesToSave:@[zone]
            recordZoneIDsToDelete:nil];

        waitForBlock(^(dispatch_semaphore_t sem) {
            op.modifyRecordZonesCompletionBlock = ^(NSArray *saved, NSArray *deleted, NSError *error) {
                if (error) NSLog(@"[iCloud] Zone error: %@", error);
                dispatch_semaphore_signal(sem);
            };
            [g_database addOperation:op];
        });

        g_available = YES;
        NSLog(@"[iCloud] Initialized successfully");
        return 1;
    }
}

// MARK: - Push Records

void icloud_push(const char *records_json) {
    if (!g_available || !records_json) return;
    @autoreleasepool {
        NSData *data = [NSData dataWithBytes:records_json length:strlen(records_json)];
        NSArray *items = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (!items) return;

        NSMutableArray<CKRecord *> *records = [NSMutableArray array];
        for (NSDictionary *item in items) {
            NSString *type = item[@"type"];
            NSNumber *serverId = item[@"id"];
            NSDictionary *fields = item[@"fields"];
            if (!type || !serverId || !fields) continue;

            NSString *recordName = [NSString stringWithFormat:@"%@-%@",
                [type isEqualToString:@"ActiveTimer"] ? @"Timer" :
                [type isEqualToString:@"TimeEntry"] ? @"Entry" : @"Todo",
                serverId];

            CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:recordName zoneID:g_zoneID];
            CKRecord *record = [[CKRecord alloc] initWithRecordType:type recordID:recordID];

            for (NSString *key in fields) {
                record[key] = fields[key];
            }
            [records addObject:record];
        }

        if (records.count == 0) return;

        CKModifyRecordsOperation *op = [[CKModifyRecordsOperation alloc]
            initWithRecordsToSave:records recordIDsToDelete:nil];
        op.savePolicy = CKRecordSaveIfServerRecordUnchanged;

        waitForBlock(^(dispatch_semaphore_t sem) {
            op.modifyRecordsCompletionBlock = ^(NSArray *saved, NSArray *deleted, NSError *error) {
                if (error) NSLog(@"[iCloud] Push batch error: %@", error);
                dispatch_semaphore_signal(sem);
            };
            [g_database addOperation:op];
        });
    }
}

// MARK: - Delete Records

void icloud_delete(const char *deletions_json) {
    if (!g_available || !deletions_json) return;
    @autoreleasepool {
        NSData *data = [NSData dataWithBytes:deletions_json length:strlen(deletions_json)];
        NSArray *items = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (!items) return;

        NSMutableArray<CKRecordID *> *recordIDs = [NSMutableArray array];
        for (NSDictionary *item in items) {
            NSString *type = item[@"type"];
            NSNumber *recordId = item[@"id"];
            if (!type || !recordId) continue;

            NSString *prefix = [type isEqualToString:@"ActiveTimer"] ? @"Timer" :
                               [type isEqualToString:@"TimeEntry"] ? @"Entry" : @"Todo";
            NSString *recordName = [NSString stringWithFormat:@"%@-%@", prefix, recordId];
            [recordIDs addObject:[[CKRecordID alloc] initWithRecordName:recordName zoneID:g_zoneID]];
        }

        if (recordIDs.count == 0) return;

        CKModifyRecordsOperation *op = [[CKModifyRecordsOperation alloc]
            initWithRecordsToSave:nil recordIDsToDelete:recordIDs];

        waitForBlock(^(dispatch_semaphore_t sem) {
            op.modifyRecordsCompletionBlock = ^(NSArray *saved, NSArray *deleted, NSError *error) {
                if (error) NSLog(@"[iCloud] Delete error: %@", error);
                dispatch_semaphore_signal(sem);
            };
            [g_database addOperation:op];
        });
    }
}

// MARK: - Fetch Changes

const char* icloud_fetch_changes(void) {
    if (!g_available) return strdup("{\"timers\":[],\"entries\":[],\"todos\":[],\"deletions\":[]}");

    __block NSMutableArray *timers = [NSMutableArray array];
    __block NSMutableArray *entries = [NSMutableArray array];
    __block NSMutableArray *todos = [NSMutableArray array];
    __block NSMutableArray *deletions = [NSMutableArray array];

    @autoreleasepool {
        CKFetchRecordZoneChangesConfiguration *config =
            [[CKFetchRecordZoneChangesConfiguration alloc] init];
        config.previousServerChangeToken = g_changeToken;

        CKFetchRecordZoneChangesOperation *op =
            [[CKFetchRecordZoneChangesOperation alloc] initWithRecordZoneIDs:@[g_zoneID]
                configurationsByRecordZoneID:@{g_zoneID: config}];

        op.recordWasChangedBlock = ^(CKRecordID *recordID, CKRecord *record, NSError *error) {
            if (error || !record) return;
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            for (NSString *key in record.allKeys) {
                id val = record[key];
                if (val) dict[key] = val;
            }
            dict[@"_recordName"] = record.recordID.recordName;

            if ([record.recordType isEqualToString:@"ActiveTimer"]) {
                [timers addObject:dict];
            } else if ([record.recordType isEqualToString:@"TimeEntry"]) {
                [entries addObject:dict];
            } else if ([record.recordType isEqualToString:@"TodoItem"]) {
                [todos addObject:dict];
            }
        };

        op.recordWithIDWasDeletedBlock = ^(CKRecordID *recordID, NSString *type) {
            [deletions addObject:@{@"recordName": recordID.recordName, @"type": type ?: @""}];
        };

        op.recordZoneChangeTokensUpdatedBlock = ^(CKRecordZoneID *zoneID, CKServerChangeToken *token, NSData *data) {
            if (token) g_changeToken = token;
        };

        op.recordZoneFetchCompletionBlock = ^(CKRecordZoneID *zoneID, CKServerChangeToken *token, NSData *data, BOOL more, NSError *error) {
            if (token) {
                g_changeToken = token;
                saveToken();
            }
        };

        waitForBlock(^(dispatch_semaphore_t sem) {
            op.fetchRecordZoneChangesCompletionBlock = ^(NSError *error) {
                if (error) NSLog(@"[iCloud] Fetch error: %@", error);
                dispatch_semaphore_signal(sem);
            };
            [g_database addOperation:op];
        });
    }

    // Build JSON result
    NSDictionary *result = @{
        @"timers": timers,
        @"entries": entries,
        @"todos": todos,
        @"deletions": deletions
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    if (!jsonData) return strdup("{}");

    char *str = (char *)malloc(jsonData.length + 1);
    memcpy(str, jsonData.bytes, jsonData.length);
    str[jsonData.length] = '\0';
    return str;
}

void icloud_free(const char *ptr) {
    if (ptr) free((void *)ptr);
}
