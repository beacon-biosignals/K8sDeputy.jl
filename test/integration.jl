tag = "latest"

# Verify Julia's handling of the `TERM` signal in a K8s environment
@testset "SIGTERM graceful termination" begin
    chart_name = "integration"
    grace_period = 3
    overrides = Dict("command" => ["julia", "entrypoint.jl"],
                     "lifecycle" => nothing,
                     "terminationGracePeriodSeconds" => grace_period)
    install_chart(chart_name, tag, overrides)

    pod = Pod("$chart_name-k8s-deputy")
    delete_started = time()
    delete(pod)
    wait(pod)
    delete_duration = time() - delete_started

    # # Determine when the "delete" command was received by the server
    # event_items = events(pod).items
    # delete_event = last(filter(event -> event.reason == "Killing", event_items))
    # delete_event_timestamp = parse(DateTime, delete_event.lastTimestamp, dateformat"yyyy-mm-dd\THH:MM:SS\Z")

    logs = String(take!(pod.logs))
    @test delete_duration < grace_period
    @test contains(logs, "[1] signal (15): Terminated\nin expression starting at")
    @test !any(event -> event.reason == "FailedPreStopHook", events(pod).items)
end

# Verify Julia's handling of the `TERM` signal in a K8s environment
@testset "Ignore SIGTERM graceful termination" begin
    chart_name = "integration"
    grace_period = 3
    # Child processes don't automatically get forwarded signals
    overrides = Dict("command" => ["/bin/sh", "-c", "julia entrypoint.jl"]
                     "lifecycle" => nothing,
                     "terminationGracePeriodSeconds" => grace_period)
    install_chart(chart_name, tag, overrides)

    pod = Pod("$chart_name-k8s-deputy")
    delete_started = time()
    delete(pod)
    wait(pod)
    delete_duration = time() - delete_started

    logs = String(take!(pod.logs))
    @test delete_duration > grace_period
    @test !contains(logs, "signal (15): Terminated")
    @test !any(event -> event.reason == "FailedPreStopHook", events(pod).items)
end

@testset "Container halts before preStop completes" begin
    chart_name = "integration"
    grace_period = 3
    overrides = Dict("command" => ["julia", "entrypoint.jl"],
                     "terminationGracePeriodSeconds" => grace_period)
    install_chart(chart_name, tag, overrides)

    pod = Pod("$chart_name-k8s-deputy")
    delete_started = time()
    delete(pod)
    wait(pod)
    delete_duration = time() - delete_started

    @test delete_duration < grace_period
    logs = String(take!(pod.logs))
    @test !contains(logs, "signal (15): Terminated")
    @test any(event -> event.reason == "FailedPreStopHook", events(pod).items)
end

@testset "Post Julia entrypoint delay missing" begin
    chart_name = "integration"
    grace_period = 3
    overrides = Dict("command" => ["/bin/sh", "-c", "julia entrypoint.jl"],
                     "terminationGracePeriodSeconds" => grace_period)
    install_chart(chart_name, tag, overrides)

    pod = Pod("$chart_name-k8s-deputy")
    delete_started = time()
    delete(pod)
    wait(pod)
    delete_duration = time() - delete_started

    @test delete_duration < grace_period
    logs = String(take!(pod.logs))
    @test !contains(logs, "signal (15): Terminated")
    @test any(event -> event.reason == "FailedPreStopHook", events(pod).items)
end
