//
//  SecItem.m
//  LiveContainer
//
//  Created by s s on 2024/11/29.
//
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "../fishhook/fishhook.h"
#import "utils.h"
#import <CommonCrypto/CommonDigest.h>

OSStatus (*orig_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result);
OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result);
OSStatus (*orig_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);
OSStatus (*orig_SecItemDelete)(CFDictionaryRef query);

NSString* accessGroup = nil;
NSString* containerId = nil;

OSStatus new_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSMutableDictionary *attributesCopy = ((__bridge NSDictionary *)attributes).mutableCopy;
    attributesCopy[(__bridge id)kSecAttrAccessGroup] = accessGroup;
    // for keychain deletion in LCUI
    attributesCopy[@"alis"] = containerId;
    
    OSStatus status = orig_SecItemAdd((__bridge CFDictionaryRef)attributesCopy, result);
    if(status == errSecParam) {
        return orig_SecItemAdd(attributes, result);
    }
    
    return status;
}

OSStatus new_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSMutableDictionary *queryCopy = ((__bridge NSDictionary *)query).mutableCopy;
    queryCopy[(__bridge id)kSecAttrAccessGroup] = accessGroup;
    OSStatus status = orig_SecItemCopyMatching((__bridge CFDictionaryRef)queryCopy, result);
    if(status == errSecParam) {
        // if this search don't support kSecAttrAccessGroup, we just use the original search
        return orig_SecItemCopyMatching(query, result);
    }
    
    return status;
}

OSStatus new_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSMutableDictionary *queryCopy = ((__bridge NSDictionary *)query).mutableCopy;
    queryCopy[(__bridge id)kSecAttrAccessGroup] = accessGroup;
    
    NSMutableDictionary *attrCopy = ((__bridge NSDictionary *)attributesToUpdate).mutableCopy;
    attrCopy[(__bridge id)kSecAttrAccessGroup] = accessGroup;

    OSStatus status = orig_SecItemUpdate((__bridge CFDictionaryRef)queryCopy, (__bridge CFDictionaryRef)attrCopy);

    if(status == errSecParam) {
        return orig_SecItemUpdate(query, attributesToUpdate);
    }
    
    return status;
}

OSStatus new_SecItemDelete(CFDictionaryRef query){
    NSMutableDictionary *queryCopy = ((__bridge NSDictionary *)query).mutableCopy;
    queryCopy[(__bridge id)kSecAttrAccessGroup] = accessGroup;
    OSStatus status = orig_SecItemDelete((__bridge CFDictionaryRef)queryCopy);
    if(status == errSecParam) {
        return new_SecItemDelete(query);
    }
    
    return status;
}

__attribute__((constructor))
static void SecItemGuestHooksInit()  {
    containerId = [NSString stringWithUTF8String:getenv("HOME")].lastPathComponent;
    NSString* containerInfoPath = [[NSString stringWithUTF8String:getenv("HOME")] stringByAppendingPathComponent:@"LCContainerInfo.plist"];
    NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfFile:containerInfoPath];
    int keychainGroupId = [infoDict[@"keychainGroupId"] intValue];
    NSString* groupId = [[NSUserDefaults.lcMainBundle.bundleIdentifier componentsSeparatedByString:@"."] lastObject];
    if(keychainGroupId == 0) {
        accessGroup = [NSString stringWithFormat:@"%@.com.kdt.livecontainer.shared", groupId];
    } else {
        accessGroup = [NSString stringWithFormat:@"%@.com.kdt.livecontainer.shared.%d", groupId, keychainGroupId];
    }

    rebind_symbols((struct rebinding[1]){{"SecItemAdd", (void *)new_SecItemAdd, (void **)&orig_SecItemAdd}},1);
    rebind_symbols((struct rebinding[1]){{"SecItemCopyMatching", (void *)new_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching}},1);
    rebind_symbols((struct rebinding[1]){{"SecItemUpdate", (void *)new_SecItemUpdate, (void **)&orig_SecItemUpdate}},1);
    rebind_symbols((struct rebinding[1]){{"SecItemDelete", (void *)new_SecItemDelete, (void **)&orig_SecItemDelete}},1);
}