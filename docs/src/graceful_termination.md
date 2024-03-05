# Graceful Termination

Kubernetes (K8s) applications are expected to handle [graceful termination](https://cloud.google.com/blog/products/containers-kubernetes/kubernetes-best-practices-terminating-with-grace). Typically,
applications will initiate a graceful termination by handling the `TERM` signal when a K8s pod is to be terminated.

At this point in time [Julia does not provide user-definable signal handlers](https://github.com/JuliaLang/julia/issues/14675) and the internal Julia signal handler for `TERM` results in the process reporting the signal (with a stack trace) to standard error and exiting. Julia provides users with [`atexit`](https://docs.julialang.org/en/v1/base/base/#Base.atexit) to define callbacks when Julia is terminating but unfortunately this callback system only allows for trivial actions to occur when Julia is shutdown due to handling the `TERM` signal.

These limitations resulted in K8sDeputy.jl providing an alternative path for handling graceful termination Julia processes. This avoids logging unnecessary error messages and also provides a reliable shutdown callback system for graceful termination.

## Interface

The K8sDeputy.jl package provides the `graceful_terminator` function for registering a single user callback upon receiving a graceful termination event. The `graceful_terminate` function can be used from another Julia process to terminate the `graceful_terminator` caller process. For example run the following code in an interactive Julia REPL:

```julia
using K8sDeputy
graceful_terminator(() -> (@info "Gracefully terminating..."; exit()))
```

In another terminal run the following code to initiate graceful termination:

```sh
julia -e 'using K8sDeputy; graceful_terminate()'
```

Once `graceful_terminate` has been called the first process will: execute the callback, log the message, and exit the Julia process.

!!! note

    By default the `graceful_terminator` function registers the caller Julia process as the "entrypoint" Julia process. Primarily, this allows for out-of-the-box support for Julia
    applications running as non-[init](https://en.wikipedia.org/wiki/Init) processes but only allows one Julia process to be defined as the "entrypoint". If you require multiple Julia processes within to support graceful termination concurrently you can use `set_entrypoint=false` (e.g. `graceful_terminator(...; set_entrypoint=false)`) and pass in the target process ID to `graceful_terminate`.

## Deputy Integration

The `graceful_terminator` function can be combined with the deputy's `shutdown` function to allow graceful termination of the application and the deputy:

```julia
using K8sDeputy
deputy = Deputy(; shutdown_handler=() -> @info "Shutting down")
server = K8sDeputy.serve!(deputy, "0.0.0.0")
graceful_terminator(() -> shutdown(deputy))

# Application code
```

## Kubernetes Setup

To configure your K8s container resource to call `graceful_terminate` when terminating you can configure a [`preStop` hook](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/#container-hooks):

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: app
      # command: ["/bin/sh", "-c", "julia entrypoint.jl; sleep 1"]
      lifecycle:
        preStop:
          exec:
            command: ["julia", "-e", "using K8sDeputy; graceful_terminate()"]
      # terminationGracePeriodSeconds: 30
```

!!! note

    Applications with slow shutdown callbacks may want to consider specifying `terminationGracePeriodSeconds` which specifies the maximum duration a pod can take when gracefully terminating. Once the timeout is reached the processes running in the pod are forcibly halted with a `KILL` signal.

Finally, the entrypoint for the container should also not directly use the Julia as [init](https://en.wikipedia.org/wiki/Init) process (PID 1). Instead, users should define their entrypoint similarly to
`["/bin/sh", "-c", "julia entrypoint.jl; sleep 1"]` as this allows the both the Julia process and the `preStop` process to cleanly terminate.
