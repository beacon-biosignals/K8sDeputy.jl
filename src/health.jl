mutable struct Deputy
    ready::Bool
    shutting_down::Bool
    shutdown_handler::Any
    shutdown_handler_timeout::Second
end

function Deputy(; shutdown_handler=nothing, shutdown_handler_timeout::Period=Second(5))
    return Deputy(false, false, shutdown_handler, shutdown_handler_timeout)
end

function readied(deputy::Deputy)
    deputy.ready = true
    return nothing
end

function shutdown(deputy::Deputy)
    # Abend if already shutting down
    deputy.shutting_down && return nothing
    deputy.shutting_down = true

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

    # Shutdown handler's should not call `exit`
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
