#import "CDFR.h"
#import <dlfcn.h>

// --- Private DFRFoundation C functions, resolved at runtime via dlsym -------

typedef void (*TBLEDSetPresenceFn)(NSString *, BOOL);
typedef void (*TBLEDShowCloseBoxFn)(BOOL);

static void *TBLEDDFRHandle(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/"
                        "Versions/A/DFRFoundation", RTLD_NOW);
    });
    return handle;
}

BOOL TBLEDDFRAvailable(void) { return TBLEDDFRHandle() != NULL; }

void TBLEDSetControlStripPresence(NSString *identifier, BOOL present) {
    void *h = TBLEDDFRHandle();
    if (!h) return;
    TBLEDSetPresenceFn fn =
        (TBLEDSetPresenceFn)dlsym(h, "DFRElementSetControlStripPresenceForIdentifier");
    if (fn) fn(identifier, present);
}

void TBLEDShowCloseBox(BOOL show) {
    void *h = TBLEDDFRHandle();
    if (!h) return;
    TBLEDShowCloseBoxFn fn =
        (TBLEDShowCloseBoxFn)dlsym(h, "DFRSystemModalShowsCloseBoxWhenFrontMost");
    if (fn) fn(show);
}

// --- Private NSTouchBar / NSTouchBarItem class methods ----------------------
// Declared here so the compiler is happy; guarded with respondsToSelector: so
// they degrade to no-ops if Apple renames or removes them (e.g. newer macOS).

@interface NSTouchBarItem (TBLEDPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (TBLEDPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
          systemTrayItemIdentifier:(NSString *)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

void TBLEDAddSystemTrayItem(NSTouchBarItem *item) {
    if ([NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)]) {
        [NSTouchBarItem addSystemTrayItem:item];
    }
}

void TBLEDPresentSystemModal(NSTouchBar *bar, NSString *identifier) {
    SEL sel = @selector(presentSystemModalTouchBar:systemTrayItemIdentifier:);
    if ([NSTouchBar respondsToSelector:sel]) {
        [NSTouchBar presentSystemModalTouchBar:bar systemTrayItemIdentifier:identifier];
    }
}

void TBLEDDismissSystemModal(NSTouchBar *bar) {
    if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]) {
        [NSTouchBar dismissSystemModalTouchBar:bar];
    }
}
