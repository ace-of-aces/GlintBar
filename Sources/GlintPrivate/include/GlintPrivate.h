#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Touch Bar (DFRFoundation / private AppKit)

typedef NS_ENUM(NSInteger, GLSystemModalPlacement) {
    /// The system modal bar sits next to the Control Strip.
    GLSystemModalPlacementBesideControlStrip = 0,
    /// The system modal bar covers the full width, Control Strip included.
    GLSystemModalPlacementFullWidth = 1,
} NS_SWIFT_NAME(SystemModalPlacement);

/// Whether the private system-modal Touch Bar API is available on this OS.
BOOL GLSystemModalAvailable(void);

void GLPresentSystemModal(NSTouchBar *touchBar, GLSystemModalPlacement placement, NSTouchBarItemIdentifier _Nullable trayIdentifier);
void GLDismissSystemModal(NSTouchBar *touchBar);
void GLMinimizeSystemModal(NSTouchBar *touchBar);

void GLAddSystemTrayItem(NSTouchBarItem *item);
void GLRemoveSystemTrayItem(NSTouchBarItem *item);

void GLSetControlStripPresence(NSTouchBarItemIdentifier identifier, BOOL present);
void GLSetSystemModalShowsCloseBox(BOOL shows);

// MARK: - Display brightness (DisplayServices)

BOOL GLDisplayBrightnessGet(CGDirectDisplayID display, float *outValue);
BOOL GLDisplayBrightnessSet(CGDirectDisplayID display, float value);

// MARK: - Keyboard backlight (CoreBrightness)

BOOL GLKeyboardBacklightAvailable(void);
float GLKeyboardBrightnessGet(void);
BOOL GLKeyboardBrightnessSet(float value);

// MARK: - Night Shift (CoreBrightness)

BOOL GLNightShiftAvailable(void);
BOOL GLNightShiftIsOn(void);
BOOL GLNightShiftSetOn(BOOL on);

// MARK: - Media (MediaRemote)

typedef NS_ENUM(NSInteger, GLMediaCommand) {
    GLMediaCommandPlay = 0,
    GLMediaCommandPause = 1,
    GLMediaCommandTogglePlayPause = 2,
    GLMediaCommandStop = 3,
    GLMediaCommandNextTrack = 4,
    GLMediaCommandPreviousTrack = 5,
} NS_SWIFT_NAME(MediaCommand);

BOOL GLMediaSendCommand(GLMediaCommand command);
// Playback *state* can't be read from here; see Sources/GlintNowPlaying.

// MARK: - Session (login)

/// Locks the screen right away, like the Lock Screen menu item.
BOOL GLLockScreen(void);

// MARK: - Dock (HIServices)

/// Sends the Dock a notification such as `com.apple.showdesktop.awake`.
BOOL GLDockSendNotification(NSString *name);

NS_ASSUME_NONNULL_END
