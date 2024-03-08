const K8S_DEPUTY_IMAGE = get(ENV, "K8S_DEPUTY_IMAGE", "k8s-deputy:integration")
const K8S_DEPUTY_IMAGE_REPO = first(split(K8S_DEPUTY_IMAGE, ':'; limit=2))
const K8S_DEPUTY_IMAGE_TAG = last(split(K8S_DEPUTY_IMAGE, ':'; limit=2))  # Includes image digest SHA

const TERMINATION_GRACE_PERIOD_SECONDS = 5

# As a convenience we'll automatically build the Docker image when a user uses `Pkg.test()`.
# If the environmental variable is set we expect the Docker image has been pre-built.
if !haskey(ENV, "K8S_DEPUTY_IMAGE")
    context_dir = joinpath(@__DIR__(), "..")
    dockerfile = joinpath("integration", "Dockerfile")

    build_args = Dict("JULIA_VERSION" => VERSION)
    docker_build(context_dir; dockerfile, build_args, tag=K8S_DEPUTY_IMAGE)
end

# Verify Julia's handling of the `TERM` signal in a K8s environment
@testset "SIGTERM graceful termination" begin
    chart_name = "integration"
    overrides = Dict("image.repository" => K8S_DEPUTY_IMAGE_REPO,
                     "image.tag" => K8S_DEPUTY_IMAGE_TAG,
                     "command" => ["julia", "entrypoint.jl"],
                     "lifecycle" => nothing,
                     "terminationGracePeriodSeconds" => TERMINATION_GRACE_PERIOD_SECONDS)

    local pod, delete_duration
    install_chart(chart_name, overrides; timeout="15s") do
        pod = Pod("$chart_name-k8s-deputy")
        delete_started = time()
        delete(pod)
        wait(pod)
        delete_duration = time() - delete_started
        return nothing
    end

    # # Determine when the "delete" command was received by the server
    # event_items = get_events(pod).items
    # delete_event = last(filter(event -> event.reason == "Killing", event_items))
    # delete_event_timestamp = parse(DateTime, delete_event.lastTimestamp, dateformat"yyyy-mm-dd\THH:MM:SS\Z")

    logs = String(take!(pod.logs))
    @test delete_duration < TERMINATION_GRACE_PERIOD_SECONDS
    @test contains(logs, "[1] signal (15): Terminated\nin expression starting at")
    @test !any(event -> event.reason == "FailedPreStopHook", get_events(pod).items)
end

# Verify Julia's handling of the `TERM` signal in a K8s environment
@testset "Ignore SIGTERM graceful termination" begin
    chart_name = "integration"
    # Child processes don't automatically get forwarded signals
    overrides = Dict("image.repository" => K8S_DEPUTY_IMAGE_REPO,
                     "image.tag" => K8S_DEPUTY_IMAGE_TAG,
                     "command" => ["/bin/sh", "-c", "julia entrypoint.jl"],
                     "lifecycle" => nothing,
                     "terminationGracePeriodSeconds" => TERMINATION_GRACE_PERIOD_SECONDS)

    local pod, delete_duration
    install_chart(chart_name, overrides; timeout="15s") do
        pod = Pod("$chart_name-k8s-deputy")
        delete_started = time()
        delete(pod)
        wait(pod)
        delete_duration = time() - delete_started
        return nothing
    end

    logs = String(take!(pod.logs))
    @test delete_duration > TERMINATION_GRACE_PERIOD_SECONDS
    @test !contains(logs, "signal (15): Terminated")
    @test !any(event -> event.reason == "FailedPreStopHook", get_events(pod).items)
end

@testset "Container halts before preStop completes" begin
    chart_name = "integration"
    overrides = Dict("image.repository" => K8S_DEPUTY_IMAGE_REPO,
                     "image.tag" => K8S_DEPUTY_IMAGE_TAG,
                     "command" => ["julia", "entrypoint.jl"],
                     "terminationGracePeriodSeconds" => TERMINATION_GRACE_PERIOD_SECONDS)

    local pod, delete_duration
    install_chart(chart_name, overrides; timeout="15s") do
        pod = Pod("$chart_name-k8s-deputy")
        delete_started = time()
        delete(pod)
        wait(pod)
        delete_duration = time() - delete_started
        return nothing
    end

    logs = String(take!(pod.logs))
    @test delete_duration < TERMINATION_GRACE_PERIOD_SECONDS
    @test !contains(logs, "signal (15): Terminated")
    @test any(event -> event.reason == "FailedPreStopHook", get_events(pod).items)
end

@testset "Missing post Julia entrypoint delay" begin
    chart_name = "integration"
    overrides = Dict("image.repository" => K8S_DEPUTY_IMAGE_REPO,
                     "image.tag" => K8S_DEPUTY_IMAGE_TAG,
                     "command" => ["/bin/sh", "-c", "julia entrypoint.jl"],
                     "terminationGracePeriodSeconds" => TERMINATION_GRACE_PERIOD_SECONDS)

    local pod, delete_duration
    install_chart(chart_name, overrides; timeout="15s") do
        pod = Pod("$chart_name-k8s-deputy")
        delete_started = time()
        delete(pod)
        wait(pod)
        delete_duration = time() - delete_started
        return nothing
    end

    logs = String(take!(pod.logs))
    @test delete_duration < TERMINATION_GRACE_PERIOD_SECONDS
    @test !contains(logs, "signal (15): Terminated")
    @test any(event -> event.reason == "FailedPreStopHook", get_events(pod).items)
end

@testset "Valid" begin
    chart_name = "integration"
    overrides = Dict("image.repository" => K8S_DEPUTY_IMAGE_REPO,
                     "image.tag" => K8S_DEPUTY_IMAGE_TAG,
                     "command" => ["/bin/sh", "-c", "julia entrypoint.jl; sleep 1"],
                     "terminationGracePeriodSeconds" => TERMINATION_GRACE_PERIOD_SECONDS)

    local pod, delete_duration
    install_chart(chart_name, overrides; timeout="15s") do
        pod = Pod("$chart_name-k8s-deputy")
        delete_started = time()
        delete(pod)
        wait(pod)
        delete_duration = time() - delete_started
        return nothing
    end

    logs = String(take!(pod.logs))
    @test delete_duration < TERMINATION_GRACE_PERIOD_SECONDS
    @test !contains(logs, "signal (15): Terminated")
    @test !any(event -> event.reason == "FailedPreStopHook", get_events(pod).items)
end
