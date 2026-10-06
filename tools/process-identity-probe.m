// Read-only process metadata probe; no Accessibility or window interaction.
#import <AppKit/AppKit.h>
#import <dlfcn.h>

int main(void) {
    @autoreleasepool {
        void *framework = dlopen("/System/Library/PrivateFrameworks/BaseBoard.framework/BaseBoard", RTLD_NOW);
        NSString *(*bundleForPID)(pid_t) = dlsym(framework, "BSBundleIDForPID");
        for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
            if ([app.localizedName isEqualToString:@"Nook"] || [app.localizedName isEqualToString:@"Figma"] || [app.localizedName hasPrefix:@"Nook Test"]) {
                NSLog(@"%@ pid=%d AppKit=%@ BaseBoard=%@ url=%@", app.localizedName, app.processIdentifier, app.bundleIdentifier, bundleForPID ? bundleForPID(app.processIdentifier) : @"unavailable", app.bundleURL);
            }
        }
    }
}
