/*
    WebBackForwardList.m
    Copyright 2001, 2002, Apple, Inc. All rights reserved.
*/
#import <WebKit/WebAssertions.h>
#import <WebKit/WebBackForwardList.h>
#import <WebKit/WebHistoryItemPrivate.h>
#import <WebKit/WebKitLogging.h>
#import <WebKit/WebPreferencesPrivate.h>
#import <WebKit/WebKitSystemBits.h>

#define COMPUTE_DEFAULT_PAGE_CACHE_SIZE UINT_MAX

@interface WebBackForwardListPrivate : NSObject
{
@public
    NSMutableArray *entries;
    int current;
    int maximumSize;
    unsigned pageCacheSize;
}
@end

@implementation WebBackForwardListPrivate

- (void)dealloc
{
    [entries release];
    [super dealloc];
}
@end

@implementation WebBackForwardList

- (id)init
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _private = [[WebBackForwardListPrivate alloc] init];
    
    _private->entries = [[NSMutableArray alloc] init];
    _private->current = -1;
    _private->maximumSize = 100;		// typically set by browser app

    _private->pageCacheSize = COMPUTE_DEFAULT_PAGE_CACHE_SIZE;
    
    return self;
}

- (void)dealloc
{
    unsigned i;
    for (i = 0; i < [_private->entries count]; i++){
        WebHistoryItem *item = [_private->entries objectAtIndex: i];
        [item setHasPageCache: NO]; 
    }
    [_private release];
    [super dealloc];
}

- (void)addItem:(WebHistoryItem *)entry;
{
    // Toss anything in the forward list
    int currSize = [_private->entries count];
    if (_private->current != currSize-1 && _private->current != -1) {
        NSRange forwardRange = NSMakeRange(_private->current+1, currSize-(_private->current+1));
        NSArray *subarray;
        subarray = [_private->entries subarrayWithRange:forwardRange];
        unsigned i;
        for (i = 0; i < [subarray count]; i++){
            WebHistoryItem *item = [subarray objectAtIndex: i];
            [item setHasPageCache: NO];            
        }
        [_private->entries removeObjectsInRange: forwardRange];
        currSize -= forwardRange.length;
    }

    // Toss the first item if the list is getting too big, as long as we're not using it
    if (currSize == _private->maximumSize && _private->current != 0) {
        WebHistoryItem *item = [_private->entries objectAtIndex: 0];
        [item setHasPageCache: NO];
        [_private->entries removeObjectAtIndex:0];
        currSize--;
        _private->current--;
    }

    [_private->entries addObject:entry];
    _private->current++;
}

- (BOOL)containsItem:(WebHistoryItem *)entry
{
    return [_private->entries indexOfObjectIdenticalTo:entry] != NSNotFound;
}


- (void)goBack
{
    if(_private->current > 0)
        _private->current--;
    else
        [NSException raise:NSInternalInconsistencyException format:@"%@: goBack called with empty back list", self];
}

- (void)goForward
{
    if(_private->current < (int)[_private->entries count]-1)
        _private->current++;
    else
        [NSException raise:NSInternalInconsistencyException format:@"%@: goForward called with empty forward list", self];
}

- (void)goToItem:(WebHistoryItem *)item
{
    int index = [_private->entries indexOfObjectIdenticalTo:item];
    if (index != NSNotFound)
        _private->current = index;
    else
        [NSException raise:NSInvalidArgumentException format:@"%@: %s:  invalid item", self, __FUNCTION__];
}

- (WebHistoryItem *)backItem
{
    if (_private->current > 0) {
        return [_private->entries objectAtIndex:_private->current-1];
    } else {
        return nil;
    }
}

- (WebHistoryItem *)currentItem
{
    if (_private->current >= 0) {
        return [_private->entries objectAtIndex:_private->current];
    } else {
        return nil;
    }
}

- (WebHistoryItem *)forwardItem
{
    if (_private->current < (int)[_private->entries count]-1) {
        return [_private->entries objectAtIndex:_private->current+1];
    } else {
        return nil;
    }
}

- (NSArray *)backListWithLimit:(int)limit;
{
    if (_private->current > 0) {
        NSRange r;
        r.location = MAX(_private->current-limit, 0);
        r.length = _private->current - r.location;
        return [_private->entries subarrayWithRange:r];
    } else {
        return nil;
    }
}

- (NSArray *)forwardListWithLimit:(int)limit;
{
    int lastEntry = (int)[_private->entries count]-1;
    if (_private->current < lastEntry) {
        NSRange r;
        r.location = _private->current+1;
        r.length =  MIN(_private->current+limit, lastEntry) - _private->current;
        return [_private->entries subarrayWithRange:r];
    } else {
        return nil;
    }
}

- (int)capacity
{
    return _private->maximumSize;
}

- (void)setCapacity:(int)size
{
    _private->maximumSize = size;
}


-(NSString *)description
{
    NSMutableString *result;
    int i;
    
    result = [NSMutableString stringWithCapacity:512];
    
    [result appendString:@"\n--------------------------------------------\n"];    
    [result appendString:@"WebBackForwardList:\n"];
    
    for (i = 0; i < (int)[_private->entries count]; i++) {
        if (i == _private->current) {
            [result appendString:@" >>>"]; 
        }
        else {
            [result appendString:@"    "]; 
        }   
        [result appendFormat:@"%2d) ", i];
        int currPos = [result length];
        [result appendString:[[_private->entries objectAtIndex:i] description]];

        // shift all the contents over.  a bit slow, but this is for debugging
        NSRange replRange = {currPos, [result length]-currPos};
        [result replaceOccurrencesOfString:@"\n" withString:@"\n        " options:0 range:replRange];
        
        [result appendString:@"\n"];
    }

    [result appendString:@"\n--------------------------------------------\n"];    

    return result;
}

- (void)_clearPageCache
{
    int i;
    for (i = 0; i < (int)[_private->entries count]; i++) {
        [[_private->entries objectAtIndex:i] setHasPageCache:NO];
    }
    [WebHistoryItem _releaseAllPendingPageCaches];
}


- (void)setPageCacheSize: (unsigned)size
{
    _private->pageCacheSize = size;
    if (size == 0) {
        [self _clearPageCache];
    }
}

#ifndef NDEBUG
static BOOL loggedPageCacheSize = NO;
#endif

- (unsigned)pageCacheSize
{
    if (_private->pageCacheSize == COMPUTE_DEFAULT_PAGE_CACHE_SIZE) {
        unsigned s;
        vm_size_t memSize = WebSystemMainMemory();
        unsigned multiplier = 1;
        
        s = [[WebPreferences standardPreferences] _pageCacheSize];
        if (memSize > 1024 * 1024 * 1024)
            multiplier = 4;
        else if (memSize > 512 * 1024 * 1024)
            multiplier = 2;

#ifndef NDEBUG
        if (!loggedPageCacheSize){
            LOG (CacheSizes, "Page cache size set to %d pages.", s * multiplier);
            loggedPageCacheSize = YES;
        }
#endif

        _private->pageCacheSize = s * multiplier;
    }
    
    return _private->pageCacheSize;
}

- (BOOL)_usesPageCache
{
    return _private->pageCacheSize != 0;
}

- (int)backListCount
{
    return _private->current;
}

- (int)forwardListCount
{
    return (int)[_private->entries count] - (_private->current + 1);
}

- (WebHistoryItem *)itemAtIndex:(int)index
{
    // Do range checks without doing math on index to avoid overflow.
    if (index < -_private->current) {
        return nil;
    }
    if (index > [self forwardListCount]) {
        return nil;
    }
    return [_private->entries objectAtIndex:index + _private->current];
}

- (NSMutableArray *)_entries
{
    return _private->entries;
}

@end
