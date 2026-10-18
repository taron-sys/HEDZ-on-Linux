/* LD_PRELOAD shim for the game under gamescope. Wine's X11 driver passes unexpected X errors to Xlib's *default*
 * handler, which exit()s: "X Error of failed request: BadWindow ... X_UnmapWindow" killed the game on New Game.
 * BadWindow is now ignored (XERR_FATAL=1 restores the old behaviour); other errors print pid/exe/backtrace first. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <execinfo.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <X11/Xlib.h>

int _XDefaultError(Display *dpy, XErrorEvent *ev)
{
    static int (*real)(Display *, XErrorEvent *);
    void *bt[64]; int n; char exe[256] = "?"; ssize_t l;
    l = readlink("/proc/self/exe", exe, sizeof(exe) - 1); if (l > 0) exe[l] = 0;
    fprintf(stderr, "[xerrbt] pid %d exe %s: X error code %d request %d minor %d resource 0x%lx serial %lu\n",
            getpid(), exe, ev->error_code, ev->request_code, ev->minor_code, ev->resourceid, ev->serial);
    if (ev->error_code == BadWindow && !getenv("XERR_FATAL")) {
        /* Wine's X11 driver unmaps a window that the compositor (gamescope/Xwayland) already destroyed; Xlib's
         * default handler would exit() the whole game. Ignore it. */
        fprintf(stderr, "[xerrbt] ignoring BadWindow (request %d resource 0x%lx)\n", ev->request_code, ev->resourceid);
        return 0;
    }
    n = backtrace(bt, 64); backtrace_symbols_fd(bt, n, 2);
    if (!real) real = dlsym(RTLD_NEXT, "_XDefaultError");
    return real(dpy, ev);
}

/* the default handler ends in exit(1): catch that too in case _XDefaultError is bound inside libX11 */
void exit(int status)
{
    static void (*real)(int) __attribute__((noreturn));
    void *bt[64]; int n;
    if (!real) real = dlsym(RTLD_NEXT, "exit");
    if (status != 0) {
        fprintf(stderr, "[xerrbt] pid %d exit(%d) called from:\n", getpid(), status);
        n = backtrace(bt, 64); backtrace_symbols_fd(bt, n, 2);
    }
    real(status);
    __builtin_unreachable();
}
