# Custom Health Checks Feature Design for K8sDeputy.jl

## Current State of the Package

### Overview
K8sDeputy.jl is a Julia package that provides Kubernetes health checks and graceful termination support for Julia services. It currently implements the standard K8s health check pattern with two fixed endpoints.

### Core Components

#### 1. Deputy Structure (`src/health.jl`)
- **Current Implementation**: 
  - Simple mutable struct with boolean flags for `ready` and `shutting_down` states
  - Stores optional `shutdown_handler` callback for custom shutdown logic
  - Fixed health check logic based on boolean states

```julia
mutable struct Deputy
    ready::Bool
    shutting_down::Bool
    shutdown_handler::Any
    shutdown_handler_timeout::Second
end
```

#### 2. Health Check Endpoints (`src/health.jl`)
- **Liveness Endpoint** (`/health/live`):
  - Returns 200 OK if not shutting down
  - Returns 503 Service Unavailable if shutting down
  - Fixed logic: `!deputy.shutting_down`

- **Readiness Endpoint** (`/health/ready`):
  - Returns 200 OK if ready
  - Returns 503 Service Unavailable if not ready
  - Fixed logic: `deputy.ready`

#### 3. HTTP Server (`src/server.jl`)
- Serves health check endpoints on configurable host/port
- Default port: 8081 (or `DEPUTY_HEALTH_CHECK_PORT` env var)
- Uses HTTP.jl router to register fixed endpoints

#### 4. Graceful Termination (`src/graceful_termination.jl`)
- Provides mechanism for clean shutdown via UNIX domain sockets
- Integrates with K8s preStop hooks
- Includes supervisor script for SIGTERM handling

### Current Limitations
1. **Fixed Health Check Logic**: Only boolean state checks, no custom validation
2. **Limited to Two Endpoints**: Only `/health/live` and `/health/ready`
3. **No Custom Health Indicators**: Cannot add application-specific health checks
4. **No Dependency Checks**: Cannot verify external dependencies (databases, services)
5. **No Health Check Metadata**: Cannot return detailed status information

## Proposed Changes for Custom Health Checks

### 1. Enhanced Deputy Structure

```julia
mutable struct Deputy
    ready::Bool
    shutting_down::Bool
    shutdown_handler::Any
    shutdown_handler_timeout::Second
    custom_health_checks::Dict{String, HealthCheck}  # NEW
    check_timeout::Second  # NEW: timeout for custom checks
end

# New struct for health checks
struct HealthCheck
    name::String
    check_function::Function  # () -> HealthCheckResult
    critical::Bool  # If true, failure affects overall health
    tags::Vector{String}  # For categorization
end

# Result type for health checks
struct HealthCheckResult
    healthy::Bool
    message::Union{String, Nothing}
    details::Dict{String, Any}  # Optional metadata
    duration_ms::Float64  # Execution time
end
```

### 2. New Public API Functions

```julia
# Register a custom health check
function register_health_check!(
    deputy::Deputy, 
    name::String, 
    check_fn::Function;
    critical::Bool=true,
    tags::Vector{String}=String[]
)

# Remove a health check
function unregister_health_check!(deputy::Deputy, name::String)

# Execute all health checks
function run_health_checks(deputy::Deputy) -> Dict{String, HealthCheckResult}

# Get health check status
function health_status(deputy::Deputy) -> HealthStatus
```

### 3. Enhanced Endpoint Responses

#### Updated Liveness Endpoint
```julia
function liveness_endpoint(deputy::Deputy)
    return function (r::HTTP.Request)
        @debug "liveness probed"
        
        # Run critical liveness checks if any registered
        liveness_checks = filter_checks(deputy.custom_health_checks, :liveness)
        
        if !isempty(liveness_checks)
            results = run_checks(liveness_checks, deputy.check_timeout)
            all_healthy = all(r -> r.healthy || !r.critical, results)
            
            if r.headers["Accept"] == "application/json"
                # Return detailed JSON response
                return HTTP.Response(
                    all_healthy ? 200 : 503,
                    ["Content-Type" => "application/json"],
                    JSON.json(results)
                )
            else
                return HTTP.Response(all_healthy ? 200 : 503)
            end
        else
            # Fall back to original behavior
            return !deputy.shutting_down ? HTTP.Response(200) : HTTP.Response(503)
        end
    end
end
```

#### New Composite Health Endpoint
```julia
# GET /health - returns overall health with all check results
function health_endpoint(deputy::Deputy)
    return function (r::HTTP.Request)
        status = health_status(deputy)
        return HTTP.Response(
            status.healthy ? 200 : 503,
            ["Content-Type" => "application/json"],
            JSON.json(status)
        )
    end
end
```

### 4. Implementation Tasks

#### Phase 1: Core Infrastructure
1. Add new fields to `Deputy` struct with backward compatibility
2. Implement `HealthCheck` and `HealthCheckResult` types
3. Create health check registration/management functions
4. Add thread-safe execution of health checks with timeouts

#### Phase 2: Enhanced Endpoints
1. Update existing endpoints to optionally include custom checks
2. Add new `/health` endpoint for comprehensive status
3. Support both simple HTTP status and detailed JSON responses
4. Add request header parsing for response format selection

#### Phase 3: Built-in Health Checks
1. Create library of common health checks:
   - Database connectivity
   - File system access
   - Memory usage
   - CPU usage
   - External HTTP service availability
2. Make these available but optional

#### Phase 4: Integration & Testing
1. Update existing tests to cover new functionality
2. Add comprehensive test suite for custom health checks
3. Update documentation with examples
4. Ensure backward compatibility

### 5. Usage Examples

```julia
using K8sDeputy

# Create deputy with custom health checks
deputy = Deputy(check_timeout=Second(5))

# Register a database health check
register_health_check!(deputy, "database", critical=true, tags=["database", "liveness"]) do
    try
        # Check database connection
        db_ping()
        return HealthCheckResult(true, "Database responding", Dict(), 10.5)
    catch e
        return HealthCheckResult(false, "Database connection failed: $e", Dict(), 100.0)
    end
end

# Register a disk space check
register_health_check!(deputy, "disk_space", critical=false, tags=["readiness"]) do
    free_space = check_disk_space("/data")
    healthy = free_space > 1_000_000_000  # 1GB minimum
    return HealthCheckResult(
        healthy,
        "Disk space: $(free_space / 1e9) GB",
        Dict("free_bytes" => free_space),
        5.0
    )
end

# Start serving with enhanced endpoints
serve!(deputy, localhost, 8081)
readied!(deputy)
```

### 6. Backward Compatibility

- All existing APIs remain unchanged
- Default behavior without custom checks matches current implementation
- New features are opt-in via new functions
- Existing Deputy constructors work without modification

### 7. Configuration Options

Add support for configuration via:
- Environment variables for default timeouts
- JSON/YAML config file for predefined health checks
- Runtime configuration updates

### 8. Dependencies

New dependencies to add:
- `JSON.jl` or `JSON3.jl` for JSON responses (likely already indirect dependency via HTTP.jl)
- Consider `OrderedCollections.jl` for ordered health check execution

## Benefits of This Approach

1. **Flexibility**: Applications can define health checks specific to their needs
2. **Visibility**: Detailed health status information for debugging
3. **Granularity**: Different checks for liveness vs readiness
4. **Compatibility**: Maintains backward compatibility
5. **Extensibility**: Easy to add new check types and features
6. **K8s Native**: Follows K8s health check best practices

## Migration Path

1. Release with new features as experimental/beta
2. Gather feedback from users
3. Stabilize API based on feedback
4. Document migration guide for advanced features
5. Consider deprecating some internal functions in favor of new APIs

## Next Steps

1. Review and refine this design document
2. Create GitHub issues for implementation phases
3. Implement Phase 1 (Core Infrastructure) in a feature branch
4. Write comprehensive tests
5. Update documentation
6. Release as minor version bump (backward compatible)