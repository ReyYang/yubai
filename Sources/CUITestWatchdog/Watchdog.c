#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <dlfcn.h>
#endif
#if DEBUG && ((defined(__APPLE__) && TARGET_OS_IOS && TARGET_OS_SIMULATOR) || defined(YUBAI_WATCHDOG_TEST))
#include "CUITestWatchdog.h"
#include <dispatch/dispatch.h>
#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#include <unistd.h>

// The signal handler touches only lock-free atomics and this fixed buffer.
// Prewarm the unwinder before installing it; symbolication/formatting/allocation
// and file access belong exclusively to the watchdog pthread.
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Signal state must be lock free");
static void *main_frames[128];
static int main_frame_count;
static _Atomic int capture_state; // 0 idle, 1 requested, 2 captured
static _Atomic int ping_pending;
static _Atomic uint64_t answered_at;
static pthread_t main_thread;
static int log_file = -1;
static pthread_mutex_t records_lock = PTHREAD_MUTEX_INITIALIZER;
static char *history, *latest_record;
static size_t history_length;

static uint64_t monotonic_ns(void) {
    struct timespec value;
    clock_gettime(CLOCK_MONOTONIC, &value);
    return (uint64_t)value.tv_sec * 1000000000 + (uint64_t)value.tv_nsec;
}
static void capture_main(int signal_number) {
    int saved_errno = errno;
    if (signal_number == SIGUSR2 && atomic_load_explicit(&capture_state, memory_order_acquire) == 1) {
        main_frame_count = backtrace(main_frames, 128);
        atomic_store_explicit(&capture_state, 2, memory_order_release);
    }
    errno = saved_errno;
}
static void answer_ping(void *unused) {
    (void)unused;
    atomic_store(&answered_at, monotonic_ns());
    atomic_store(&ping_pending, 0);
}
static void write_all(int fd, const char *value, size_t length) {
    while (fd >= 0 && length > 0) {
        ssize_t count = write(fd, value, length);
        if (count < 0 && errno == EINTR) { continue; }
        if (count <= 0) { return; }
        value += count; length -= (size_t)count;
    }
}
static void append_record(double elapsed, const char *status, int with_stack) {
    // One stack is bounded independently of the cumulative, lossless history.
    const size_t capacity = 1024 * 1024;
    char *record = malloc(capacity);
    if (!record) { return; }
    struct timespec now;
    struct tm utc;
    char stamp[32];
    clock_gettime(CLOCK_REALTIME, &now);
    gmtime_r(&now.tv_sec, &utc);
    strftime(stamp, sizeof(stamp), "%Y-%m-%dT%H:%M:%S", &utc);
    size_t used = (size_t)snprintf(record, capacity,
        "YUBAI-STALL %s.%03ldZ pid=%d stall=%.3fs %s\n", stamp, now.tv_nsec / 1000000, getpid(), elapsed, status);
    if (with_stack && atomic_load_explicit(&capture_state, memory_order_acquire) == 2) {
        char **symbols = backtrace_symbols(main_frames, main_frame_count);
        for (int i = 0; i < main_frame_count && used < capacity - 512; i++) {
            int count = snprintf(record + used, capacity - used, "  %02d %s [%p]\n", i,
                symbols ? symbols[i] : "<symbol unavailable>", main_frames[i]);
            if (count > 0) { used += (size_t)count; }
            #if defined(__APPLE__)
            // atos can recover Swift symbols (including local app frames) from
            // the matching debug dylib/dSYM using this image load address.
            Dl_info info;
            if (dladdr(main_frames[i], &info) && info.dli_fname && used < capacity - 512) {
                const char *name = strrchr(info.dli_fname, '/');
                count = snprintf(record + used, capacity - used,
                    "     image=%s load=%p pc=%p\n", name ? name + 1 : info.dli_fname, info.dli_fbase, main_frames[i]);
                if (count > 0) { used += (size_t)count; }
            }
            #endif
        }
        free(symbols);
        atomic_store_explicit(&capture_state, 0, memory_order_release);
    } else if (with_stack) {
        used += (size_t)snprintf(record + used, capacity - used,
            "  MAIN thread SIGUSR2 capture pending (signal may be masked)\n");
    }
    used = used < capacity ? used : capacity - 1;
    record[used] = '\0';
    pthread_mutex_lock(&records_lock);
    char *grown = realloc(history, history_length + used + 1);
    if (grown) {
        history = grown; memcpy(history + history_length, record, used + 1); history_length += used;
    }
    free(latest_record); latest_record = strdup(record);
    pthread_mutex_unlock(&records_lock);
    write_all(log_file, record, used);
    write_all(STDERR_FILENO, record, used);
    free(record);
}
static void request_stack(void) {
    int expected = 0;
    if (atomic_compare_exchange_strong(&capture_state, &expected, 1)) {
        if (pthread_kill(main_thread, SIGUSR2) != 0) { atomic_store(&capture_state, 0); return; }
    }
    // A blocked main thread is interrupted by the signal. Do not dispatch the
    // capture to that queue or substitute this pthread's own stack.
    for (int i = 0; i < 25 && atomic_load_explicit(&capture_state, memory_order_acquire) == 1; i++) {
        struct timespec delay = {0, 10000000}; nanosleep(&delay, NULL);
    }
}
static void *watch_main(void *unused) {
    char *path = unused;
    char *slash = strrchr(path, '/');
    if (slash) { *slash = '\0'; mkdir(path, 0700); *slash = '/'; }
    log_file = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (log_file < 0) { fprintf(stderr, "YUBAI-STALL cannot open %s: %s\n", path, strerror(errno)); }
    free(path);
    uint64_t stall_start = 0, last_report = 0;
    double recovered_length = 0;
    for (;;) {
        struct timespec interval = {1, 0};
        while (nanosleep(&interval, &interval) != 0 && errno == EINTR) {}
        uint64_t now = monotonic_ns(), answer = atomic_load(&answered_at);
        if (now - answer >= 5000000000ULL) {
            if (!stall_start) { stall_start = answer; }
            if (!last_report || now - last_report >= 5000000000ULL) {
                request_stack();
                append_record((now - stall_start) / 1e9, "MAIN thread unresponsive", 1);
                last_report = now;
            }
        } else if (stall_start) {
            // Preserve a capture delivered late, including one masked until
            // recovery, before permitting the next capture to reuse the buffer.
            recovered_length = (answer - stall_start) / 1e9;
            append_record(recovered_length, "MAIN thread recovered",
                atomic_load_explicit(&capture_state, memory_order_acquire) == 2);
            stall_start = 0; last_report = 0;
        } else if (atomic_load_explicit(&capture_state, memory_order_acquire) == 2) {
            append_record(recovered_length, "delayed MAIN stack (signal masked until after recovery)", 1);
        }
        if (!atomic_exchange(&ping_pending, 1)) { dispatch_async_f(dispatch_get_main_queue(), NULL, answer_ping); }
    }
    return NULL;
}
int yubai_stall_watchdog_start(const char *path) {
    static int started;
    if (started) { return 0; }
    #if defined(__APPLE__)
    if (!pthread_main_np()) { return EPERM; }
    #endif
    struct sigaction previous, action = {0};
    if (sigaction(SIGUSR2, NULL, &previous) != 0) { return errno; }
    if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN) { return EBUSY; }
    main_thread = pthread_self();
    // Force lazy unwind-library setup while no signal handler is active.
    backtrace(main_frames, 128);
    action.sa_handler = capture_main; action.sa_flags = SA_RESTART;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGUSR2, &action, NULL) != 0) { return errno; }
    char *owned_path = strdup(path);
    if (!owned_path) { sigaction(SIGUSR2, &previous, NULL); return ENOMEM; }
    atomic_store(&answered_at, monotonic_ns());
    pthread_t thread;
    int result = pthread_create(&thread, NULL, watch_main, owned_path);
    if (result != 0) {
        sigaction(SIGUSR2, &previous, NULL);
        free(owned_path);
        return result;
    }
    pthread_detach(thread); started = 1;
    return 0;
}
char *yubai_stall_watchdog_copy_records(int latest) {
    pthread_mutex_lock(&records_lock);
    char *copy = strdup((latest ? latest_record : history) ?: "");
    pthread_mutex_unlock(&records_lock);
    return copy;
}
#endif
