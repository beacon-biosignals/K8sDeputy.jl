# As Julia lacks user-defined signal handling and the default behavior for critical signals
# (i.e. SIGTERM, SIGABRT, SIGQUIT) is to report the signal and show a stack trace. As K8s
# utilizes SIGTERM by default to gracefully shutdown pods and we want to avoid logging
# unnecessary stack traces so we will utilize a `preStop` container hook as an alternative.
#
# Note it is possible to use the C function `sigaction` with a Julia callback function but
# from experimenting with this there are a few issues such as being unable to use locks or
# printing (`jl_safe_printf` does work).

# NOTE: if you update any paths, filenames, or the messages expected in the socket, you must
# also update /bin/supervise.sh to match.

# Linux stores PID files and UNIX-domain sockets in `/run`. Users with K8s containers
# utilizing read-only file systems should make use of a volume mount to allow K8sDeputy.jl
# to write to `/run`. Users can change the IPC directory by specifying `DEPUTY_IPC_DIR` but
# this is mainly just used for testing.
_deputy_ipc_dir() = get(ENV, "DEPUTY_IPC_DIR", "/run")

# Write transient UNIX-domain sockets to the IPC directory.
function _graceful_terminator_socket_path(pid::Int32)
    return joinpath(_deputy_ipc_dir(), "graceful-terminator.$pid.socket")
end

# Following the Linux convention for pid files:
# https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch03s15.html
entrypoint_pid_file() = joinpath(_deputy_ipc_dir(), "julia-entrypoint.pid")
set_entrypoint_pid(pid::Integer) = write(entrypoint_pid_file(), string(pid) * "\n")

function entrypoint_pid()
    pid_file = entrypoint_pid_file()
    return isfile(pid_file) ? parse(Int32, readchomp(pid_file)) : Int32(1)
end

# https://docs.libuv.org/en/v1.x/process.html#c.uv_kill
uv_kill(pid::Integer, signum::Integer) = ccall(:uv_kill, Cint, (Cint, Cint), pid, signum)

"""
    graceful_terminator(f; set_entrypoint::Bool=true) -> Nothing

Register a zero-argument function to be called when `graceful_terminate` is called targeting
this process. The user-defined function `f` is expected to call `exit` to terminate the
Julia process. The `graceful_terminator` function is only allowed to be called once within a
Julia process.

## Keywords

- `set_entrypoint::Bool` (optional): Sets the calling Julia process as the "entrypoint" to
  be targeted by default when running `graceful_terminate` in another Julia process. Users
  who want to utilize `graceful_terminator` in multiple Julia processes should use
  `set_entrypoint=false` and specify process IDs when calling `graceful_terminate`. Defaults
  to `true`.

## Examples

```julia
app_status = AppStatus()
graceful_terminator(() -> shutdown!(app_status))
```
## Kubernetes Setup

When using Kubernetes (K8s) you can enable [graceful termination](https://cloud.google.com/blog/products/containers-kubernetes/kubernetes-best-practices-terminating-with-grace)
of a Julia process by defining a pod [`preStop`](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/#container-hooks)
container hook. Typically, K8s initiates graceful termination via the `TERM` signal but
as Julia forcefully terminates when receiving this signal and Julia does not support
user-defined signal handlers we utilize `preStop` instead.

### Using superviser entrypoint

K8sDeputy provides a bash script in bin/superviser.sh which handles the `TERM` signal and
sends the `"terminate"` message to the graceful termination socket.  This can be used as the
`ENTRYPOINT` for your docker image.  For example, after installing `K8sDeputy` in the active
Julia project:

```dockerfile
RUN julia --color=yes -e 'using K8sDeputy; K8sDeputy.install_supervise_shim("/usr/bin")'
ENTRYPOINT ["/usr/bin/supervise.sh"]
```

The command/script to run and any arguments it requires should be passed in via `args` in
your [K8s Container
spec](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.33/#container-v1-core);
anything you specify for `command` in the Container spec will _override_ the container's
entrypoint.

!!! note
    The entrypoint script requires `netcat`, which is not present in e.g. `debian-slim`
    images.  In particular, it requires the "OpenBSD" flavor (available as `netcat-openbsd`
    in `apt`).  The script will fail before starting if `command -v nc` fails.

    It also uses `jq` to generate JSON-formatted log messages with timestamps.  This is not
    _required_ (it uses a more fragile fallback) but strongly recommended.

### Using pre-stop hook

The following K8s pod manifest snippet will specify K8s to call the user-defined function
specified by the `graceful_terminator`:

```yaml
spec:
  containers:
    - lifecycle:
        preStop:
          exec:
            command: ["julia", "-e", "using $(@__MODULE__()); graceful_terminate()"]
```

Additionally, the entrypoint for the container should also not directly use the Julia process
as the init process (PID 1). Instead, users should define their entrypoint similarly to
`["/bin/sh", "-c", "julia entrypoint.jl; sleep 1"]` as this allows for both the Julia
process and the `preStop` process to cleanly terminate.
"""
function graceful_terminator(f; set_entrypoint::Bool=true)
    set_entrypoint && set_entrypoint_pid(getpid())

    # Utilize UNIX-domain sockets (Linux) or named pipes (Windows) for the IPC. Avoid using
    # network sockets here as we don't want to allow access to this functionality from
    # outside of the localhost. Each process uses a distinct socket name allowing for
    # multiple Julia processes to allow independent use of the graceful terminator.
    socket_path = _graceful_terminator_socket_path(getpid())

    # Remove any pre-existing UNIX-domain socket as otherwise this will cause our `listen`
    # call to fail. Should be safe to remove this file as it has been reserved for this PID.
    # Only should be needed in the scenario where the K8s pod has been restarted and the
    # location of the socket exists in a K8s volume.
    ispath(socket_path) && rm(socket_path)

    server = listen(socket_path)

    t = Threads.@spawn begin
        while isopen(server)
            sock = accept(server)
            request = readline(sock)

            if request == "terminate"
                try
                    f()  # Expecting user-defined function to call `exit`
                catch e
                    @error "User graceful terminator callback failed with exception:\n" *
                           sprint(showerror, e, catch_backtrace())
                end
            else
                @warn "Graceful terminator received an invalid request: \"$request\""
            end

            close(sock)
        end
    end

    # Useful only to report internal errors
    @static if VERSION >= v"1.7.0-DEV.727"
        errormonitor(t)
    end

    return nothing
end

"""
    graceful_terminate(pid::Int32=entrypoint_pid(); wait::Bool=true) -> Nothing

Initiates the execution of the `graceful_terminator` user callback in the process `pid`. See
`graceful_terminator` for more details.
"""
function graceful_terminate(pid::Int32=entrypoint_pid(); wait::Bool=true)
    # Note: The follow dead code has been left here purposefully as an example of how to
    # view output when running via `preStop`.
    #
    # As K8s doesn't provide a way to view the logs from the `preStop` command you can work
    # a round this by writing to the STDOUT of the `pid`. Only works while `pid` is running.
    # https://stackoverflow.com/a/70708744
    # open("/proc/$pid/fd/1", "w") do io
    #     println(io, "preStop called")
    # end

    sock = connect(_graceful_terminator_socket_path(pid))
    println(sock, "terminate")
    close(sock)

    # Wait for the `pid` to complete. We must block here as otherwise K8s sends a
    # `TERM` signal immediately after the `preStop` completes. If we fail to wait the
    # Julia process won't have a chance to perform a "clean" shutdown. If the Julia process
    # takes longer than `terminationGracePeriodSeconds` to stop then K8s will forcefully
    # terminate the with the `KILL` signal.
    #
    # The `preStop` must complete before the container terminates otherwise K8s will
    # report a `FailedPreStopHook` event. To avoid seeing this warning the Julia process
    # should not be run directly as the container entrypoint but rather run as a subprocess
    # of the entrypoint with a delay after the subprocess' termination. Doing this allows
    # both the target Julia process and the `preStop` process to exit cleanly.
    #
    # https://cloud.google.com/blog/products/containers-kubernetes/kubernetes-best-practices-terminating-with-grace
    # https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination
    if wait
        # The special "signal" 0 is used to check for process existence.
        # https://man7.org/linux/man-pages/man2/kill.2.html
        while uv_kill(pid, 0) == 0
            # Polling frequency should ideally be faster than the post-termination delay
            sleep(0.1)
        end
    end

    return nothing
end

function install_supervise_shim(shims_root::AbstractString)
    src = abspath(joinpath(@__DIR__, "..", "bin", "supervise.sh"))
    isfile(src) || error("supervise.sh shim not found at $src")

    mkpath(shims_root)
    dest = joinpath(shims_root, "supervise.sh")

    @info "Linking $src -> $dest"
    symlink(src, dest)

    return dest
end
