//
// EMKLookupCache.m 
// EasyMappingKit
//
// Created by dmitriy on 3/3/14
// Copyright (c) 2014 Yalantis. All rights reserved. 
//
#import "EMKLookupCache.h"
#import "EMKManagedObjectMapping.h"
#import "EMKRelationshipMapping.h"
#import "EMKAttributeMapping.h"
#import "EMKAttributeMapping+Extension.h"

#import <CoreData/CoreData.h>

@class EMKLookupCache;

NSString *const EMKLookupCacheCurrentKey = @"com.yalantis.EasyMappingKit.lookup-cache";

EMKLookupCache *EMKLookupCacheGetCurrent() {
	return [[[NSThread currentThread] threadDictionary] objectForKey:EMKLookupCacheCurrentKey];
}

void EMKLookupCacheSetCurrent(EMKLookupCache *cache) {
	NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
	NSCParameterAssert(cache);
	NSCParameterAssert(![threadDictionary objectForKey:EMKLookupCacheCurrentKey]);

	[threadDictionary setObject:cache forKey:EMKLookupCacheCurrentKey];
}

void EMKLookupCacheRemoveCurrent() {
	NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
	NSCParameterAssert([threadDictionary objectForKey:EMKLookupCacheCurrentKey]);
	[threadDictionary removeObjectForKey:EMKLookupCacheCurrentKey];
}

@implementation EMKLookupCache {
	id _externalRepresentation;

	NSManagedObjectContext *_context;

	NSMutableDictionary *_lookupKeysMap;
	NSMutableDictionary *_lookupObjectsMap;
}

#pragma mark - Init


- (instancetype)initWithMapping:(EMKManagedObjectMapping *)mapping
         externalRepresentation:(id)externalRepresentation
					    context:(NSManagedObjectContext *)context {
	NSParameterAssert(mapping);
	NSParameterAssert(externalRepresentation);
	NSParameterAssert(context);

	self = [self init];
	if (self) {
		_mapping = mapping;
		_context = context;
		
		_lookupKeysMap = [NSMutableDictionary new];
		_lookupObjectsMap = [NSMutableDictionary new];

		[self fillUsingExternalRepresentation:externalRepresentation];
	}

	return self;
}

#pragma mark - Inspection

- (void)inspectObjectRepresentation:(id)objectRepresentation usingMapping:(EMKManagedObjectMapping *)mapping {
	EMKAttributeMapping *primaryKeyMapping = mapping.primaryKeyMapping;
	NSParameterAssert(primaryKeyMapping);

	id primaryKeyValue = [primaryKeyMapping mappedValueFromRepresentation:objectRepresentation];
    if (primaryKeyValue) {
        [_lookupKeysMap[mapping.entityName] addObject:primaryKeyValue];
    }

	for (EMKRelationshipMapping *relationshipMapping in mapping.relationshipMappings) {
		[self inspectExternalRepresentation:objectRepresentation usingMapping:relationshipMapping.objectMapping];
	}
}

- (void)inspectExternalRepresentation:(id)externalRepresentation usingMapping:(EMKManagedObjectMapping *)mapping {
	id representation = [mapping mappedExternalRepresentation:externalRepresentation];

	if ([representation isKindOfClass:NSArray.class]) {
		for (id objectRepresentation in representation) {
			[self inspectObjectRepresentation:objectRepresentation usingMapping:mapping];
		}
	} else if ([representation isKindOfClass:NSDictionary.class]) {
		[self inspectObjectRepresentation:representation usingMapping:mapping];
	} else {
		assert(false);
	}
}

- (void)collectEntityNames:(NSMutableSet *)namesCollection usingMapping:(EMKManagedObjectMapping *)mapping {
	[namesCollection addObject:mapping.entityName];

	for (EMKRelationshipMapping *relationshipMapping in mapping.relationshipMappings) {
		[self collectEntityNames:namesCollection usingMapping:(EMKManagedObjectMapping *)relationshipMapping.objectMapping];
	}
}

- (void)prepareLookupMapsStructure {
	NSMutableSet *entityNames = [NSMutableSet new];
	[self collectEntityNames:entityNames usingMapping:self.mapping];

	for (NSString *entityName in entityNames) {
		_lookupKeysMap[entityName] = [NSMutableSet new];
	}
}

- (void)fillUsingExternalRepresentation:(id)externalRepresentation {
	// ie. drop previous results
	_externalRepresentation = externalRepresentation;

	[_lookupKeysMap removeAllObjects];
	[_lookupObjectsMap removeAllObjects];

	[self prepareLookupMapsStructure];
	[self inspectExternalRepresentation:_externalRepresentation usingMapping:self.mapping];
}

- (NSMutableDictionary *)fetchExistingObjectsForMapping:(EMKManagedObjectMapping *)mapping {
	NSSet *lookupValues = _lookupKeysMap[mapping.entityName];
	if (lookupValues.count == 0) return [NSMutableDictionary dictionary];

	NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:mapping.entityName];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K IN %@", mapping.primaryKey, lookupValues];
	[fetchRequest setPredicate:predicate];
	[fetchRequest setFetchLimit:lookupValues.count];

	NSMutableDictionary *output = [NSMutableDictionary new];
	NSArray *existingObjects = [_context executeFetchRequest:fetchRequest error:NULL];
	for (NSManagedObject *object in existingObjects) {
		output[[object valueForKey:mapping.primaryKey]] = object;
	}

	return output;
}

- (id)existingObjectForRepresentation:(id)representation mapping:(EMKManagedObjectMapping *)mapping {
	NSDictionary *entityObjectsMap = _lookupObjectsMap[mapping.entityName];
	if (!entityObjectsMap) {
		entityObjectsMap = [self fetchExistingObjectsForMapping:mapping];
		_lookupObjectsMap[mapping.entityName] = entityObjectsMap;
	}

	id primaryKeyValue = [mapping.primaryKeyMapping mappedValueFromRepresentation:representation];
	if (primaryKeyValue == nil || primaryKeyValue == NSNull.null) return nil;

	return entityObjectsMap[primaryKeyValue];
}

- (void)addExistingObject:(id)object usingMapping:(EMKManagedObjectMapping *)mapping {
	id primaryKeyValue = [object valueForKeyPath:mapping.primaryKey];
	NSParameterAssert(object);

	[_lookupObjectsMap[mapping.entityName] setObject:object forKey:primaryKeyValue];
}

@end