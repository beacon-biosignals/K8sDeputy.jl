using Aqua: Aqua
using Dates: Second
using K8sDeputy
using K8sDeputy: readiness_endpoint, liveness_endpoint, serve!
using HTTP: HTTP
using Mocking: Mocking, @mock, @patch, apply
using Sockets: localhost
using Test

# https://en.wikipedia.org/wiki/Ephemeral_port
const EPHEMERAL_PORT_RANGE = 49152:65535

Mocking.activate()

const IPC_DIR = mktempdir()
ipc_dir_patch = @patch K8sDeputy._ipc_dir() = IPC_DIR

@testset "K8sDeputy.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(K8sDeputy; ambiguities=false)
    end

    include("graceful_termination.jl")
    include("health.jl")
end
