#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns a reversible, process-scoped menu bar visibility request.
/// No files or system preferences are changed.
@interface NookVisibilityLease : NSObject
+ (BOOL)isAvailable;
+ (nullable instancetype)allowBundles:(NSArray<NSString *> *)bundles
                          completion:(void (^)(NSError * _Nullable error))completion;
- (void)restore;
@end

NS_ASSUME_NONNULL_END
