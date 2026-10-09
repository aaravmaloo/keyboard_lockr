// klock_mac.mm
// macOS: blocks all keyboard input when locked, toggled with Cmd+Shift+X.
// Menu bar icon (keyboard glyph + lock badge) is drawn at runtime with Core Graphics, no image files needed.
// Build:  make bundle   (produces Klock.app)
// Run:    drag Klock.app to /Applications, then double-click it (or `open Klock.app`)
// Needs:  System Settings -> Privacy & Security -> Accessibility -> allow Klock.
//         Without it the app stays in the menu bar and shows "Permission needed" until granted.
// "Start at login" in the menu uses SMAppService, which only works once this is
// running from inside a proper .app bundle with a stable path (e.g. /Applications).

#import <Cocoa/Cocoa.h>
#include <ApplicationServices/ApplicationServices.h>
#import <ServiceManagement/ServiceManagement.h>

static bool locked = false;
static CFMachPortRef eventTap = NULL;
static const CGKeyCode kVK_ANSI_X_CODE = 7;

@interface KlockController : NSObject
@property (strong) NSStatusItem *statusItem;
@property (strong) NSImage *iconLocked;
@property (strong) NSImage *iconUnlocked;
@property (strong) NSMenuItem *startupItem;
@property (strong) NSMenuItem *toggleItem;
@property (strong) NSMenuItem *permissionItem;
@property (strong) NSTimer *retryTimer;
- (void)updateIcon;
- (void)setPermissionMissing:(BOOL)missing;
- (void)openPermissionSettings;
- (void)toggleLock;
- (void)toggleStartup;
@end

// Draws the keyboard glyph + lock badge into an NSImage at runtime.
static NSImage* DrawTrayIcon(BOOL isLocked) {
    NSSize size = NSMakeSize(18, 18); // menu bar icons render small; template style
    NSImage *img = [[NSImage alloc] initWithSize:size];
    [img lockFocus];

    NSColor *fg = [NSColor blackColor]; // template image: macOS recolors this automatically
    NSColor *lockColor = isLocked ? [NSColor colorWithCalibratedRed:0.8 green:0.15 blue:0.15 alpha:1.0] : fg;

    // Keyboard outline
    NSBezierPath *kb = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 5, 13, 8) xRadius:2 yRadius:2];
    [kb setLineWidth:1.0];
    [fg setStroke];
    [kb stroke];

    // Key dots (two rows)
    [fg setFill];
    CGFloat rowY1 = 11.0, rowY2 = 8.5;
    CGFloat xs[4] = {3.5, 6.0, 8.5, 11.0};
    for (int i = 0; i < 4; i++) {
        NSBezierPath *dot1 = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(xs[i]-0.4, rowY1-0.4, 0.8, 0.8)];
        [dot1 fill];
        NSBezierPath *dot2 = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(xs[i]-0.4, rowY2-0.4, 0.8, 0.8)];
        [dot2 fill];
    }
    // Spacebar
    NSBezierPath *space = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3.5, 6.0, 8.0, 1.2) xRadius:0.5 yRadius:0.5];
    [space fill];

    // Lock badge, bottom-right, in front
    [lockColor setFill];
    [lockColor setStroke];
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(10, 0, 7, 6) xRadius:1.2 yRadius:1.2];
    [body fill];

    NSBezierPath *shackle = [NSBezierPath bezierPath];
    [shackle appendBezierPathWithArcWithCenter:NSMakePoint(13.5, 6.5) radius:2.2 startAngle:20 endAngle:160];
    [shackle setLineWidth:1.2];
    [shackle stroke];

    // Keyhole
    [[NSColor whiteColor] setFill];
    NSBezierPath *hole = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(12.9, 2.2, 1.2, 1.2)];
    [hole fill];

    [img unlockFocus];
    [img setTemplate:!isLocked]; // locked state uses real red, so don't let the OS recolor it away
    return img;
}

@implementation KlockController

- (instancetype)init {
    self = [super init];
    if (self) {
        _iconUnlocked = DrawTrayIcon(NO);
        _iconLocked = DrawTrayIcon(YES);

        _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        _statusItem.button.image = _iconUnlocked;

        NSMenu *menu = [[NSMenu alloc] init];
        _permissionItem = [[NSMenuItem alloc] initWithTitle:@"Permission needed - click to fix"
                                                      action:@selector(openPermissionSettings)
                                               keyEquivalent:@""];
        _permissionItem.target = self;
        _permissionItem.hidden = YES;
        [menu addItem:_permissionItem];

        _toggleItem = [[NSMenuItem alloc] initWithTitle:@"Lock (Cmd+Shift+X)"
                                                  action:@selector(toggleLock)
                                           keyEquivalent:@""];
        _toggleItem.target = self;
        [menu addItem:_toggleItem];
        [menu addItem:[NSMenuItem separatorItem]];

        _startupItem = [[NSMenuItem alloc] initWithTitle:@"Start at login"
                                                    action:@selector(toggleStartup)
                                             keyEquivalent:@""];
        _startupItem.target = self;
        if (@available(macOS 13.0, *)) {
            _startupItem.state = (SMAppService.mainAppService.status == SMAppServiceStatusEnabled)
                                  ? NSControlStateValueOn : NSControlStateValueOff;
        } else {
            _startupItem.enabled = NO; // SMAppService needs macOS 13+
        }
        [menu addItem:_startupItem];

        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        [menu addItem:quitItem];
        _statusItem.menu = menu;
    }
    return self;
}

- (void)updateIcon {
    self.statusItem.button.image = locked ? self.iconLocked : self.iconUnlocked;
    self.toggleItem.title = locked ? @"Unlock (Cmd+Shift+X)" : @"Lock (Cmd+Shift+X)";
}

- (void)setPermissionMissing:(BOOL)missing {
    self.permissionItem.hidden = !missing;
    self.toggleItem.enabled = !missing;
}

// If Klock is already listed but does nothing, the grant is stale (e.g. after an update): remove it with "-", add it again.
- (void)openPermissionSettings {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

- (void)toggleLock {
    locked = !locked;
    [self updateIcon];
}

- (void)toggleStartup {
    if (@available(macOS 13.0, *)) {
        NSError *error = nil;
        BOOL currentlyEnabled = (SMAppService.mainAppService.status == SMAppServiceStatusEnabled);
        BOOL ok;
        if (currentlyEnabled) {
            ok = [SMAppService.mainAppService unregisterAndReturnError:&error];
        } else {
            ok = [SMAppService.mainAppService registerAndReturnError:&error];
        }
        if (!ok) {
            NSLog(@"Failed to toggle login item: %@", error);
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Couldn't update login item";
            alert.informativeText = error.localizedDescription ?: @"Unknown error.";
            [alert runModal];
            return;
        }
        self.startupItem.state = currentlyEnabled ? NSControlStateValueOff : NSControlStateValueOn;
    }
}

@end

static KlockController *controller = nil;

CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(eventTap, true);
        return event;
    }

    if (type == kCGEventKeyDown) {
        CGKeyCode keycode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        CGEventFlags flags = CGEventGetFlags(event);
        bool cmd = flags & kCGEventFlagMaskCommand;
        bool shift = flags & kCGEventFlagMaskShift;

        if (cmd && shift && keycode == kVK_ANSI_X_CODE) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [controller toggleLock];
            });
            return NULL; // swallow the toggle combo
        }
    }

    if (locked) {
        if (type == kCGEventKeyDown || type == kCGEventKeyUp || type == kCGEventFlagsChanged) {
            return NULL;
        }
    }
    return event;
}

// Creates the event tap if we don't have one yet. Returns false while permission is missing.
static bool StartEventTap() {
    if (eventTap) return true;
    CGEventMask mask = (1 << kCGEventKeyDown) | (1 << kCGEventKeyUp) | (1 << kCGEventFlagsChanged);
    eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                 mask, eventCallback, NULL);
    if (!eventTap) return false;

    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);
    return true;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory]; // no Dock icon, menu bar only

        controller = [[KlockController alloc] init];

        // Ask for Accessibility up front (shows the system prompt), then keep the menu bar icon alive
        // and retry until access is granted, so there is no silent exit and no relaunch needed.
        NSDictionary *opts = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @YES };
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);

        if (!StartEventTap()) {
            NSLog(@"Event tap not available yet. Waiting for Accessibility permission.");
            [controller setPermissionMissing:YES];
            controller.retryTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *t) {
                if (StartEventTap()) {
                    [t invalidate];
                    [controller setPermissionMissing:NO];
                }
            }];
        }

        [app run];
    }
    return 0;
}
