// CDFR — Objective-C shim over the private DFRFoundation / NSTouchBar control
// strip API used by Pock and MTMR to place a persistent Touch Bar item.
//
// Everything is resolved dynamically (dlopen for the C functions,
// respondsToSelector: for the private class methods) so the app links and
// runs even on Macs without a Touch Bar or on macOS versions where these
// private entry points have been renamed or removed — the calls become no-ops
// and the menu-bar mirror remains authoritative.
#import <AppKit/AppKit.h>

/// YES if the private DFRFoundation framework could be loaded on this system.
BOOL GLOWBARDFRAvailable(void);

/// Show/hide a control-strip item with the given identifier (persistent tile).
void GLOWBARSetControlStripPresence(NSString *identifier, BOOL present);

/// Whether the system-modal Touch Bar shows a close box when frontmost.
void GLOWBARShowCloseBox(BOOL show);

/// Register a Touch Bar item as a system-tray (control strip) item.
void GLOWBARAddSystemTrayItem(NSTouchBarItem *item);

/// Present a full Touch Bar modally, anchored to the given tray identifier.
void GLOWBARPresentSystemModal(NSTouchBar *bar, NSString *identifier);

/// Dismiss a previously presented system-modal Touch Bar.
void GLOWBARDismissSystemModal(NSTouchBar *bar);
