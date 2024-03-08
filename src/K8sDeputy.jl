module K8sDeputy

using Dates: Period, Second
using HTTP: HTTP
using Mocking
using Sockets: accept, connect, listen, localhost

export Deputy, graceful_terminator, readied!, shutdown!, graceful_terminate

include("graceful_termination.jl")
include("health.jl")
include("server.jl")

end # module K8sDeputy
