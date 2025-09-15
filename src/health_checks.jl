"""
Health check types and functionality for custom health validation.
"""

struct HealthCheckResult
    healthy::Bool
    message::Union{String, Nothing}
    details::Dict{String, Any}
    duration_ms::Float64
    
    function HealthCheckResult(healthy::Bool, message::Union{String, Nothing}=nothing,
                              details::Dict{String, Any}=Dict{String, Any}(),
                              duration_ms::Float64=0.0)
        return new(healthy, message, details, duration_ms)
    end
end

struct HealthCheck
    name::String
    check_function::Function
    critical::Bool
    tags::Vector{String}
    
    function HealthCheck(name::String, check_function::Function;
                        critical::Bool=true, tags::Vector{String}=String[])
        return new(name, check_function, critical, tags)
    end
end

struct HealthStatus
    healthy::Bool
    checks::Dict{String, HealthCheckResult}
    timestamp::String
    
    function HealthStatus(healthy::Bool, checks::Dict{String, HealthCheckResult})
        return new(healthy, checks, string(now()))
    end
end

"""
    register_health_check!(deputy::Deputy, name::String, check_fn::Function; 
                          critical::Bool=true, tags::Vector{String}=String[])

Register a custom health check with the deputy.

## Arguments
- `deputy`: The Deputy instance to register the check with
- `name`: Unique name for the health check
- `check_fn`: Zero-argument function that returns a HealthCheckResult

## Keywords
- `critical`: If true, failure affects overall health status (default: true)
- `tags`: Tags for categorizing the check (e.g., ["liveness"], ["readiness"], ["dependency"])

## Example
```julia
register_health_check!(deputy, "database") do
    try
        ping_database()
        return HealthCheckResult(true, "Database is healthy")
    catch e
        return HealthCheckResult(false, "Database connection failed: \$e")
    end
end
```
"""
function register_health_check!(deputy::Deputy, name::String, check_fn::Function;
                               critical::Bool=true, tags::Vector{String}=String[])
    check = HealthCheck(name, check_fn; critical=critical, tags=tags)
    lock(deputy.health_checks_lock) do
        deputy.custom_health_checks[name] = check
    end
    return nothing
end

"""
    unregister_health_check!(deputy::Deputy, name::String)

Remove a registered health check.
"""
function unregister_health_check!(deputy::Deputy, name::String)
    lock(deputy.health_checks_lock) do
        delete!(deputy.custom_health_checks, name)
    end
    return nothing
end

"""
    run_health_check(check::HealthCheck, timeout::Period) -> HealthCheckResult

Execute a single health check with timeout.
"""
function run_health_check(check::HealthCheck, timeout::Period)
    start_time = time()
    result_channel = Channel{HealthCheckResult}(1)
    
    @async begin
        try
            result = check.check_function()
            put!(result_channel, result)
        catch e
            error_result = HealthCheckResult(
                false,
                "Health check threw exception: $(sprint(showerror, e))",
                Dict{String, Any}("error" => string(e)),
                (time() - start_time) * 1000
            )
            put!(result_channel, error_result)
        end
    end
    
    # Wait for result with timeout
    status = timedwait(timeout; pollint=Second(0.1)) do
        return isready(result_channel)
    end
    
    if status === :ok
        result = take!(result_channel)
        # Update duration if not already set
        if result.duration_ms == 0.0
            duration_ms = (time() - start_time) * 1000
            result = HealthCheckResult(result.healthy, result.message, result.details, duration_ms)
        end
        return result
    else
        duration_ms = (time() - start_time) * 1000
        return HealthCheckResult(
            false,
            "Health check timed out after $(timeout)",
            Dict{String, Any}("timeout" => true),
            duration_ms
        )
    end
end

"""
    run_health_checks(deputy::Deputy; tags::Vector{String}=String[]) -> Dict{String, HealthCheckResult}

Execute health checks, optionally filtered by tags.
"""
function run_health_checks(deputy::Deputy; tags::Vector{String}=String[])
    checks_to_run = lock(deputy.health_checks_lock) do
        if isempty(tags)
            return copy(deputy.custom_health_checks)
        else
            return filter(deputy.custom_health_checks) do (name, check)
                return any(tag -> tag in check.tags, tags)
            end
        end
    end
    
    results = Dict{String, HealthCheckResult}()
    
    # Run checks in parallel
    tasks = []
    for (name, check) in checks_to_run
        task = @async begin
            return name => run_health_check(check, deputy.check_timeout)
        end
        push!(tasks, task)
    end
    
    # Collect results
    for task in tasks
        name, result = fetch(task)
        results[name] = result
    end
    
    return results
end

"""
    health_status(deputy::Deputy; include_default::Bool=true) -> HealthStatus

Get comprehensive health status including all checks.
"""
function health_status(deputy::Deputy; include_default::Bool=true)
    results = Dict{String, HealthCheckResult}()
    
    # Include default checks
    if include_default
        results["ready"] = HealthCheckResult(
            deputy.ready,
            deputy.ready ? "Application is ready" : "Application not ready"
        )
        results["live"] = HealthCheckResult(
            !deputy.shutting_down,
            deputy.shutting_down ? "Application is shutting down" : "Application is live"
        )
    end
    
    # Run custom checks
    custom_results = run_health_checks(deputy)
    merge!(results, custom_results)
    
    # Determine overall health
    overall_healthy = all(results) do (name, result)
        check = get(deputy.custom_health_checks, name, nothing)
        # If it's a custom check, only critical failures affect overall health
        if !isnothing(check)
            return result.healthy || !check.critical
        else
            # Default checks (ready/live) always affect overall health
            return result.healthy
        end
    end
    
    return HealthStatus(overall_healthy, results)
end

"""
    to_dict(status::HealthStatus) -> Dict

Convert HealthStatus to a dictionary suitable for JSON serialization.
"""
function to_dict(status::HealthStatus)
    return Dict{String, Any}(
        "healthy" => status.healthy,
        "timestamp" => status.timestamp,
        "checks" => Dict(
            name => Dict{String, Any}(
                "healthy" => result.healthy,
                "message" => result.message,
                "details" => result.details,
                "duration_ms" => result.duration_ms
            )
            for (name, result) in status.checks
        )
    )
end

"""
    to_dict(result::HealthCheckResult) -> Dict

Convert HealthCheckResult to a dictionary suitable for JSON serialization.
"""
function to_dict(result::HealthCheckResult)
    return Dict{String, Any}(
        "healthy" => result.healthy,
        "message" => result.message,
        "details" => result.details,
        "duration_ms" => result.duration_ms
    )
end