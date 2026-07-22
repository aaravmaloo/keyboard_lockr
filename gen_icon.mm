// gen_icon.mm
// Build-time helper: draws the same keyboard+lock glyph used in the menu bar,
// at app-icon resolution, and writes every PNG size iconutil needs for a .icns.
// Not shipped in the app bundle — this only runs during `make icon`.
//
// Build: clang++ -std=c++17 -fobjc-arc -framework Cocoa -o gen_icon gen_icon.mm
// Run:   ./gen_icon Klock.iconset

#import <Cocoa/Cocoa.h>

// Same design as DrawTrayIcon() in klock_mac.mm, scaled up and re-proportioned
// for a square app icon canvas instead of a thin menu bar glyph.
static NSImage* DrawAppIcon(CGFloat px) {
    NSSize size = NSMakeSize(px, px);
    NSImage *img = [[NSImage alloc] initWithSize:size];
    [img lockFocus];

    CGFloat u = px / 32.0; // unit scale, design drawn on a 32x32 grid like the tray icon

    NSColor *bg = [NSColor colorWithCalibratedWhite:0.13 alpha:1.0];
    NSBezierPath *rounded = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, px, px)
                                                              xRadius:px * 0.22
                                                              yRadius:px * 0.22];
    [bg setFill];
    [rounded fill];

    NSColor *fg = [NSColor whiteColor];
    NSColor *lockColor = [NSColor colorWithCalibratedRed:0.85 green:0.2 blue:0.2 alpha:1.0];

    // Keyboard outline, centered with margin
    NSRect kbRect = NSMakeRect(4*u, 11*u, 24*u, 14*u);
    NSBezierPath *kb = [NSBezierPath bezierPathWithRoundedRect:kbRect xRadius:2.5*u yRadius:2.5*u];
    [kb setLineWidth:1.6*u];
    [fg setStroke];
    [kb stroke];

    // Key dots, two rows
    [fg setFill];
    CGFloat rowY1 = 20.5*u, rowY2 = 16.5*u;
    CGFloat xs[6] = {8*u, 11.3*u, 14.6*u, 17.9*u, 21.2*u, 24.5*u};
    for (int i = 0; i < 6; i++) {
        NSBezierPath *d1 = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(xs[i]-0.7*u, rowY1-0.7*u, 1.4*u, 1.4*u)];
        [d1 fill];
        NSBezierPath *d2 = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(xs[i]-0.7*u, rowY2-0.7*u, 1.4*u, 1.4*u)];
        [d2 fill];
    }
    // Spacebar
    NSBezierPath *space = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(9*u, 12.5*u, 14*u, 2.2*u)
                                                            xRadius:1*u yRadius:1*u];
    [space fill];

    // Lock badge, bottom-right, drawn in front
    CGFloat lockW = 12*u, lockH = 10*u;
    NSRect lockRect = NSMakeRect(20*u, 2*u, lockW, lockH);
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:lockRect xRadius:2*u yRadius:2*u];
    [lockColor setFill];
    [body fill];

    NSBezierPath *shackle = [NSBezierPath bezierPath];
    [shackle appendBezierPathWithArcWithCenter:NSMakePoint(26*u, 12.5*u) radius:3.6*u startAngle:20 endAngle:160];
    [shackle setLineWidth:1.8*u];
    [lockColor setStroke];
    [shackle stroke];

    [[NSColor whiteColor] setFill];
    NSBezierPath *hole = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(25.2*u, 5.5*u, 1.6*u, 1.6*u)];
    [hole fill];

    [img unlockFocus];
    return img;
}

static BOOL WritePNG(NSImage *img, NSString *path, CGFloat px) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                       pixelsWide:(NSInteger)px
                       pixelsHigh:(NSInteger)px
                    bitsPerSample:8
                  samplesPerPixel:4
                         hasAlpha:YES
                         isPlanar:NO
                   colorSpaceName:NSDeviceRGBColorSpace
                      bytesPerRow:0
                     bitsPerPixel:0];
    rep.size = NSMakeSize(px, px);

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [img drawInRect:NSMakeRect(0, 0, px, px) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: gen_icon <output.iconset directory>\n");
            return 1;
        }
        NSString *iconsetPath = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:iconsetPath
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:nil];

        // (filename, pixel size) pairs iconutil expects inside a .iconset
        NSArray<NSArray *> *sizes = @[
            @[@"icon_16x16.png", @16],
            @[@"icon_16x16@2x.png", @32],
            @[@"icon_32x32.png", @32],
            @[@"icon_32x32@2x.png", @64],
            @[@"icon_128x128.png", @128],
            @[@"icon_128x128@2x.png", @256],
            @[@"icon_256x256.png", @256],
            @[@"icon_256x256@2x.png", @512],
            @[@"icon_512x512.png", @512],
            @[@"icon_512x512@2x.png", @1024],
        ];

        for (NSArray *entry in sizes) {
            NSString *name = entry[0];
            CGFloat px = [entry[1] doubleValue];
            NSImage *icon = DrawAppIcon(px);
            NSString *outPath = [iconsetPath stringByAppendingPathComponent:name];
            if (!WritePNG(icon, outPath, px)) {
                fprintf(stderr, "failed to write %s\n", outPath.UTF8String);
                return 1;
            }
        }
        printf("wrote %s\n", iconsetPath.UTF8String);
    }
    return 0;
}
