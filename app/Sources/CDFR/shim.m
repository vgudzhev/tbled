#import "CDFR.h"
#import <dlfcn.h>

// --- Private DFRFoundation C functions, resolved at runtime via dlsym -------

typedef void (*GLOWBARSetPresenceFn)(NSString *, BOOL);
typedef void (*GLOWBARShowCloseBoxFn)(BOOL);

static void *GLOWBARDFRHandle(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/"
                        "Versions/A/DFRFoundation", RTLD_NOW);
    });
    return handle;
}

BOOL GLOWBARDFRAvailable(void) { return GLOWBARDFRHandle() != NULL; }

void GLOWBARSetControlStripPresence(NSString *identifier, BOOL present) {
    void *h = GLOWBARDFRHandle();
    if (!h) return;
    GLOWBARSetPresenceFn fn =
        (GLOWBARSetPresenceFn)dlsym(h, "DFRElementSetControlStripPresenceForIdentifier");
    if (fn) fn(identifier, present);
}

void GLOWBARShowCloseBox(BOOL show) {
    void *h = GLOWBARDFRHandle();
    if (!h) return;
    GLOWBARShowCloseBoxFn fn =
        (GLOWBARShowCloseBoxFn)dlsym(h, "DFRSystemModalShowsCloseBoxWhenFrontMost");
    if (fn) fn(show);
}

// --- Private NSTouchBar / NSTouchBarItem class methods ----------------------
// Declared here so the compiler is happy; guarded with respondsToSelector: so
// they degrade to no-ops if Apple renames or removes them (e.g. newer macOS).

@interface NSTouchBarItem (GLOWBARPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (GLOWBARPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
          systemTrayItemIdentifier:(NSString *)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

void GLOWBARAddSystemTrayItem(NSTouchBarItem *item) {
    if ([NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)]) {
        [NSTouchBarItem addSystemTrayItem:item];
    }
}

void GLOWBARPresentSystemModal(NSTouchBar *bar, NSString *identifier) {
    SEL sel = @selector(presentSystemModalTouchBar:systemTrayItemIdentifier:);
    if ([NSTouchBar respondsToSelector:sel]) {
        [NSTouchBar presentSystemModalTouchBar:bar systemTrayItemIdentifier:identifier];
    }
}

void GLOWBARDismissSystemModal(NSTouchBar *bar) {
    if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]) {
        [NSTouchBar dismissSystemModalTouchBar:bar];
    }
}
