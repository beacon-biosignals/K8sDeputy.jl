@testset "graceful_terminator" begin
    deputy_ipc_dir = mktempdir()

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
        cmd = addenv(cmd, "DEPUTY_IPC_DIR" => deputy_ipc_dir)
        buffer = IOBuffer()
        p = run(pipeline(cmd; stdout=buffer, stderr=buffer); wait=false)
        @test timedwait(() -> process_running(p), Second(5)) === :ok

        # Allow some time for Julia to startup and the graceful terminator to be registered.
        sleep(3)

        # When no PID is passed in the process ID is read from the Julia entrypoint file.
        # Blocks untils the process terminates.
        withenv("DEPUTY_IPC_DIR" => deputy_ipc_dir) do
            @test graceful_terminate() === nothing
        end

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
        cmd = addenv(cmd, "DEPUTY_IPC_DIR" => deputy_ipc_dir)
        buffer1 = IOBuffer()
        buffer2 = IOBuffer()
        p1 = run(pipeline(cmd; stdout=buffer1, stderr=buffer1); wait=false)
        p2 = run(pipeline(cmd; stdout=buffer2, stderr=buffer2); wait=false)
        @test timedwait(() -> process_running(p1) && process_running(p2), Second(5)) === :ok

        # Allow some time for Julia to startup and the graceful terminator to be registered.
        sleep(3)

        # Blocks untils the process terminates
        withenv("DEPUTY_IPC_DIR" => deputy_ipc_dir) do
            @test graceful_terminate(getpid(p1)) === nothing
            @test graceful_terminate(getpid(p2)) === nothing
        end
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

    # When users set `DEPUTY_IPC_DIR` they may be using a K8s volume. As even `emptyDir`
    # volumes persist for the lifetime of the pod we may have a UNIX-domain socket already
    # present from a previous restart.
    @testset "bind after restart" begin
        code = quote
            using K8sDeputy
            using Sockets: listen

            # Generate the socket as if the K8s pod had restarted and this path remained.
            # One difference with this setup is the process which created the socket is
            # still running so there may be a write lock on the file which definitely
            # wouldn't exist if the pod had restarted. Note that closing the socket will
            # remove the path.
            socket_path = K8sDeputy._graceful_terminator_socket_path(getpid())
            server = listen(socket_path)

            atexit(() -> @info "SHUTDOWN COMPLETE")
            graceful_terminator(; set_entrypoint=false) do
                @info "GRACEFUL TERMINATION HANDLER"
                exit(2)
                return nothing
            end
            sleep(60)
        end

        cmd = `$(Base.julia_cmd()) --color=no -e $code`
        cmd = addenv(cmd, "DEPUTY_IPC_DIR" => deputy_ipc_dir)
        buffer = IOBuffer()
        p = run(pipeline(cmd; stdout=buffer, stderr=buffer); wait=false)
        @test timedwait(() -> process_running(p), Second(5)) === :ok

        # Allow some time for Julia to startup and the graceful terminator to be registered.
        sleep(3)

        # Socket exists as a UNIX-domain socket
        socket_path = withenv("DEPUTY_IPC_DIR" => deputy_ipc_dir) do
            return K8sDeputy._graceful_terminator_socket_path(getpid(p))
        end
        @test ispath(socket_path)
        @test !isfile(socket_path)

        # Blocks untils the process terminates
        withenv("DEPUTY_IPC_DIR" => deputy_ipc_dir) do
            @test graceful_terminate(getpid(p)) === nothing
        end
        @test process_exited(p)
        @test p.exitcode == 2

        output = String(take!(buffer))
        expected = """
            [ Info: GRACEFUL TERMINATION HANDLER
            [ Info: SHUTDOWN COMPLETE
            """
        @test output == expected
    end
end
