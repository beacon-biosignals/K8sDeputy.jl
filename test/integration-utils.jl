using kubectl_jll
using UUIDs
using JSON3: JSON3

# TODO: Would be great if we could use the UID for all requests
mutable struct Pod
    name::String
    uid::UUID
    logs::IOBuffer
    logs_process::Base.Process

    function Pod(name::AbstractString)
        pod = new(name)
        pod.uid = get_uid(pod)
        pod.logs = IOBuffer()
        pod.logs_process = monitor_logs(pod.logs, pod)
        return pod
    end
end

Base.print(io::IO, p::Pod) = print(io, "pod/", p.name)

function get_uid(p::Pod)
    cmd = `$(kubectl()) get $p -o jsonpath="{.metadata.uid}"`
    err = IOBuffer()
    uid = readchomp(pipeline(ignorestatus(cmd), stderr=err))

    err.size > 0 && error(String(take!(err)))
    return parse(UUID, uid)
end

function monitor_logs(io::IO, p::Pod)
    cmd = `$(kubectl()) logs -f $p`
    return run(pipeline(cmd; stdout=io); wait=false)
end

# TODO: Confirm that pod UID contains FailedPreStopHook
function get_events(p::Pod)
    cmd = `$(kubectl()) get events --field-selector involvedObject.uid=$(p.uid) -o json`
    err = IOBuffer()
    out = readchomp(pipeline(ignorestatus(cmd), stderr=err))

    err.size > 0 && error(String(take!(err)))
    return JSON3.read(out)
end

function delete(p::Pod; wait::Bool=true)
    cmd = `$(kubectl()) delete $p --wait=$wait`
    err = IOBuffer()
    run(pipeline(ignorestatus(cmd), stdout=devnull, stderr=err))

    err.size > 0 && error(String(take!(err)))
    return nothing
end

function Base.wait(p::Pod)
    cmd = `$(kubectl()) wait --for=delete $p`
    err = IOBuffer()
    run(pipeline(ignorestatus(cmd), stdout=devnull, stderr=err))

    err.size > 0 && error(String(take!(err)))
    return nothing
end

function install_chart(name::AbstractString, overrides=Dict(); quiet::Bool=true)
    chart = joinpath(@__DIR__(), "integration", "chart", "k8s-deputy")
    options = `--set kind=pod`
    for (k, v) in pairs(overrides)
        options = if v isa AbstractArray || v isa AbstractDict || v isa Nothing
            `$options --set-json $k=$(JSON3.write(v))`
        else
            `$options --set-literal $k=$v`
        end
    end
    stdout = quiet ? devnull : Base.stdout
    run(pipeline(`helm uninstall $name --ignore-not-found`; stdout))
    run(pipeline(`helm install $name $chart --wait $options`; stdout))
end

function install_chart(body, name::AbstractString, overrides=Dict(); quiet::Bool=true)
    local result
    stdout = quiet ? devnull : Base.stdout
    install_chart(name, overrides; quiet)
    try
        result = body()
    finally
        run(pipeline(`helm uninstall $name`; stdout))
    end
    return result
end
