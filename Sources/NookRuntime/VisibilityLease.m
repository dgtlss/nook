#import "NookRuntime.h"
#import <dlfcn.h>

// Selector names and signatures were inspected on the installed macOS 27.2
// framework with tools/framework-probe.m. This is original implementation.
@protocol NookConfigurationFactory
- (instancetype)initWithAllowedSystemItems:(NSArray<NSNumber *> *)items
                  allowedBundleIdentifiers:(NSArray<NSString *> *)bundles;
@end

@protocol NookAssessmentRequest
- (void)activateWithConfiguration:(id)configuration
               completionHandler:(void (^)(NSError * _Nullable))completion;
- (void)invalidate;
@end

@interface NookVisibilityLease ()
@property(nonatomic, strong) id<NookAssessmentRequest> request;
@end

@implementation NookVisibilityLease
+ (BOOL)isAvailable {
    static void *loadedFramework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        loadedFramework = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW | RTLD_LOCAL);
    });
    if (!loadedFramework) return NO;
    Class factory = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class engine = NSClassFromString(@"MBAssessmentModeAssertion");
    return [factory instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)]
        && [engine instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)]
        && [engine instancesRespondToSelector:@selector(invalidate)];
}

+ (instancetype)allowBundles:(NSArray<NSString *> *)bundles completion:(void (^)(NSError *))completion {
    if (![self isAvailable]) return nil;
    NookVisibilityLease *lease = [[self alloc] init];
    @try {
        // Installed 27.2 MBSystemItemIdentifier.rawValue accepts 0...8.
        // Verified with Apple's dyld_info; allow all native identifiers.
        // Live verification still checks for collateral native-module changes.
        NSMutableArray<NSNumber *> *systemItems = [NSMutableArray array];
        for (NSInteger value = 0; value <= 8; value++) [systemItems addObject:@(value)];
        Class factory = NSClassFromString(@"MBAssessmentModeConfiguration");
        id<NookConfigurationFactory> allocated = [factory alloc];
        id configuration = [allocated initWithAllowedSystemItems:systemItems allowedBundleIdentifiers:bundles];
        lease.request = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!configuration || !lease.request) return nil;
        [lease.request activateWithConfiguration:configuration completionHandler:completion];
        return lease;
    } @catch (NSException *exception) {
        [lease restore];
        completion([NSError errorWithDomain:@"Nook.Visibility" code:1 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"macOS rejected the visibility request."}]);
        return nil;
    }
}

- (void)restore {
    id<NookAssessmentRequest> request = self.request;
    self.request = nil;
    @try { [request invalidate]; }
    @catch (NSException *exception) { NSLog(@"Nook could not release a visibility request: %@", exception.reason); }
}

- (void)dealloc {
    [self restore];
}
@end
