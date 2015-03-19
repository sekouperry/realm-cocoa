////////////////////////////////////////////////////////////////////////////
//
// Copyright 2015 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#import "RLMTestCase.h"
#import "RLMPredicateUtil.h"

@interface KVOTests : RLMTestCase
@end

struct KVOHelper {
    id observer;
    id obj;
    NSString *keyPath;
    void (^block)(NSString *, id, NSDictionary *);

    KVOHelper(id observer, id obj, NSString *keyPath, void (^block)(NSString *, id, NSDictionary *))
    : observer(observer), obj(obj), keyPath(keyPath), block(block)
    {
        [obj addObserver:observer forKeyPath:keyPath options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:this];
    }
    ~KVOHelper() {
        [obj removeObserver:observer forKeyPath:keyPath context:this];
    }
};

@implementation KVOTests
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    static_cast<KVOHelper *>(context)->block(keyPath, object, change);
}

- (void)testSameObject {
    RLMRealm *realm = RLMRealm.defaultRealm;
    [realm beginWriteTransaction];

    IntObject *obj1 = [IntObject createInDefaultRealmWithObject:@[@5]];

    __block bool called = false;
    auto h = KVOHelper(self, obj1, @"intCol", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"intCol");
        XCTAssertEqualObjects(obj, obj1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @5);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @10);
        called = true;
    });
    obj1.intCol = 10;
    XCTAssertTrue(called);
    
    [realm commitWriteTransaction];
}

- (void)testOtherObject {
    RLMRealm *realm = RLMRealm.defaultRealm;
    [realm beginWriteTransaction];

    IntObject *obj1 = [IntObject createInDefaultRealmWithObject:@[@5]];
    IntObject *obj2 = [IntObject allObjects].firstObject;

    __block bool called = false;
    auto h = KVOHelper(self, obj2, @"intCol", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"intCol");
        XCTAssertEqualObjects(obj, obj2);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @5);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @10);
        called = true;
    });
    obj1.intCol = 10;
    XCTAssertTrue(called);
    
    [realm commitWriteTransaction];
}

- (void)testRefresh {
    RLMRealm *realm = RLMRealm.defaultRealm;
    [realm beginWriteTransaction];

    IntObject *obj1 = [IntObject createInDefaultRealmWithObject:@[@5]];
    [realm commitWriteTransaction];

    __block bool called = false;
    auto h = KVOHelper(self, obj1, @"intCol", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"intCol");
        XCTAssertEqualObjects(obj, obj1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @5);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @10);
        called = true;
    });

    dispatch_queue_t queue = dispatch_queue_create("queue", 0);
    dispatch_async(queue, ^{
        IntObject *obj2 = [IntObject allObjects].firstObject;
        [obj2.realm transactionWithBlock:^{
            obj2.intCol = 10;
        }];
    });
    dispatch_sync(queue, ^{});

    XCTAssertFalse(called);
    [realm refresh];
    XCTAssertTrue(called);
}

- (void)testOnlyCorrectProperty {
    RLMRealm *realm = RLMRealm.defaultRealm;
    [realm beginWriteTransaction];

    AllIntSizesObject *obj1 = [AllIntSizesObject createInDefaultRealmWithObject:@[@1, @2, @3]];

    auto h1 = KVOHelper(self, obj1, @"int16", ^(NSString *, id, NSDictionary *) {
        XCTFail(@"int16 modified");
    });

    __block bool called = false;
    auto h = KVOHelper(self, obj1, @"int32", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"int32");
        XCTAssertEqualObjects(obj, obj1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @2);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @4);
        called = true;
    });

    obj1.int32 = 4;
    XCTAssertTrue(called);
    [realm commitWriteTransaction];

    called = false;
    dispatch_queue_t queue = dispatch_queue_create("queue", 0);
    dispatch_async(queue, ^{
        AllIntSizesObject *obj2 = [AllIntSizesObject allObjects].firstObject;
        [obj2.realm transactionWithBlock:^{
            obj2.int64 = 6;
        }];
    });
    dispatch_sync(queue, ^{});

    XCTAssertFalse(called);
    [realm refresh];
    XCTAssertFalse(called);
}

- (void)testMultipleProperties {
    RLMRealm *realm = RLMRealm.defaultRealm;
    [realm beginWriteTransaction];

    AllIntSizesObject *obj1 = [AllIntSizesObject createInDefaultRealmWithObject:@[@1, @2, @3]];

    __block bool called1 = false;
    auto h1 = KVOHelper(self, obj1, @"int16", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"int16");
        XCTAssertEqualObjects(obj, obj1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @2);
        called1 = true;
    });

    __block bool called2 = false;
    auto h2 = KVOHelper(self, obj1, @"int32", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"int32");
        XCTAssertEqualObjects(obj, obj1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @2);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @4);
        called2 = true;
    });

    __block bool called3 = false;
    auto h3 = KVOHelper(self, obj1, @"int64", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"int64");
        XCTAssertEqualObjects(obj, obj1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @3);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @6);
        called3 = true;
    });

    obj1.int16 = 2;
    XCTAssertTrue(called1);
    obj1.int32 = 4;
    XCTAssertTrue(called2);
    obj1.int64 = 6;
    XCTAssertTrue(called3);
    [realm commitWriteTransaction];
}

- (void)testMultiplePropertiesRefresh {
    RLMRealm *realm = RLMRealm.defaultRealm;
    [realm beginWriteTransaction];

    AllIntSizesObject *obj1 = [AllIntSizesObject createInDefaultRealmWithObject:@[@1, @2, @3]];
    [realm commitWriteTransaction];

    __block bool called1 = false;
    auto h1 = KVOHelper(self, obj1, @"int16", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"int16");
        XCTAssertEqualObjects(obj, obj1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @2);
        called1 = true;
    });

    __block bool called2 = false;
    auto h2 = KVOHelper(self, obj1, @"int32", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"int32");
        XCTAssertEqualObjects(obj, obj1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @2);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @4);
        called2 = true;
    });

    __block bool called3 = false;
    auto h3 = KVOHelper(self, obj1, @"int64", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"int64");
        XCTAssertEqualObjects(obj, obj1);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @3);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @6);
        called3 = true;
    });

    dispatch_queue_t queue = dispatch_queue_create("queue", 0);
    dispatch_async(queue, ^{
        AllIntSizesObject *obj2 = [AllIntSizesObject allObjects].firstObject;
        [obj2.realm transactionWithBlock:^{
            obj2.int16 = 2;
        }];
    });
    dispatch_sync(queue, ^{});
    [realm refresh];
    XCTAssertTrue(called1);

    XCTAssertFalse(called2);
    dispatch_async(queue, ^{
        AllIntSizesObject *obj2 = [AllIntSizesObject allObjects].firstObject;
        [obj2.realm transactionWithBlock:^{
            obj2.int32 = 4;
        }];
    });
    dispatch_sync(queue, ^{});
    [realm refresh];
    XCTAssertTrue(called2);

    XCTAssertFalse(called3);
    dispatch_async(queue, ^{
        AllIntSizesObject *obj2 = [AllIntSizesObject allObjects].firstObject;
        [obj2.realm transactionWithBlock:^{
            obj2.int64 = 6;
        }];
    });
    dispatch_sync(queue, ^{});
    [realm refresh];
    XCTAssertTrue(called3);
}

- (void)testUnrelatedObjects {
    RLMRealm *realm = RLMRealm.defaultRealm;
    [realm beginWriteTransaction];

    AllIntSizesObject *obj1 = [AllIntSizesObject createInDefaultRealmWithObject:@[@1, @2, @3]];
    AllIntSizesObject *obj2 = [AllIntSizesObject createInDefaultRealmWithObject:@[@1, @2, @3]];

    auto h1 = KVOHelper(self, obj1, @"int16", ^(NSString *, id, NSDictionary *) {
        XCTFail(@"obj1 modified");
    });
    auto h2 = KVOHelper(self, obj1, @"int32", ^(NSString *, id, NSDictionary *) {
        XCTFail(@"obj1 modified");
    });
    __block bool called = false;
    auto h3 = KVOHelper(self, obj2, @"int32", ^(NSString *keyPath, id obj, NSDictionary *changeDictionary) {
        XCTAssertEqualObjects(keyPath, @"int32");
        XCTAssertEqualObjects(obj, obj2);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeOldKey], @2);
        XCTAssertEqualObjects(changeDictionary[NSKeyValueChangeNewKey], @4);
        called = true;
    });

    obj2.int32 = 4;
    XCTAssertTrue(called);
    [realm commitWriteTransaction];

    dispatch_queue_t queue = dispatch_queue_create("queue", 0);
    dispatch_async(queue, ^{
        AllIntSizesObject *obj2 = [AllIntSizesObject allObjects].firstObject;
        [obj2.realm transactionWithBlock:^{
            obj2.int16 = 0;
        }];
    });
    dispatch_sync(queue, ^{});
}

@end