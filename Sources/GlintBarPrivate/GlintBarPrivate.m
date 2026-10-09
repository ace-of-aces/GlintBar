#import "GlintBarPrivate.h"
#include <dlfcn.h>
#include <objc/message.h>

#define PRIVATE_FW(name) "/System/Library/PrivateFrameworks/" name ".framework/" name

static void *GLHandle(const char *path) {
    // dlopen ref-counts and caches, so repeated calls are cheap.
    return dlopen(path, RTLD_LAZY | RTLD_LOCAL);
}

static void *GLSymbol(const char *path, const char *symbol) {
    void *handle = GLHandle(path);
    return handle ? dlsym(handle, symbol) : NULL;
}

// MARK: - Touch Bar

@interface NSTouchBar (GlintBarPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar placement:(long long)placement systemTrayItemIdentifier:(nullable NSTouchBarItemIdentifier)identifier;
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar systemTrayItemIdentifier:(nullable NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

@interface NSTouchBarItem (GlintBarPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

static const char *kDFRFoundation = PRIVATE_FW("DFRFoundation");

BOOL GLSystemModalAvailable(void) {
    GLHandle(kDFRFoundation);
    return [NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]
        && [NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]
        && [NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)];
}

void GLPresentSystemModal(NSTouchBar *touchBar, GLSystemModalPlacement placement, NSTouchBarItemIdentifier trayIdentifier) {
    if ([NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]) {
        [NSTouchBar presentSystemModalTouchBar:touchBar placement:placement systemTrayItemIdentifier:trayIdentifier];
    } else if ([NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:systemTrayItemIdentifier:)]) {
        [NSTouchBar presentSystemModalTouchBar:touchBar systemTrayItemIdentifier:trayIdentifier];
    }
}

void GLDismissSystemModal(NSTouchBar *touchBar) {
    if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]) {
        [NSTouchBar dismissSystemModalTouchBar:touchBar];
    }
}

void GLMinimizeSystemModal(NSTouchBar *touchBar) {
    if ([NSTouchBar respondsToSelector:@selector(minimizeSystemModalTouchBar:)]) {
        [NSTouchBar minimizeSystemModalTouchBar:touchBar];
    }
}

void GLAddSystemTrayItem(NSTouchBarItem *item) {
    if ([NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)]) {
        [NSTouchBarItem addSystemTrayItem:item];
    }
}

void GLRemoveSystemTrayItem(NSTouchBarItem *item) {
    if ([NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)]) {
        [NSTouchBarItem removeSystemTrayItem:item];
    }
}

void GLSetControlStripPresence(NSTouchBarItemIdentifier identifier, BOOL present) {
    void (*fn)(NSString *, BOOL) = GLSymbol(kDFRFoundation, "DFRElementSetControlStripPresenceForIdentifier");
    if (fn) fn(identifier, present);
}

void GLSetSystemModalShowsCloseBox(BOOL shows) {
    void (*fn)(BOOL) = GLSymbol(kDFRFoundation, "DFRSystemModalShowsCloseBoxWhenFrontMost");
    if (fn) fn(shows);
}

// MARK: - Display brightness

static const char *kDisplayServices = PRIVATE_FW("DisplayServices");

BOOL GLDisplayBrightnessGet(CGDirectDisplayID display, float *outValue) {
    int (*fn)(CGDirectDisplayID, float *) = GLSymbol(kDisplayServices, "DisplayServicesGetBrightness");
    return fn ? fn(display, outValue) == 0 : NO;
}

BOOL GLDisplayBrightnessSet(CGDirectDisplayID display, float value) {
    int (*fn)(CGDirectDisplayID, float) = GLSymbol(kDisplayServices, "DisplayServicesSetBrightness");
    if (!fn || fn(display, value) != 0) return NO;
    // Lets the rest of the system (Control Center, ambient adaptation) know about the change.
    void (*changed)(CGDirectDisplayID, double) = GLSymbol(kDisplayServices, "DisplayServicesBrightnessChanged");
    if (changed) changed(display, value);
    return YES;
}

// MARK: - Keyboard backlight

@protocol GLKeyboardBrightnessClient <NSObject>
- (NSArray<NSNumber *> *)copyKeyboardBacklightIDs;
- (float)brightnessForKeyboard:(unsigned long long)keyboardID;
- (BOOL)setBrightness:(float)brightness forKeyboard:(unsigned long long)keyboardID;
@end

static id<GLKeyboardBrightnessClient> GLKeyboardClient(unsigned long long *outID) {
    static id<GLKeyboardBrightnessClient> client;
    static unsigned long long keyboardID;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!GLHandle(PRIVATE_FW("CoreBrightness"))) return;
        Class cls = NSClassFromString(@"KeyboardBrightnessClient");
        if (!cls) return;
        id candidate = [[cls alloc] init];
        if (![candidate respondsToSelector:@selector(brightnessForKeyboard:)]
            || ![candidate respondsToSelector:@selector(setBrightness:forKeyboard:)]) return;
        keyboardID = 1; // The built-in keyboard on every Touch Bar MacBook Pro.
        if ([candidate respondsToSelector:@selector(copyKeyboardBacklightIDs)]) {
            NSNumber *first = [candidate copyKeyboardBacklightIDs].firstObject;
            if (first) keyboardID = first.unsignedLongLongValue;
        }
        client = candidate;
    });
    if (outID) *outID = keyboardID;
    return client;
}

BOOL GLKeyboardBacklightAvailable(void) {
    return GLKeyboardClient(NULL) != nil;
}

float GLKeyboardBrightnessGet(void) {
    unsigned long long kid;
    id<GLKeyboardBrightnessClient> client = GLKeyboardClient(&kid);
    return client ? [client brightnessForKeyboard:kid] : 0;
}

BOOL GLKeyboardBrightnessSet(float value) {
    unsigned long long kid;
    id<GLKeyboardBrightnessClient> client = GLKeyboardClient(&kid);
    return client ? [client setBrightness:value forKeyboard:kid] : NO;
}

// MARK: - Night Shift

typedef struct {
    int hour;
    int minute;
} GLBlueLightTime;

typedef struct {
    BOOL active;
    BOOL enabled; // Night Shift is on right now
    BOOL sunSchedulePermitted;
    int mode;
    struct { GLBlueLightTime from, to; } schedule;
    unsigned long long disableFlags;
    BOOL available;
} GLBlueLightStatus;

@protocol GLBlueLightClient <NSObject>
+ (BOOL)supportsBlueLightReduction;
- (BOOL)getBlueLightStatus:(GLBlueLightStatus *)status;
- (BOOL)setEnabled:(BOOL)enabled;
@end

static id<GLBlueLightClient> GLBlueLight(void) {
    static id<GLBlueLightClient> client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!GLHandle(PRIVATE_FW("CoreBrightness"))) return;
        Class cls = NSClassFromString(@"CBBlueLightClient");
        if (![cls respondsToSelector:@selector(supportsBlueLightReduction)] || ![cls supportsBlueLightReduction]) return;
        id candidate = [[cls alloc] init];
        if (![candidate respondsToSelector:@selector(getBlueLightStatus:)]
            || ![candidate respondsToSelector:@selector(setEnabled:)]) return;
        client = candidate;
    });
    return client;
}

BOOL GLNightShiftAvailable(void) {
    return GLBlueLight() != nil;
}

BOOL GLNightShiftIsOn(void) {
    GLBlueLightStatus status = {0};
    return [GLBlueLight() getBlueLightStatus:&status] && status.enabled;
}

BOOL GLNightShiftSetOn(BOOL on) {
    id<GLBlueLightClient> client = GLBlueLight();
    return client ? [client setEnabled:on] : NO;
}

// MARK: - Media

static const char *kMediaRemote = PRIVATE_FW("MediaRemote");

BOOL GLMediaSendCommand(GLMediaCommand command) {
    Boolean (*fn)(int, CFDictionaryRef) = GLSymbol(kMediaRemote, "MRMediaRemoteSendCommand");
    return fn ? fn((int)command, NULL) : NO;
}

// MARK: - Session

BOOL GLLockScreen(void) {
    void (*fn)(void) = GLSymbol(PRIVATE_FW("login"), "SACLockScreenImmediate");
    if (!fn) return NO;
    fn();
    return YES;
}

// MARK: - Dock

BOOL GLDockSendNotification(NSString *name) {
    void (*fn)(CFStringRef, int) = GLSymbol("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", "CoreDockSendNotification");
    if (!fn) return NO;
    fn((__bridge CFStringRef)name, 0);
    return YES;
}
