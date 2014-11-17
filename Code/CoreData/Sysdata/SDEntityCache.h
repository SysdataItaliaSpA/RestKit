//
//  SDEntityCache.h
//  MyLife
//
//  Created by Davide Ramo on 12/11/14.
//
//

#import "RKEntityCache.h"

/**
 *  Workaround to cache NSManagedObjects by entity.rootEntity instead of actual entity.
 *  This because in RKEntityCache when a relation is defined from entity Person to the same entity Person (like Person-child->Person) the cache doesn't retrieve destination entity if the destination entity is a subentity (Client subentity of Person and relation is linked from Person->Client)
 */
@interface SDEntityCache : RKEntityCache

@end
