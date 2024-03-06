using Aqua: Aqua
using Dates: Second
using K8sDeputy
using K8sDeputy: readiness_endpoint, liveness_endpoint, serve!
using HTTP: HTTP
using Mocking: Mocking, @mock, @patch, apply
using Sockets: localhost
using Test

const RUN_TESTS = let
    valid_types = ("unit", "integration", "quality_assurance")
    run_tests = get(ENV, "RUN_TESTS", "unit,quality-assurance")
    types = map(t -> replace(t, '-' => '_'), split(run_tests, ','))
    NamedTuple([Symbol(t) => t in types for t in valid_types])
end

# https://en.wikipedia.org/wiki/Ephemeral_port
const EPHEMERAL_PORT_RANGE = 49152:65535

Mocking.activate()

@testset "K8sDeputy.jl" begin
    if RUN_TESTS.quality_assurance
        @testset "Quality Assurance" begin
            Aqua.test_all(K8sDeputy; ambiguities=false)
        end
    else
        @warn "Skipping quality assurance tests"
    end

    if RUN_TESTS.unit
        @testset "Unit" begin
            include("graceful_termination.jl")
            include("health.jl")
        end
    else
        @warn "Skipping unit tests"
    end

    if RUN_TESTS.integration
        @testset "Integration" begin
            include("integration.jl")
        end
    else
        @warn "Skipping integration tests"
    end
end
