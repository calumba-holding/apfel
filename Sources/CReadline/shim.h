#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <readline/readline.h>
#include <readline/history.h>

static inline FILE *apfel_get_rl_outstream(void) {
    return rl_outstream;
}

static inline void apfel_set_rl_outstream(FILE *stream) {
    rl_outstream = stream;
}

static inline FILE *apfel_get_rl_instream(void) {
    return rl_instream;
}

static inline void apfel_set_rl_instream(FILE *stream) {
    rl_instream = stream;
}

static volatile sig_atomic_t apfel_sigint_reset_stdout = 0;

static inline void apfel_block_sigint(void) {
    sigset_t blocked;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGINT);
    pthread_sigmask(SIG_BLOCK, &blocked, NULL);
}

static void apfel_sigint_exit_handler(int sig) {
    (void)sig;

    static const char reset[] = "\033[0m";
    static const char newline[] = "\n";

    if (apfel_sigint_reset_stdout) {
        (void)write(STDOUT_FILENO, reset, sizeof(reset) - 1);
    }
    (void)write(STDERR_FILENO, newline, sizeof(newline) - 1);
    _exit(130);
}

/// Install a signal-safe SIGINT handler that exits immediately with code 130.
static inline void apfel_install_sigint_exit_handler(int resetStdout) {
    struct sigaction sa;
    sigset_t unblock;
    sigemptyset(&sa.sa_mask);
    sa.sa_handler = apfel_sigint_exit_handler;
    sa.sa_flags = 0;

    apfel_sigint_reset_stdout = resetStdout ? 1 : 0;
    sigaction(SIGINT, &sa, NULL);

    sigemptyset(&unblock);
    sigaddset(&unblock, SIGINT);
    pthread_sigmask(SIG_UNBLOCK, &unblock, NULL);
}

/// Read a line with SIGINT unblocked and a C-level exit handler installed.
/// Some runtime/model setup can leave SIGINT masked before chat input begins.
static inline char *apfel_readline_interruptible(const char *prompt) {
    struct sigaction sa;
    struct sigaction previous;
    sigset_t unblock;
    sigset_t previous_mask;
    char *line;

    apfel_sigint_reset_stdout = isatty(STDOUT_FILENO) != 0;

    sigemptyset(&sa.sa_mask);
    sa.sa_handler = apfel_sigint_exit_handler;
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, &previous);

    sigemptyset(&unblock);
    sigaddset(&unblock, SIGINT);
    pthread_sigmask(SIG_UNBLOCK, &unblock, &previous_mask);

    line = readline(prompt);
    pthread_sigmask(SIG_SETMASK, &previous_mask, NULL);
    sigaction(SIGINT, &previous, NULL);
    return line;
}
