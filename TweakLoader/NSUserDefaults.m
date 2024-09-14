//
//  NSUserDefaults.m
//  jump
//
//  Created by s s on 2024/9/13.
//

#import <Foundation/Foundation.h>
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "utils.h"

__attribute__((constructor))
static void UIKitGuestHooksInit() {
    swizzle(NSUserDefaults.class, @selector(_initWithSuiteName:container:), @selector(hook__initWithSuiteName:container:));
}


@implementation NSUserDefaults(LiveContainerHooks)

- (instancetype) hook__initWithSuiteName:(NSString*)name container:(NSURL*)url {
    NSURL* urlNew = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"%s", getenv("LC_HOME_PATH")]];
    return [self hook__initWithSuiteName:name container:urlNew];
}

@end
