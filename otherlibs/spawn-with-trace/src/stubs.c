/*
 * spawn_with_trace - Spawn a process with syscall tracing using seccomp-bpf + ptrace
 *
 * This library spawns a child process and traces all openat syscalls,
 * collecting the file paths that the process attempts to open.
 */

#define _GNU_SOURCE

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>
#include <caml/unixsupport.h>

#if defined(__linux__) && (defined(__x86_64__) || defined(__aarch64__))
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/ptrace.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __x86_64__
#define AUDIT_ARCH_CURRENT AUDIT_ARCH_X86_64
#define SYSCALL_NR_OPENAT __NR_openat
#define REG_SYSCALL_NR(regs) ((regs).orig_rax)
#define REG_ARG1(regs) ((regs).rsi)  /* pathname for openat (dirfd=rdi, pathname=rsi) */
#elif defined(__aarch64__)
#define AUDIT_ARCH_CURRENT AUDIT_ARCH_AARCH64
#define SYSCALL_NR_OPENAT __NR_openat
#define REG_SYSCALL_NR(regs) ((regs).regs[8])
#define REG_ARG1(regs) ((regs).regs[1])  /* pathname for openat */
#endif

/* Maximum paths to track */
#define MAX_PATHS 65536

/* Path storage */
struct path_list {
    char **paths;
    size_t count;
    size_t capacity;
};

static void path_list_init(struct path_list *list) {
    list->paths = NULL;
    list->count = 0;
    list->capacity = 0;
}

static void path_list_free(struct path_list *list) {
    for (size_t i = 0; i < list->count; i++) {
        free(list->paths[i]);
    }
    free(list->paths);
    path_list_init(list);
}

static int path_list_add(struct path_list *list, const char *path) {
    if (list->count >= MAX_PATHS) return 0;

    if (list->count >= list->capacity) {
        size_t new_cap = list->capacity == 0 ? 256 : list->capacity * 2;
        if (new_cap > MAX_PATHS) new_cap = MAX_PATHS;
        char **new_paths = realloc(list->paths, new_cap * sizeof(char *));
        if (!new_paths) return -1;
        list->paths = new_paths;
        list->capacity = new_cap;
    }

    list->paths[list->count] = strdup(path);
    if (!list->paths[list->count]) return -1;
    list->count++;
    return 0;
}

/* Read a string from tracee's memory using process_vm_readv */
static int read_string_from_tracee(pid_t pid, unsigned long addr, char *buf, size_t buflen) {
    if (addr == 0 || buflen == 0) return -1;

    struct iovec local = { .iov_base = buf, .iov_len = buflen };
    struct iovec remote = { .iov_base = (void *)addr, .iov_len = buflen };

    ssize_t n = process_vm_readv(pid, &local, 1, &remote, 1, 0);
    if (n <= 0) return -1;

    /* Ensure null termination */
    buf[buflen - 1] = '\0';

    /* Find actual string length */
    size_t len = strnlen(buf, n);
    if (len == (size_t)n && len < buflen) {
        /* String might be truncated, need to check if there's a null */
        buf[n] = '\0';
    }

    return 0;
}

/* Install seccomp-bpf filter to trace openat syscalls */
static int install_seccomp_filter(void) {
    struct sock_filter filter[] = {
        /* Load architecture */
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
        /* Check architecture */
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_CURRENT, 1, 0),
        /* Wrong arch: allow */
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        /* Load syscall number */
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        /* Check for openat */
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYSCALL_NR_OPENAT, 0, 1),
        /* openat: trace */
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_TRACE),
        /* Default: allow */
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };

    struct sock_fprog prog = {
        .len = sizeof(filter) / sizeof(filter[0]),
        .filter = filter,
    };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == -1) {
        return -1;
    }

    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog) == -1) {
        return -1;
    }

    return 0;
}

/* Child process setup */
static void child_setup_and_exec(const char *prog, char *const argv[], char *const envp[],
                                  const char *cwd, int stdin_fd, int stdout_fd, int stderr_fd) {
    /* Change directory if specified */
    if (cwd && chdir(cwd) == -1) {
        _exit(127);
    }

    /* Set up I/O redirections */
    if (stdin_fd >= 0 && stdin_fd != STDIN_FILENO) {
        if (dup2(stdin_fd, STDIN_FILENO) == -1) _exit(127);
        close(stdin_fd);
    }
    if (stdout_fd >= 0 && stdout_fd != STDOUT_FILENO) {
        if (dup2(stdout_fd, STDOUT_FILENO) == -1) _exit(127);
        close(stdout_fd);
    }
    if (stderr_fd >= 0 && stderr_fd != STDERR_FILENO) {
        if (dup2(stderr_fd, STDERR_FILENO) == -1) _exit(127);
        close(stderr_fd);
    }

    /* Request to be traced */
    if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) == -1) {
        _exit(127);
    }

    /* Stop to let parent set up ptrace options */
    raise(SIGSTOP);

    /* Install seccomp filter */
    if (install_seccomp_filter() == -1) {
        _exit(127);
    }

    /* Execute the program */
    execvpe(prog, argv, envp);
    _exit(127);
}

/* ptrace options to trace all descendants */
#define PTRACE_OPTIONS (PTRACE_O_TRACESECCOMP | PTRACE_O_EXITKILL | \
                        PTRACE_O_TRACEFORK | PTRACE_O_TRACEVFORK | \
                        PTRACE_O_TRACECLONE)

/* Get the current working directory of a process */
static int get_proc_cwd(pid_t pid, char *buf, size_t buflen) {
    char proc_path[64];
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/cwd", pid);
    ssize_t len = readlink(proc_path, buf, buflen - 1);
    if (len == -1) return -1;
    buf[len] = '\0';
    return 0;
}

/* Resolve a path to absolute, using process cwd for relative paths */
static void resolve_and_add_path(pid_t pid, const char *path, struct path_list *paths) {
    char combined[PATH_MAX];
    char resolved[PATH_MAX];
    const char *to_resolve;

    if (path[0] == '/') {
        /* Already absolute */
        to_resolve = path;
    } else {
        /* Relative path - combine with process cwd */
        char cwd[PATH_MAX];
        if (get_proc_cwd(pid, cwd, sizeof(cwd)) == 0) {
            snprintf(combined, sizeof(combined), "%s/%s", cwd, path);
            to_resolve = combined;
        } else {
            /* Can't get cwd, add as-is */
            path_list_add(paths, path);
            return;
        }
    }

    /* Try to normalize with realpath (resolves .., symlinks, etc.) */
    if (realpath(to_resolve, resolved) != NULL) {
        path_list_add(paths, resolved);
    } else {
        /* File doesn't exist yet or other error - add combined path */
        path_list_add(paths, to_resolve);
    }
}

/* Handle a seccomp event for a tracee */
static void handle_seccomp_event(pid_t pid, struct path_list *paths) {
#ifdef __x86_64__
    struct user_regs_struct regs;
    if (ptrace(PTRACE_GETREGS, pid, NULL, &regs) == 0) {
        if (REG_SYSCALL_NR(regs) == SYSCALL_NR_OPENAT) {
            unsigned long pathname_addr = REG_ARG1(regs);
            char path_buf[PATH_MAX];
            if (read_string_from_tracee(pid, pathname_addr, path_buf, sizeof(path_buf)) == 0) {
                resolve_and_add_path(pid, path_buf, paths);
            }
        }
    }
#elif defined(__aarch64__)
    struct user_pt_regs regs;
    struct iovec iov = { .iov_base = &regs, .iov_len = sizeof(regs) };
    if (ptrace(PTRACE_GETREGSET, pid, NT_PRSTATUS, &iov) == 0) {
        if (REG_SYSCALL_NR(regs) == SYSCALL_NR_OPENAT) {
            unsigned long pathname_addr = REG_ARG1(regs);
            char path_buf[PATH_MAX];
            if (read_string_from_tracee(pid, pathname_addr, path_buf, sizeof(path_buf)) == 0) {
                resolve_and_add_path(pid, path_buf, paths);
            }
        }
    }
#endif
}

/* Trace the child process and all its descendants */
static int trace_child(pid_t root_child, struct path_list *paths, int *exit_status) {
    int status;
    int num_tracees = 1;  /* Start with root child */

    /* Wait for initial SIGSTOP from root child */
    if (waitpid(root_child, &status, 0) == -1) {
        return -1;
    }

    if (!WIFSTOPPED(status) || WSTOPSIG(status) != SIGSTOP) {
        return -1;
    }

    /* Set ptrace options on root child */
    if (ptrace(PTRACE_SETOPTIONS, root_child, NULL, PTRACE_OPTIONS) == -1) {
        return -1;
    }

    /* Resume root child */
    if (ptrace(PTRACE_CONT, root_child, NULL, 0) == -1) {
        return -1;
    }

    /* Main tracing loop - wait for any tracee */
    while (num_tracees > 0) {
        pid_t pid = waitpid(-1, &status, __WALL);
        if (pid == -1) {
            if (errno == ECHILD) break;
            return -1;
        }

        if (WIFEXITED(status) || WIFSIGNALED(status)) {
            /* Tracee exited */
            num_tracees--;
            if (pid == root_child) {
                *exit_status = status;
            }
            continue;
        }

        if (WIFSTOPPED(status)) {
            int event = (status >> 16) & 0xff;
            int sig = WSTOPSIG(status);

            if (event == PTRACE_EVENT_SECCOMP) {
                /* SECCOMP event - syscall entry */
                handle_seccomp_event(pid, paths);
            } else if (event == PTRACE_EVENT_FORK ||
                       event == PTRACE_EVENT_VFORK ||
                       event == PTRACE_EVENT_CLONE) {
                /* New child created - it will be auto-traced due to options */
                num_tracees++;
            } else if (sig != SIGTRAP && sig != (SIGTRAP | 0x80)) {
                /* Deliver other signals to tracee */
                if (ptrace(PTRACE_CONT, pid, NULL, sig) == -1) {
                    if (errno != ESRCH) return -1;
                }
                continue;
            }
        }

        /* Continue execution */
        if (ptrace(PTRACE_CONT, pid, NULL, 0) == -1) {
            if (errno != ESRCH) return -1;
        }
    }

    return 0;
}

/* Convert string list to OCaml list */
static value paths_to_ocaml_list(struct path_list *paths) {
    CAMLparam0();
    CAMLlocal3(list, cons, str);

    list = Val_emptylist;

    /* Build list in reverse (to get correct order) */
    for (size_t i = paths->count; i > 0; i--) {
        str = caml_copy_string(paths->paths[i - 1]);
        cons = caml_alloc_small(2, Tag_cons);
        Field(cons, 0) = str;
        Field(cons, 1) = list;
        list = cons;
    }

    CAMLreturn(list);
}

/* Convert Unix.process_status to OCaml value */
static value make_process_status(int status) {
    CAMLparam0();
    CAMLlocal1(result);

    if (WIFEXITED(status)) {
        /* WEXITED of int */
        result = caml_alloc_small(1, 0);
        Field(result, 0) = Val_int(WEXITSTATUS(status));
    } else if (WIFSIGNALED(status)) {
        /* WSIGNALED of int */
        result = caml_alloc_small(1, 1);
        Field(result, 0) = Val_int(WTERMSIG(status));
    } else if (WIFSTOPPED(status)) {
        /* WSTOPPED of int */
        result = caml_alloc_small(1, 2);
        Field(result, 0) = Val_int(WSTOPSIG(status));
    } else {
        /* Should not happen */
        result = caml_alloc_small(1, 0);
        Field(result, 0) = Val_int(255);
    }

    CAMLreturn(result);
}

/*
 * spawn_with_trace_run : prog:string -> argv:string array -> env:string array -> cwd:string option
 *                        -> stdin:int -> stdout:int -> stderr:int
 *                        -> (Unix.process_status * string list)
 */
CAMLprim value spawn_with_trace_run(value prog, value argv, value env, value cwd,
                                     value stdin_fd, value stdout_fd, value stderr_fd) {
    CAMLparam5(prog, argv, env, cwd, stdin_fd);
    CAMLxparam2(stdout_fd, stderr_fd);
    CAMLlocal3(result, status_val, paths_val);

    const char *prog_str = String_val(prog);
    const char *cwd_str = Is_none(cwd) ? NULL : String_val(Some_val(cwd));
    int c_stdin_fd = Int_val(stdin_fd);
    int c_stdout_fd = Int_val(stdout_fd);
    int c_stderr_fd = Int_val(stderr_fd);

    /* Convert argv to C array */
    mlsize_t argc = Wosize_val(argv);
    char **argv_c = malloc((argc + 1) * sizeof(char *));
    if (!argv_c) caml_raise_out_of_memory();

    for (mlsize_t i = 0; i < argc; i++) {
        argv_c[i] = (char *)String_val(Field(argv, i));
    }
    argv_c[argc] = NULL;

    /* Convert env to C array */
    mlsize_t envc = Wosize_val(env);
    char **env_c = malloc((envc + 1) * sizeof(char *));
    if (!env_c) {
        free(argv_c);
        caml_raise_out_of_memory();
    }

    for (mlsize_t i = 0; i < envc; i++) {
        env_c[i] = (char *)String_val(Field(env, i));
    }
    env_c[envc] = NULL;

    struct path_list paths;
    path_list_init(&paths);

    int exit_status = 0;

    /* Release OCaml runtime for blocking operations */
    caml_enter_blocking_section();

    pid_t child = fork();
    if (child == -1) {
        caml_leave_blocking_section();
        free(argv_c);
        free(env_c);
        uerror("fork", Nothing);
    }

    if (child == 0) {
        /* Child process */
        child_setup_and_exec(prog_str, argv_c, env_c, cwd_str, c_stdin_fd, c_stdout_fd, c_stderr_fd);
        _exit(127);
    }

    /* Parent process */
    free(argv_c);
    free(env_c);

    int trace_result = trace_child(child, &paths, &exit_status);

    caml_leave_blocking_section();

    if (trace_result == -1) {
        path_list_free(&paths);
        uerror("trace_child", Nothing);
    }

    /* Build result tuple (process_status * string list) */
    status_val = make_process_status(exit_status);
    paths_val = paths_to_ocaml_list(&paths);

    path_list_free(&paths);

    result = caml_alloc_tuple(2);
    Store_field(result, 0, status_val);
    Store_field(result, 1, paths_val);

    CAMLreturn(result);
}

/* Bytecode wrapper for 7-argument function */
CAMLprim value spawn_with_trace_run_bytecode(value *argv, int argn) {
    (void)argn;
    return spawn_with_trace_run(argv[0], argv[1], argv[2], argv[3],
                                 argv[4], argv[5], argv[6]);
}

#else /* Not Linux x86_64 or aarch64 */

#include <errno.h>

CAMLprim value spawn_with_trace_run(value prog, value argv, value env, value cwd,
                                     value stdin_fd, value stdout_fd, value stderr_fd) {
    CAMLparam5(prog, argv, env, cwd, stdin_fd);
    CAMLxparam2(stdout_fd, stderr_fd);
    unix_error(ENOTSUP, "spawn_with_trace_run", Nothing);
    CAMLreturn(Val_unit); /* Never reached */
}

CAMLprim value spawn_with_trace_run_bytecode(value *argv, int argn) {
    (void)argn;
    return spawn_with_trace_run(argv[0], argv[1], argv[2], argv[3],
                                 argv[4], argv[5], argv[6]);
}

#endif
