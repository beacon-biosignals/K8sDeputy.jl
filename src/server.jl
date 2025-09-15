const DEFAULT_PORT = 8081

function _default_port()
    name = "DEPUTY_HEALTH_CHECK_PORT"
    return haskey(ENV, name) ? parse(Int, ENV[name]) : DEFAULT_PORT
end

"""
    K8sDeputy.serve!(deputy::Deputy, [host], [port::Integer]; kwargs...) -> HTTP.Server

Starts a non-blocking `HTTP.Server` responding to requests to `deputy` health checks. The
following health check endpoints are available:

- `/health/live`: Is the server is alive/running?
- `/health/ready`: Is the server ready (has `readied!(deputy)` been called)?
- `/health`: Comprehensive health status including all custom checks

These endpoints will respond with HTTP status `200 OK` on success or
`503 Service Unavailable` on failure. When the `Accept: application/json` header is provided,
the endpoints return detailed JSON responses including custom health check results.

## Arguments

- `host` (optional): The address to listen to for incoming requests. Defaults to
  `Sockets.localhost`.
- `port::Integer` (optional): The port to listen on. Defaults to the port number specified
  by the environmental variable `DEPUTY_HEALTH_CHECK_PORT`, otherwise `8081`.

Any `kwargs` provided are passed to `HTTP.serve!`.
"""
function serve!(deputy::Deputy, host=localhost, port::Integer=_default_port(); kwargs...)
    router = HTTP.Router()
    HTTP.register!(router, "/health/live", liveness_endpoint(deputy))
    HTTP.register!(router, "/health/ready", readiness_endpoint(deputy))
    HTTP.register!(router, "/health", health_endpoint(deputy))

    return HTTP.serve!(router, host, port; kwargs...)
end
