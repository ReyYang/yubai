#ifndef YUBAI_STALL_SOURCE_H
#define YUBAI_STALL_SOURCE_H
#include <stddef.h>
#include <string.h>
#define YUBAI_STALL_MAX_FRAMES 512

// Classify the captured call chain, never the test phase or elapsed time.
// A mixed stack with actual application work still belongs to the app.
static inline const char *yubai_stall_source(char *const *symbols, size_t count) {
    int audit = 0, snapshot = 0, app = 0;
    if (!symbols || !count) { return "unknown"; }
    for (size_t i = 0; i < count; i++) {
        const char *s = symbols[i];
        if (strstr(s, "_axAudit") || strstr(s, "AccessibilityAudit") || strstr(s, "_accessibilityAudit")) { audit = 1; }
        if (strstr(s, "XCTAutomationSupport") || strstr(s, "XCTPerformOnMainRunLoop") ||
            strstr(s, "matchingSnapshotsInSnapshotTree")) { snapshot = 1; }
        if (strstr(s, "Yubai") && !strstr(s, "capture_main") &&
            !strstr(s, "$s5Yubai0A3AppV5$main") && !strstr(s, "__debug_main_executable_dylib_entry_point")) {
            // SwiftUI-generated View witnesses contain no app implementation.
            // Runtime metadata/type instantiation is reported as system work.
            if (!(strstr(s, "SwiftUI4View") && strstr(s, "_make") && strstr(s, "TW"))) { app = 1; }
        }
    }
    return app ? "app" : audit ? "xctest-audit" : snapshot ? "xctest-snapshot" : count >= YUBAI_STALL_MAX_FRAMES ? "unknown" : "system";
}
#endif
