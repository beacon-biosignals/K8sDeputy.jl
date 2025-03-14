mutable struct Deputy
    ready::Bool
    shutting_down::Bool
    shutdown_handler::Any
    shutdown_handler_timeout::Second
end

"""
    Deputy(; shutdown_handler=nothing, shutdown_handler_timeout::Period=Second(5))

Construct an application `Deputy` which provides health check endpoints.

## Keywords

- `shutdown_handler` (optional): A zero-argument function which allows the user to provide
  a custom callback function for when `shutdown!(::Deputy)` is called.
- `shutdown_handler_timeout::Period` (optional): Specifies the maximum execution duration of
  a `shutdown_handler`.
"""
function Deputy(; shutdown_handler=nothing, shutdown_handler_timeout::Period=Second(5))
    return Deputy(false, false, shutdown_handler, shutdown_handler_timeout)
end

"""
    readied!(deputy::Deputy) -> Nothing

Mark the application as "ready". Sets the readiness endpoint to respond with successful
responses.
"""
function readied!(deputy::Deputy)
    deputy.ready = true
    return nothing
end

"""
    shutdown!(deputy::Deputy) -> Nothing

Initiates a shutdown of the application by:

1. Mark the application as shutting down ("non-live").
2. Executing the deputy's `shutdown_handler` (if defined).
3. Exiting the current Julia process.

If a `deputy.shutdown_handler` is defined it must complete within the
`deputy.shutdown_handler_timeout` or a warning will be logged and the Julia process will
immediately exit. Any exceptions that occur in the `deputy.shutdown_handler` will also be
logged and result in the Julia process exiting.

A `shutdown_handler` may optionally call `exit` if a user wants to specify the exit status.
By default `shutdown!` uses an exit status of `1`.
"""
function shutdown!(deputy::Deputy)
    # Abend if already shutting down
    deputy.shutting_down && return nothing
    deputy.shutting_down = true
    @debug "Initiating deputy shutdown"

    if !isnothing(deputy.shutdown_handler)
        t = @async deputy.shutdown_handler()

        # Ensure the shutdown handler completes on-time and without exceptions
        status = timedwait(deputy.shutdown_handler_timeout; pollint=Second(1)) do
            return istaskdone(t)
        end

        if istaskfailed(t)
            @error "Shutdown handler failed" exception = TaskFailedException(t)
        elseif status === :timed_out
            @warn "Shutdown handler still running after $(deputy.shutdown_handler_timeout)"
        end
    end

    # Normally `shutdown!` is responsible for exiting the Julia process. However, a
    # user-defined `shutdown_handler` may call `exit` but must do so prior before reaching
    # the timeout.
    @mock exit(1)

    return nothing
end

function liveness_endpoint(deputy::Deputy)
    return function (r::HTTP.Request)
        @debug "liveness probed"
        return if !deputy.shutting_down
            HTTP.Response(200)
        else
            HTTP.Response(503)
        end
    end
end

function readiness_endpoint(deputy::Deputy)
    return function (r::HTTP.Request)
        @debug "readiness probed"
        return if deputy.ready
            HTTP.Response(200)
        else
            HTTP.Response(503)
        end
    end
end
