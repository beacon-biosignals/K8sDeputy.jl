@testset "graceful_terminator / graceful_terminate" begin
    code = quote
        using K8sDeputy
        atexit(() -> @info "SHUTDOWN COMPLETE")
        graceful_terminator() do
            @info "GRACEFUL TERMINATION HANDLER"
            exit(2)
            return nothing
        end
        sleep(60)
    end

    cmd = `$(Base.julia_cmd()) --color=no -e $code`
    buffer = IOBuffer()
    p = run(pipeline(cmd; stdout=buffer, stderr=buffer); wait=false)
    @test timedwait(() -> process_running(p), Second(5)) === :ok

    # Allow some time for Julia to startup and the graceful terminator to be registered.
    sleep(3)

    @test graceful_terminate(getpid(p)) === nothing  # Blocks untils the HTTP server goes down
    @test process_exited(p)
    @test p.exitcode == 2

    output = String(take!(buffer))
    expected = """
        [ Info: GRACEFUL TERMINATION HANDLER
        [ Info: SHUTDOWN COMPLETE
        """
    @test output == expected
end
