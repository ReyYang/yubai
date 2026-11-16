#ifndef YUBAI_UI_TEST_WATCHDOG_H
#define YUBAI_UI_TEST_WATCHDOG_H

// Implemented only in DEBUG simulator builds. Start on the main thread,
// after checking the explicit UI-test launch argument.
int yubai_stall_watchdog_start(const char *path);
// Caller owns the returned string (free). latest == 0 returns the full history.
char *yubai_stall_watchdog_copy_records(int latest);

#endif
