# macOS Tahoe window corner radius: findings

**Goal:** make macOS Tahoe window corners sharp (radius 0) system-wide.
**Result:** this works with two global user defaults and needs no SIP change. A value of `0` is ignored, so `0.01` is used.
**Date:** 2026-10-16

## Environment

| Item | Value |
|---|---|
| macOS | 26.6.2 (build 25G83) |
| Architecture | arm64 (arm64e shared cache) |
| SIP | Enabled |
| AppKit location | dyld shared cache only (`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e*`) |

## TL;DR

```bash
# Apply (affects every AppKit app launched afterwards)
defaults write -g NSConvolutionOverride1 -float 0.01   # normal windows, sheets, alerts
defaults write -g NSConvolutionOverride2 -float 0.01   # utility windows / panels

# Activate: relaunch apps (killall Finder for Finder), or log out and back in

# Revert
defaults delete -g NSConvolutionOverride1
defaults delete -g NSConvolutionOverride2
```

## How the corner radius is chosen

### Call chain (observed via disassembly)

```
-[NSWindow _cornerRadius]
  ├─ if a per-window radius was set via -[NSWindow _setCornerRadius:] → return that associated value
  └─ else → -[NSThemeFrame _cornerRadius]
              ├─ window is in full screen → 0
              └─ else → -[NSThemeFrame _getCachedWindowCornerRadius]
                          ├─ cached → return cache
                          ├─ r = -[NSThemeFrame _convolutionOverride]      ← user-defaults override
                          ├─ r != 0 → use r
                          ├─ Solarium (Liquid Glass) appearance → hard-coded table (below)
                          └─ else → +[NSThemeFrame _cornerRadiusForWindowType:window:] (CoreUI, pre-Tahoe look)
```

If `-[NSWindow _cornerRadius]` returns 0 and `_shouldGetCornerMaskFromVisualEffectView` is true, the window uses the visual effect view's `_effectiveMaskCornerRadius` instead.

### `-[NSThemeFrame _getCachedWindowCornerRadius]` (reconstructed from arm64e disassembly)

```objc
double -[NSThemeFrame _getCachedWindowCornerRadius] {
    if (self->_flags.hasCachedCornerRadius) return self->_cachedCornerRadius;

    double r = [self _convolutionOverride];
    if (r == 0.0) {                                  // fcmp d0, #0.0 ; b.ne → store
        if ([self _hasSolariumAppearance]) {
            if (([self _effectiveStyleMask] & 0x41) == 0) {
                r = 0;                               // not titled → square
            } else {
                NSWindow *w = [self window];
                if ([w _isUtilityWindow])            r = 15;
                else if ([w isSheet])                r = 26;
                else if ([w _isAlertWindow])         r = 26;
                else {
                    NSToolbar *tb = [w toolbar];
                    NSInteger style = [w _effectiveToolbarStyle];
                    r = 16;
                    if (tb && [tb isVisible] && !(style == 1 || style == 2))
                        r = (style == 4 /* unifiedCompact */) ? 20 : 26;
                }
            }
        } else {
            r = [NSThemeFrame _cornerRadiusForWindowType:[self _cuiWindowType] window:_window];
        }
    }
    self->_cachedCornerRadius = r;
    self->_flags.hasCachedCornerRadius = YES;
    return r;
}
```

The radius table for Tahoe (Solarium) windows:

| Window kind | Radius (pt) |
|---|---|
| Titled, no visible toolbar | 16 |
| Toolbar style `expanded` (1) or `preference` (2) | 16 |
| Toolbar style `unified` (3) or `automatic` (0) | 26 |
| Toolbar style `unifiedCompact` (4) | 20 |
| Sheet | 26 |
| Alert | 26 |
| Utility window | 15 |
| Not titled (`styleMask & 0x41 == 0`) | 0 |

The 16, 26 and 15 values were confirmed at runtime. The toolbar-style split is inferred from the `sub x8, style, #3 ; cmn x8, #3 ; b.hi` sequence.

### `-[NSThemeFrame _convolutionOverride]`

```objc
double -[NSThemeFrame _convolutionOverride] {
    if ([_window _isUtilityWindow])
        return _NSGetCGFloatAppConfig(@"NSConvolutionOverride2", 0.0, &cacheFlag2, &cacheValue2, NULL);
    return _NSGetCGFloatAppConfig(@"NSConvolutionOverride1", 0.0, &cacheFlag1, &cacheValue1, NULL);
}
```

Each value is cached once per process (`_MergedGlobals.78`), so a running app does not pick up changes until it is relaunched.

### `_NSGetCGFloatAppConfig(key, default, cacheFlag, cacheValue, fallbackBlock)`

- Returns the cached value if `cacheFlag` is already set.
- Otherwise it reads `[[NSUserDefaults standardUserDefaults] objectForKey:key]`, then `floatForKey:`. The standard search list includes `NSGlobalDomain`, so `defaults write -g` applies to every app. A per-app domain or a launch argument (`-NSConvolutionOverride1 0.01`) also works.
- If the key is unset, it calls `fallbackBlock` when one is given, or else uses `default`.
- Side effects when the value differs from the default:
  - It `NSLog`s `key=value` when the value comes from a volatile domain (for example the argument domain) or when `NSLogUnusualAppConfig` is set.
  - It calls `_NSNoteNonStandardBehaviorFloat`.
  - It calls `_NSSendNonstandardAppConfigurationToAnalytics`, but only when `|value - default|` is at or above a threshold constant whose value was not read.

### How the radius reaches WindowServer: `-[NSThemeFrame _cornerMask]`

- In full screen it returns `nil`.
- Under Solarium:
  1. `r = _cornerRadius`.
  2. `inset = ceil(r × cornerCurveExpansionFactor)`, where the factor is for the continuous curve.
  3. It builds a resizable mask `NSImage` of size `2·inset + 1`, with `capInsets = inset`, `_setHasTrivialEdges:YES` and `resizingMode = stretch`. The image is drawn by the block in `+[NSThemeFrame _resizableContinuousCornerMaskImageForCornerRadius:]`.
- Without Solarium it uses `_cornerMaskImageForWindowType:window:` (CoreUI).

Observed mask sizes, which match the formula with a factor of about 1.53:

| Radius | Mask image | capInsets |
|---|---|---|
| 16 (default) | 51 × 51 | 25 |
| 26 (default, toolbar) | 81 × 81 | 40 |
| 0.01 (override) | 3 × 3 | 1 |

### Pre-Tahoe path: `+[NSThemeFrame _cornerRadiusForWindowType:window:]`

- It asserts if called while Solarium is active. The message is `"Unexpected use of _cornerRadiusForWindowType:window:"` at NSThemeFrame.m:1283.
- Otherwise it queries CoreUI through `-[NSAppearance _copyMeasurements:context:options:requestedMeasurements:]`, keyed by window type, active state and window.
- If no measurement comes back, it falls back to `capInsets.left` of the CoreUI corner mask image.

### Per-window private API: `-[NSWindow _setCornerRadius:]`

- If `r > 0`, it sets a flag bit and stores the value as an associated object.
- If `r <= 0`, it clears both.
- In either case it then calls `_cornerMaskChanged` and `[[self _themeFrame] _invalidateCornerConfiguration]`.
- This only applies to code running inside the app, for example the user's own apps. Because `r <= 0` clears the override, this API cannot force a radius of 0 either.

## Why `0.01` and not `0`

`_getCachedWindowCornerRadius` only uses the override when it is non-zero. A value of `0` falls through to the default table. With `0.01`, the mask becomes 3×3 with a 1-unit cap inset, so the corner is effectively square.

Negative values would also pass the `!= 0` check. They were not tested and should be avoided, because they would feed a negative radius into CGPath and image drawing.

## Verification

All verification ran in self-built probe apps. No system process was modified for testing.

| Check | Default | With `NSConvolutionOverride1 = 0.01` |
|---|---|---|
| `-[NSWindow _cornerRadius]`, plain titled | 16 | 0.01 |
| `-[NSWindow _cornerRadius]`, titled + toolbar | 26 | 0.01 |
| `_cornerMask`, plain | NSImage 51×51, inset 25 | NSImage 3×3, inset 1 |
| `_cornerMask`, toolbar | NSImage 81×81, inset 40 | NSImage 3×3, inset 1 |

After `defaults write -g`, a freshly launched probe with no launch arguments reported `0.01` and a 3×3 mask. That confirms the value is read from the global domain.

A visual screenshot was **not** captured, because the terminal has no Screen Recording permission (`screencapture` reported "could not create image from rect").

Reproduction probe:

```objc
// clang -fobjc-arc -framework Cocoa mask.m -o mask && ./mask [-NSConvolutionOverride1 0.01]
#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import <objc/runtime.h>
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    for (int tb = 0; tb < 2; tb++) {
      NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,300,200)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
      if (tb) w.toolbar = [[NSToolbar alloc] initWithIdentifier:@"t"];
      [w orderFront:nil];
      id mask = ((id (*)(id, SEL))objc_msgSend)(w, sel_registerName("_cornerMask"));
      double r = ((double (*)(id, SEL))objc_msgSend)(w, sel_registerName("_cornerRadius"));
      printf("%s: _cornerRadius=%g mask=%s\n", tb ? "toolbar" : "plain", r,
             NSStringFromSize([(NSImage *)mask size]).UTF8String);
      [w close];
    }
  }
}
```

## Caveats

- **Relaunch is required.** The value is cached per process, and the radius is cached per theme frame.
- **Inner content may stay rounded.** Tahoe glass elements inside the window are not covered. For example, sidebar glass has its own minimum (`NSSplitViewItemGlassMinimumCornerRadius`), and other content uses concentric or capsule corner styles. This override changes only the outer window shape.
- **Some apps are not affected.** These include apps that draw their own frame (frameless Electron windows, Chrome), apps that call `_setCornerRadius:`, and non-AppKit windows.
- **Full-screen windows are unchanged.** They already use radius 0 and a `nil` mask.
- **AppKit reports the setting to Apple.** It flags the value as a non-standard app configuration (`_NSSendNonstandardAppConfigurationToAnalytics`), subject to the user's analytics-sharing settings.
- **The key is private and undocumented.** A future macOS update may rename or remove it.

## Open questions (not investigated)

- `NSWindowPreferCornerRadiusAndPath`: a default key found in the shared cache. It is unset on this system, and where it is used was not traced.
- `NSShouldInitializeCornerRadius`: found as a string; its purpose is unknown.
- SkyLight/WindowServer symbols `SetWindowCornerRadius`, `SetWindowSystemCornerRadius` and `ClearWindowSystemCornerRadius`: the server-side handling was not analyzed. The AppKit-side override was enough.
- The value of the analytics threshold constant.
- The exact `cornerCurveExpansionFactor` value. Measurements bound it to (1.5, 1.538], which is consistent with Core Animation's continuous-corner factor of about 1.5287.

## Method and tooling

1. **REA.** The REA `binary_session` reported Hopper available, and Ghidra and IDA not configured.
2. **Why AppKit was not loaded into Hopper.** AppKit exists only inside the dyld shared cache. `dyld_info -objc` refuses to print live ObjC info for cache images. Extracting the full cache with Xcode's `dsc_extractor` was ruled out with 19 GB free on disk. Extracting a single image needs `ipsw`, and installing it required trusting the third-party Homebrew tap `blacktop/tap`, which was not done. The tap was added during the attempt; remove it with `brew untap blacktop/tap` if unwanted.
3. **String scan.** A scan of the arm64e cache sub-files for `*[Cc]orner*` identifiers found `_cornerRadiusForWindowType`, `_getCachedWindowCornerRadius`, `NSCGSWindowCornerRadiusMask`, `NSWindowPreferCornerRadiusAndPath` and the SkyLight setters.
4. **Runtime enumeration.** A self-built probe app (`objc_copyClassList` / `class_copyMethodList`) listed every AppKit selector containing `cornerradius`, `cornermask` or `cornerpath`, with type encodings and IMP addresses. It also printed the live radius values.
5. **Disassembly.** `lldb --batch` was run against the probe, ad-hoc signed with `com.apple.security.get-task-allow`. It disassembled `-[NSThemeFrame _getCachedWindowCornerRadius]`, `-[NSThemeFrame _convolutionOverride]`, `_NSGetCGFloatAppConfig`, `-[NSThemeFrame _cornerRadius]`, `-[NSThemeFrame _cornerMask]`, `+[NSThemeFrame _cornerRadiusForWindowType:window:]`, `-[NSWindow _cornerRadius]` and `-[NSWindow _setCornerRadius:]`. Addresses in that output depend on the current boot's shared-cache slide and are not stable.
6. **Validation.** The override was first tested through the probe's argument domain, then applied globally and re-verified in a fresh process.

The pseudocode in this document is reconstructed from disassembly; it is an interpretation, not Apple source.
