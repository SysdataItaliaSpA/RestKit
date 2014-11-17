//
//  SDEntityCache.m
//  MyLife
//
//  Created by Davide Ramo on 12/11/14.
//
//

#import "SDEntityCache.h"
#import "RKEntityByAttributeCache.h"

@interface NSEntityDescription (RestKitSync)
@property (nonatomic,readonly) NSEntityDescription* rootEntity;
@end
@implementation NSEntityDescription (RestKitSync)
- (NSEntityDescription*) rootEntity
{
    NSEntityDescription* currentEntity = self.superentity;

    if (!currentEntity)
    {
        return self;
    }

    while (currentEntity.superentity)
    {
        currentEntity = currentEntity.superentity;
    }

    return currentEntity;
}
@end

@interface RKEntityCache ()
@property (nonatomic, strong) NSMutableSet *attributeCaches;
- (void)waitForDispatchGroup:(dispatch_group_t)dispatchGroup withCompletionBlock:(void (^)(void))completion;
@end

@implementation SDEntityCache

//- (id)initWithManagedObjectContext:(NSManagedObjectContext *)context
//{
//    NSAssert(context, @"Cannot initialize entity cache with a nil context");
//    self = [super init];
//    if (self) {
//        _managedObjectContext = context;
//        _attributeCaches = [[NSMutableSet alloc] init];
//    }
//
//    return self;
//}
//
//- (id)init
//{
//    return [self initWithManagedObjectContext:nil];
//}

- (void)cacheObjectsForEntity:(NSEntityDescription *)entity byAttributes:(NSArray *)attributeNames completion:(void (^)(void))completion
{
    NSParameterAssert(entity);
    NSParameterAssert(attributeNames);
    RKEntityByAttributeCache *attributeCache = [self attributeCacheForEntity:entity.rootEntity attributes:attributeNames];
    if (attributeCache && !attributeCache.isLoaded) {
        [attributeCache load:completion];
    } else {
        attributeCache = [[RKEntityByAttributeCache alloc] initWithEntity:entity.rootEntity attributes:attributeNames managedObjectContext:self.managedObjectContext];
        attributeCache.callbackQueue = self.callbackQueue;
        [attributeCache load:completion];
        [self.attributeCaches addObject:attributeCache];
    }
}

- (BOOL)isEntity:(NSEntityDescription *)entity cachedByAttributes:(NSArray *)attributeNames
{
    NSParameterAssert(entity);
    NSParameterAssert(attributeNames);
    RKEntityByAttributeCache *attributeCache = [self attributeCacheForEntity:entity.rootEntity attributes:attributeNames];
    return (attributeCache && attributeCache.isLoaded);
}

- (NSManagedObject *)objectForEntity:(NSEntityDescription *)entity withAttributeValues:(NSDictionary *)attributeValues inContext:(NSManagedObjectContext *)context
{
    NSParameterAssert(entity);
    NSParameterAssert(attributeValues);
    NSParameterAssert(context);
    RKEntityByAttributeCache *attributeCache = [self attributeCacheForEntity:entity.rootEntity attributes:[attributeValues allKeys]];
    if (attributeCache) {
        return [attributeCache objectWithAttributeValues:attributeValues inContext:context];
    }

    return nil;
}

- (NSSet *)objectsForEntity:(NSEntityDescription *)entity withAttributeValues:(NSDictionary *)attributeValues inContext:(NSManagedObjectContext *)context
{
    NSParameterAssert(entity);
    NSParameterAssert(attributeValues);
    NSParameterAssert(context);
    RKEntityByAttributeCache *attributeCache = [self attributeCacheForEntity:entity.rootEntity attributes:[attributeValues allKeys]];
    if (attributeCache) {
        return [attributeCache objectsWithAttributeValues:attributeValues inContext:context];
    }

    return [NSSet set];
}

- (RKEntityByAttributeCache *)attributeCacheForEntity:(NSEntityDescription *)entity attributes:(NSArray *)attributeNames
{
    NSParameterAssert(entity);
    NSParameterAssert(attributeNames);
    for (RKEntityByAttributeCache *cache in [self.attributeCaches copy]) {
        if ([cache.entity isEqual:entity.rootEntity] && [cache.attributes isEqualToArray:attributeNames]) {
            return cache;
        }
    }

    return nil;
}

- (NSSet *)attributeCachesForEntity:(NSEntityDescription *)entity
{
    NSAssert(entity, @"Cannot retrieve attribute caches for a nil entity");
    NSMutableSet *set = [NSMutableSet set];
    for (RKEntityByAttributeCache *cache in [self.attributeCaches copy]) {
        if ([cache.entity isEqual:entity.rootEntity]) {
            [set addObject:cache];
        }
    }

    return [NSSet setWithSet:set];
}

//- (void)waitForDispatchGroup:(dispatch_group_t)dispatchGroup withCompletionBlock:(void (^)(void))completion
//{
//    if (completion) {
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),^{
//            dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
//#if !OS_OBJECT_USE_OBJC
//            dispatch_release(dispatchGroup);
//#endif
//            dispatch_async(self.callbackQueue ?: dispatch_get_main_queue(), completion);
//        });
//    }
//}

//- (void)flush:(void (^)(void))completion
//{
//    dispatch_group_t dispatchGroup = completion ? dispatch_group_create() : NULL;
//    for (RKEntityByAttributeCache *cache in self.attributeCaches) {
//        if (dispatchGroup) dispatch_group_enter(dispatchGroup);
//        [cache flush:^{
//            if (dispatchGroup) dispatch_group_leave(dispatchGroup);
//        }];
//    }
//    if (dispatchGroup) [self waitForDispatchGroup:dispatchGroup withCompletionBlock:completion];
//}

- (void)addObject:(NSManagedObject *)object completion:(void (^)(void))completion
{
    NSAssert(object, @"Cannot add a nil object to the cache");
    dispatch_group_t dispatchGroup = completion ? dispatch_group_create() : NULL;
    NSArray *attributeCaches = [self attributeCachesForEntity:object.entity.rootEntity];
    NSSet *objects = [NSSet setWithObject:object];
    for (RKEntityByAttributeCache *cache in attributeCaches) {
        if (dispatchGroup) dispatch_group_enter(dispatchGroup);
        [cache addObjects:objects completion:^{
            if (dispatchGroup) dispatch_group_leave(dispatchGroup);
        }];
    }
    if (dispatchGroup) [self waitForDispatchGroup:dispatchGroup withCompletionBlock:completion];
}

- (void)removeObject:(NSManagedObject *)object completion:(void (^)(void))completion
{
    NSAssert(object, @"Cannot remove a nil object from the cache");
    NSArray *attributeCaches = [self attributeCachesForEntity:object.entity.rootEntity];
    NSSet *objects = [NSSet setWithObject:object];
    dispatch_group_t dispatchGroup = completion ? dispatch_group_create() : NULL;
    for (RKEntityByAttributeCache *cache in attributeCaches) {
        if (dispatchGroup) dispatch_group_enter(dispatchGroup);
        [cache removeObjects:objects completion:^{
            if (dispatchGroup) dispatch_group_leave(dispatchGroup);
        }];
    }
    if (dispatchGroup) [self waitForDispatchGroup:dispatchGroup withCompletionBlock:completion];
}

- (void)addObjects:(NSSet *)objects completion:(void (^)(void))completion
{
    dispatch_group_t dispatchGroup = completion ? dispatch_group_create() : NULL;
    NSSet *distinctEntities = [objects valueForKeyPath:@"entity"];
    for (NSEntityDescription *entity in distinctEntities) {
        NSArray *attributeCaches = [self attributeCachesForEntity:entity.rootEntity];
        if ([attributeCaches count]) {
            NSMutableSet *objectsToAdd = [NSMutableSet set];
            for (NSManagedObject *managedObject in objects) {
                if ([managedObject.entity isEqual:entity]) [objectsToAdd addObject:managedObject];
            }
            for (RKEntityByAttributeCache *cache in attributeCaches) {
                if (dispatchGroup) dispatch_group_enter(dispatchGroup);
                [cache addObjects:objectsToAdd completion:^{
                    if (dispatchGroup) dispatch_group_leave(dispatchGroup);
                }];
            }
        }
    }
    if (dispatchGroup) [self waitForDispatchGroup:dispatchGroup withCompletionBlock:completion];
}

- (void)removeObjects:(NSSet *)objects completion:(void (^)(void))completion
{
    dispatch_group_t dispatchGroup = completion ? dispatch_group_create() : NULL;
    NSSet *distinctEntities = [objects valueForKeyPath:@"entity"];
    for (NSEntityDescription *entity in distinctEntities) {
        NSArray *attributeCaches = [self attributeCachesForEntity:entity.rootEntity];
        if ([attributeCaches count]) {
            NSMutableSet *objectsToRemove = [NSMutableSet set];
            for (NSManagedObject *managedObject in objects) {
                if ([managedObject.entity isEqual:entity]) [objectsToRemove addObject:managedObject];
            }
            for (RKEntityByAttributeCache *cache in attributeCaches) {
                if (dispatchGroup) dispatch_group_enter(dispatchGroup);
                [cache removeObjects:objectsToRemove completion:^{
                    if (dispatchGroup) dispatch_group_leave(dispatchGroup);
                }];
            }
        }
    }
    if (dispatchGroup) [self waitForDispatchGroup:dispatchGroup withCompletionBlock:completion];
}

- (BOOL)containsObject:(NSManagedObject *)managedObject
{
    for (RKEntityByAttributeCache *attributeCache in [self attributeCachesForEntity:managedObject.entity.rootEntity]) {
        if ([attributeCache containsObject:managedObject]) return YES;
    }

    return NO;
}@end
