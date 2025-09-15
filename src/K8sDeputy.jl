module K8sDeputy

using Dates: Period, Second, now
using HTTP: HTTP
using Mocking
using Sockets: accept, connect, listen, localhost

export Deputy, graceful_terminator, readied!, shutdown!, graceful_terminate
export HealthCheck, HealthCheckResult, HealthStatus
export register_health_check!, unregister_health_check!, run_health_checks, health_status

include("graceful_termination.jl")
include("health_checks.jl")
include("health.jl")
include("server.jl")
include("deprecated.jl")

end # module K8sDeputy
