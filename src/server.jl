const DEFAULT_PORT = 8081

function _default_port()
    name = "DEPUTY_HEALTH_CHECK_PORT"
    return haskey(ENV, name) ? parse(Int, ENV[name]) : DEFAULT_PORT
end

function serve!(deputy::Deputy, host=localhost, port::Integer=_default_port())
    router = HTTP.Router()
    HTTP.register!(router, "/health/live", live_endpoint(deputy))
    HTTP.register!(router, "/health/ready", ready_endpoint(deputy))

    return HTTP.serve!(router, host, port)
end
