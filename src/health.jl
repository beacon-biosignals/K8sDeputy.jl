mutable struct Deputy
    ready::Bool
    shutting_down::Bool
    shutdown_handler::Any
    shutdown_handler_timeout::Second
    custom_health_checks::Dict{String, HealthCheck}
    health_checks_lock::ReentrantLock
    check_timeout::Second
end

"""
    Deputy(; shutdown_handler=nothing, shutdown_handler_timeout::Period=Second(5),
           check_timeout::Period=Second(5))

Construct an application `Deputy` which provides health check endpoints.

## Keywords

- `shutdown_handler` (optional): A zero-argument function which allows the user to provide
  a custom callback function for when `shutdown!(::Deputy)` is called.
- `shutdown_handler_timeout::Period` (optional): Specifies the maximum execution duration of
  a `shutdown_handler`.
- `check_timeout::Period` (optional): Specifies the maximum execution duration for each
  custom health check. Defaults to 5 seconds.
"""
function Deputy(; shutdown_handler=nothing, shutdown_handler_timeout::Period=Second(5),
                check_timeout::Period=Second(5))
    return Deputy(false, false, shutdown_handler, shutdown_handler_timeout,
                  Dict{String, HealthCheck}(), ReentrantLock(), check_timeout)
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
        
        # Check for custom liveness checks
        liveness_checks = lock(deputy.health_checks_lock) do
            filter(deputy.custom_health_checks) do (name, check)
                return "liveness" in check.tags
            end
        end
        
        if !isempty(liveness_checks)
            # Run liveness checks
            results = Dict{String, HealthCheckResult}()
            for (name, check) in liveness_checks
                results[name] = run_health_check(check, deputy.check_timeout)
            end
            
            # Check if all critical checks pass
            all_healthy = all(results) do (name, result)
                check = liveness_checks[name]
                return result.healthy || !check.critical
            end
            
            # Also check the default liveness (not shutting down)
            all_healthy = all_healthy && !deputy.shutting_down
            
            # Return JSON response if requested
            accept_header = get(r.headers, "Accept", "")
            if occursin("application/json", accept_header)
                response_body = Dict{String, Any}(
                    "status" => all_healthy ? "healthy" : "unhealthy",
                    "checks" => Dict(name => to_dict(result) for (name, result) in results),
                    "shutting_down" => deputy.shutting_down
                )
                return HTTP.Response(
                    all_healthy ? 200 : 503,
                    ["Content-Type" => "application/json"],
                    HTTP.bytes(repr(response_body))
                )
            else
                return HTTP.Response(all_healthy ? 200 : 503)
            end
        else
            # Fall back to original behavior
            return if !deputy.shutting_down
                HTTP.Response(200)
            else
                HTTP.Response(503)
            end
        end
    end
end

function readiness_endpoint(deputy::Deputy)
    return function (r::HTTP.Request)
        @debug "readiness probed"
        
        # Check for custom readiness checks
        readiness_checks = lock(deputy.health_checks_lock) do
            filter(deputy.custom_health_checks) do (name, check)
                return "readiness" in check.tags
            end
        end
        
        if !isempty(readiness_checks)
            # Run readiness checks
            results = Dict{String, HealthCheckResult}()
            for (name, check) in readiness_checks
                results[name] = run_health_check(check, deputy.check_timeout)
            end
            
            # Check if all critical checks pass
            all_healthy = all(results) do (name, result)
                check = readiness_checks[name]
                return result.healthy || !check.critical
            end
            
            # Also check the default readiness
            all_healthy = all_healthy && deputy.ready
            
            # Return JSON response if requested
            accept_header = get(r.headers, "Accept", "")
            if occursin("application/json", accept_header)
                response_body = Dict{String, Any}(
                    "status" => all_healthy ? "healthy" : "unhealthy",
                    "checks" => Dict(name => to_dict(result) for (name, result) in results),
                    "ready" => deputy.ready
                )
                return HTTP.Response(
                    all_healthy ? 200 : 503,
                    ["Content-Type" => "application/json"],
                    HTTP.bytes(repr(response_body))
                )
            else
                return HTTP.Response(all_healthy ? 200 : 503)
            end
        else
            # Fall back to original behavior
            return if deputy.ready
                HTTP.Response(200)
            else
                HTTP.Response(503)
            end
        end
    end
end

function health_endpoint(deputy::Deputy)
    return function (r::HTTP.Request)
        @debug "health status requested"
        
        status = health_status(deputy)
        
        # Always return JSON for comprehensive health endpoint
        return HTTP.Response(
            status.healthy ? 200 : 503,
            ["Content-Type" => "application/json"],
            HTTP.bytes(repr(to_dict(status)))
        )
    end
end
