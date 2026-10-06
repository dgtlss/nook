// Original runtime inspection tool. Prints API metadata only; creates no assertions.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

int main(void) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW);
        if (!handle) { fprintf(stderr, "%s\n", dlerror()); return 1; }
        unsigned int count = 0;
        Class *classes = objc_copyClassList(&count);
        for (unsigned int i = 0; i < count; i++) {
            Class cls = classes[i];
            const char *origin = class_getImageName(cls);
            if (!origin || !strstr(origin, "MenuBarClientCore")) continue;
            printf("Class %s\n", class_getName(cls));
            unsigned int methodsCount = 0;
            Method *methods = class_copyMethodList(cls, &methodsCount);
            for (unsigned int j = 0; j < methodsCount; j++) {
                printf("  - %s %s\n", sel_getName(method_getName(methods[j])), method_getTypeEncoding(methods[j]));
            }
            free(methods);
        }
        free(classes);
    }
}
