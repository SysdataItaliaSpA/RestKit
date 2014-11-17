//
//  SDInMemoryManagedObjectCache.m
//  MyLife
//
//  Created by Davide Ramo on 12/11/14.
//
//

#import "SDInMemoryManagedObjectCache.h"
#import "SDEntityCache.h"
#import "RKLog.h"
#import "RKEntityByAttributeCache.h"

// Set Logging Component
#undef RKLogComponent
#define RKLogComponent RKlcl_cRestKitCoreData

static NSPersistentStoreCoordinator *RKPersistentStoreCoordinatorFromManagedObjectContext(NSManagedObjectContext *managedObjectContext)
{
    NSManagedObjectContext *currentContext = managedObjectContext;
    do {
        if ([currentContext persistentStoreCoordinator]) return [currentContext persistentStoreCoordinator];
        currentContext = [currentContext parentContext];
    } while (currentContext);
    return nil;
}

static dispatch_queue_t RKInMemoryManagedObjectCacheCallbackQueue(void)
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t callbackQueue;
    dispatch_once(&onceToken, ^{
        callbackQueue = dispatch_queue_create("org.restkit.core-data.in-memory-cache.callback-queue", DISPATCH_QUEUE_CONCURRENT);
    });
    return callbackQueue;
}

@interface RKInMemoryManagedObjectCache (RestKitSync)
@property (nonatomic, assign) dispatch_queue_t callbackQueue;
- (void)handleManagedObjectContextDidChangeNotification:(NSNotification *)notification;
@end

@interface SDInMemoryManagedObjectCache ()
@property (nonatomic, strong, readwrite) SDEntityCache *entityCache;
@end

@implementation SDInMemoryManagedObjectCache

- (id)initWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
    self = [super initWithManagedObjectContext:managedObjectContext];
    if (self) {
        NSManagedObjectContext *cacheContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [cacheContext setPersistentStoreCoordinator:RKPersistentStoreCoordinatorFromManagedObjectContext(managedObjectContext)];
        self.entityCache = [[SDEntityCache alloc] initWithManagedObjectContext:cacheContext];
        self.entityCache.callbackQueue = RKInMemoryManagedObjectCacheCallbackQueue();

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleManagedObjectContextDidChangeNotification:) name:NSManagedObjectContextObjectsDidChangeNotification object:managedObjectContext];
    }
    return self;
}

- (id)init
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"%@ Failed to call designated initializer. Invoke initWithManagedObjectContext: instead.",
                                           NSStringFromClass([self class])]
                                 userInfo:nil];
}

- (NSSet *)managedObjectsWithEntity:(NSEntityDescription *)entity
                    attributeValues:(NSDictionary *)attributeValues
             inManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
    NSParameterAssert(entity);
    NSParameterAssert(attributeValues);
    NSParameterAssert(managedObjectContext);

    NSArray *attributes = [attributeValues allKeys];
    if (! [self.entityCache isEntity:entity cachedByAttributes:attributes]) {
        RKLogInfo(@"Caching instances of Entity '%@' by attributes '%@'", entity.name, [attributes componentsJoinedByString:@", "]);
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [self.entityCache cacheObjectsForEntity:entity byAttributes:attributes completion:^{
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

        RKEntityByAttributeCache *attributeCache = [self.entityCache attributeCacheForEntity:entity attributes:attributes];

        // Fetch any pending objects and add them to the cache
        NSFetchRequest *fetchRequest = [NSFetchRequest new];
        fetchRequest.entity = entity;
        fetchRequest.includesPendingChanges = YES;

        [managedObjectContext performBlockAndWait:^{
            NSError *error = nil;
            NSArray *objects = nil;
            objects = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
            if (objects) {
                [attributeCache addObjects:[NSSet setWithArray:objects] completion:^{
                    dispatch_semaphore_signal(semaphore);
                }];
            } else {
                RKLogError(@"Fetched pre-loading existing managed objects with error: %@", error);
                dispatch_semaphore_signal(semaphore);
            }
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

#if !OS_OBJECT_USE_OBJC
        dispatch_release(semaphore);
#endif

        RKLogTrace(@"Cached %ld objects", (long)[attributeCache count]);
    }

    return [self.entityCache objectsForEntity:entity withAttributeValues:attributeValues inContext:managedObjectContext];
}

@end
