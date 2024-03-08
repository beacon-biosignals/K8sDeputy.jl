@testset "graceful_terminator" begin
    @testset "Julia entrypoint" begin
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

        # When no PID is passed in the process ID is read from the Julia entrypoint file.
        # Blocks untils the process terminates.
        @test graceful_terminate() === nothing

        @test process_exited(p)
        @test p.exitcode == 2

        output = String(take!(buffer))
        expected = """
            [ Info: GRACEFUL TERMINATION HANDLER
            [ Info: SHUTDOWN COMPLETE
            """
        @test output == expected
    end

    @testset "multiple Julia processes" begin
        code = quote
            using K8sDeputy
            atexit(() -> @info "SHUTDOWN COMPLETE")
            graceful_terminator(; set_entrypoint=false) do
                @info "GRACEFUL TERMINATION HANDLER"
                exit(2)
                return nothing
            end
            sleep(60)
        end

        cmd = `$(Base.julia_cmd()) --color=no -e $code`
        buffer1 = IOBuffer()
        buffer2 = IOBuffer()
        p1 = run(pipeline(cmd; stdout=buffer1, stderr=buffer1); wait=false)
        p2 = run(pipeline(cmd; stdout=buffer2, stderr=buffer2); wait=false)
        @test timedwait(() -> process_running(p1) && process_running(p2), Second(5)) === :ok

        # Allow some time for Julia to startup and the graceful terminator to be registered.
        sleep(3)

        # Blocks untils the process terminates
        @test graceful_terminate(getpid(p1)) === nothing
        @test graceful_terminate(getpid(p2)) === nothing
        @test process_exited(p1)
        @test process_exited(p2)

        output1 = String(take!(buffer1))
        output2 = String(take!(buffer2))
        expected = """
            [ Info: GRACEFUL TERMINATION HANDLER
            [ Info: SHUTDOWN COMPLETE
            """
        @test output1 == expected
        @test output2 == expected
    end
end
