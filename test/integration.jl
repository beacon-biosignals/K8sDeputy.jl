const K8S_DEPUTY_IMAGE = get(ENV, "K8S_DEPUTY_IMAGE", "k8s-deputy:integration")

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
    grace_period = 3
    overrides = Dict("image.repository" => image_repository(K8S_DEPUTY_IMAGE),
                     "image.tag" => image_tag(K8S_DEPUTY_IMAGE),
                     "command" => ["julia", "entrypoint.jl"],
                     "lifecycle" => nothing,
                     "terminationGracePeriodSeconds" => grace_period)

    local pod, delete_duration
    install_chart(chart_name, overrides) do
        pod = Pod("$chart_name-k8s-deputy")
        delete_started = time()
        delete(pod)
        wait(pod)
        delete_duration = time() - delete_started
    end

    # # Determine when the "delete" command was received by the server
    # event_items = get_events(pod).items
    # delete_event = last(filter(event -> event.reason == "Killing", event_items))
    # delete_event_timestamp = parse(DateTime, delete_event.lastTimestamp, dateformat"yyyy-mm-dd\THH:MM:SS\Z")

    logs = String(take!(pod.logs))
    @test delete_duration < grace_period
    @test contains(logs, "[1] signal (15): Terminated\nin expression starting at")
    @test !any(event -> event.reason == "FailedPreStopHook", get_events(pod).items)
end

# Verify Julia's handling of the `TERM` signal in a K8s environment
@testset "Ignore SIGTERM graceful termination" begin
    chart_name = "integration"
    grace_period = 3
    # Child processes don't automatically get forwarded signals
    overrides = Dict("image.repository" => image_repository(K8S_DEPUTY_IMAGE),
                     "image.tag" => image_tag(K8S_DEPUTY_IMAGE),
                     "command" => ["/bin/sh", "-c", "julia entrypoint.jl"],
                     "lifecycle" => nothing,
                     "terminationGracePeriodSeconds" => grace_period)

    local pod, delete_duration
    install_chart(chart_name, overrides) do
        pod = Pod("$chart_name-k8s-deputy")
        delete_started = time()
        delete(pod)
        wait(pod)
        delete_duration = time() - delete_started
    end

    logs = String(take!(pod.logs))
    @test delete_duration > grace_period
    @test !contains(logs, "signal (15): Terminated")
    @test !any(event -> event.reason == "FailedPreStopHook", get_events(pod).items)
end

@testset "Container halts before preStop completes" begin
    chart_name = "integration"
    grace_period = 3
    overrides = Dict("image.repository" => image_repository(K8S_DEPUTY_IMAGE),
                     "image.tag" => image_tag(K8S_DEPUTY_IMAGE),
                     "command" => ["julia", "entrypoint.jl"],
                     "terminationGracePeriodSeconds" => grace_period)

    local pod, delete_duration
    install_chart(chart_name, overrides) do
        pod = Pod("$chart_name-k8s-deputy")
        delete_started = time()
        delete(pod)
        wait(pod)
        delete_duration = time() - delete_started
    end

    logs = String(take!(pod.logs))
    @test delete_duration < grace_period
    @test !contains(logs, "signal (15): Terminated")
    @test any(event -> event.reason == "FailedPreStopHook", get_events(pod).items)
end

@testset "Missing post Julia entrypoint delay" begin
    chart_name = "integration"
    grace_period = 3
    overrides = Dict("image.repository" => image_repository(K8S_DEPUTY_IMAGE),
                     "image.tag" => image_tag(K8S_DEPUTY_IMAGE),
                     "command" => ["/bin/sh", "-c", "julia entrypoint.jl"],
                     "terminationGracePeriodSeconds" => grace_period)

    local pod, delete_duration
    install_chart(chart_name, overrides) do
        pod = Pod("$chart_name-k8s-deputy")
        delete_started = time()
        delete(pod)
        wait(pod)
        delete_duration = time() - delete_started
    end

    logs = String(take!(pod.logs))
    @test delete_duration < grace_period
    @test !contains(logs, "signal (15): Terminated")
    @test any(event -> event.reason == "FailedPreStopHook", get_events(pod).items)
end

@testset "Valid" begin
    chart_name = "integration"
    grace_period = 3
    overrides = Dict("image.repository" => image_repository(K8S_DEPUTY_IMAGE),
                     "image.tag" => image_tag(K8S_DEPUTY_IMAGE),
                     "command" => ["/bin/sh", "-c", "julia entrypoint.jl; sleep 1"],
                     "terminationGracePeriodSeconds" => grace_period)

    local pod, delete_duration
    install_chart(chart_name, overrides) do
        pod = Pod("$chart_name-k8s-deputy")
        delete_started = time()
        delete(pod)
        wait(pod)
        delete_duration = time() - delete_started
    end

    logs = String(take!(pod.logs))
    @test delete_duration < grace_period
    @test !contains(logs, "signal (15): Terminated")
    @test !any(event -> event.reason == "FailedPreStopHook", get_events(pod).items)
end
