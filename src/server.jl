const DEFAULT_PORT = 8081

function _default_port()
    name = "DEPUTY_HEALTH_CHECK_PORT"
    return haskey(ENV, name) ? parse(Int, ENV[name]) : DEFAULT_PORT
end

"""
    K8sDeputy.serve!(deputy::Deputy, [host], [port::Integer]) -> HTTP.Server

Starts a non-blocking `HTTP.Server` responding to requests to `deputy` health checks. The
following health check endpoints are available:

- `/health/live`: Is the server is alive/running?
- `/health/ready`: Is the server ready (has `readied(deputy)` been called)?

These endpoints will respond with HTTP status `200 OK` on success or
`503 Service Unavailable` on failure.

## Arguments

- `host` (optional): The address to listen to for incoming requests. Defaults to
  `Sockets.localhost`.
- `port::Integer` (optional): The port to listen on. Defaults to the port number specified
  by the environmental variable `DEPUTY_HEALTH_CHECK_PORT`, otherwise `8081`.
"""
function serve!(deputy::Deputy, host=localhost, port::Integer=_default_port())
    router = HTTP.Router()
    HTTP.register!(router, "/health/live", liveness_endpoint(deputy))
    HTTP.register!(router, "/health/ready", readiness_endpoint(deputy))

    return HTTP.serve!(router, host, port)
end
