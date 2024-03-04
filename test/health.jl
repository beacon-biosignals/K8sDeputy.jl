function exit_patcher(rc::Ref{Int})
    atexit_hooks = []
    return [@patch Base.atexit(f) = push!(atexit_hooks, f)
            @patch function Base.exit(n)
                rc[] = n
                while !isempty(atexit_hooks)
                    pop!(atexit_hooks)()
                end
            end]
end

@testset "Deputy" begin
    @testset "basic" begin
        deputy = Deputy()
        @test !deputy.ready
        @test !deputy.shutting_down

        readied(deputy)
        @test deputy.ready
        @test !deputy.shutting_down
    end

    @testset "live_endpoint / ready_endpoint" begin
        deputy = Deputy()
        request = HTTP.Request()

        # Note: Users should not mutate the internal state of a `Deputy`
        # TODO: Define `==(x::HTTP.Response, y::HTTP.Response)`.

        deputy.ready = false
        r = ready_endpoint(deputy)(request)
        @test r.status == 503
        @test isempty(String(r.body))

        deputy.ready = true
        r = ready_endpoint(deputy)(request)
        @test r.status == 200
        @test isempty(String(r.body))

        deputy.shutting_down = false
        r = live_endpoint(deputy)(request)
        @test r.status == 200
        @test isempty(String(r.body))

        deputy.shutting_down = true
        r = live_endpoint(deputy)(request)
        @test r.status == 503
        @test isempty(String(r.body))
    end

    # Note: If a non-mocked `exit(0)` is called it may appear that all tests have passed.
    @testset "shutdown" begin
        @testset "default handler" begin
            deputy = Deputy()

            rc = Ref{Int}()
            logs = [(:info, "SHUTDOWN COMPLETE")]
            @test_logs(logs...,
                       apply(exit_patcher(rc)) do
                           @mock atexit(() -> @info "SHUTDOWN COMPLETE")
                           return shutdown(deputy)
                       end)

            @test isassigned(rc)
            @test rc[] == 1
        end

        @testset "custom handler" begin
            deputy = nothing

            shutdown_handler = function ()
                @info "SHUTDOWN HANDLER"
                @info "shutting_down = $(deputy.shutting_down)"
            end

            deputy = Deputy(; shutdown_handler)

            rc = Ref{Int}()
            logs = [(:info, "SHUTDOWN HANDLER"),
                    (:info, "shutting_down = true"),
                    (:info, "SHUTDOWN COMPLETE")]
            @test_logs(logs...,
                       apply(exit_patcher(rc)) do
                           @mock atexit(() -> @info "SHUTDOWN COMPLETE")
                           return shutdown(deputy)
                       end)

            @test isassigned(rc)
            @test rc[] == 1
        end

        @testset "handler exception" begin
            shutdown_handler = () -> error("failure")
            deputy = Deputy(; shutdown_handler)

            rc = Ref{Int}()
            logs = [(:error, "Shutdown handler failed"),
                    (:info, "SHUTDOWN COMPLETE")]
            @test_logs(logs...,
                       apply(exit_patcher(rc)) do
                           @mock atexit(() -> @info "SHUTDOWN COMPLETE")
                           return shutdown(deputy)
                       end)

            @test isassigned(rc)
            @test rc[] == 1
        end

        @testset "timeout" begin
            shutdown_handler = function ()
                @info "SHUTDOWN HANDLER"
                sleep(10)
                @info "SHOULD NEVER BE SEEN"
                return nothing
            end

            deputy = Deputy(; shutdown_handler, shutdown_handler_timeout=Second(1))

            rc = Ref{Int}()
            logs = [(:info, "SHUTDOWN HANDLER"),
                    (:warn, "Shutdown handler still running after 1 second"),
                    (:info, "SHUTDOWN COMPLETE")]
            @test_logs(logs...,
                       apply(exit_patcher(rc)) do
                           @mock atexit(() -> @info "SHUTDOWN COMPLETE")
                           return shutdown(deputy)
                       end)

            @test isassigned(rc)
            @test rc[] == 1
        end

        @testset "exit" begin
            code = quote
                using K8sDeputy, Dates

                shutdown_handler() = @info "SHUTDOWN HANDLER"
                atexit(() -> @info "SHUTDOWN COMPLETE")

                deputy = Deputy(; shutdown_handler, shutdown_handler_timeout=Second(1))
                shutdown(deputy)
            end

            cmd = `$(Base.julia_cmd()) --color=no -e $code`
            buffer = IOBuffer()
            p = run(pipeline(cmd; stdout=buffer, stderr=buffer); wait=false)

            @test timedwait(() -> process_exited(p), Second(10)) === :ok
            @test p.exitcode == 1

            output = String(take!(buffer))
            expected = """
                [ Info: SHUTDOWN HANDLER
                [ Info: SHUTDOWN COMPLETE
                """
            @test output == expected
        end
    end

    @testset "serve!" begin
        deputy = Deputy()
        port = rand(EPHEMERAL_PORT_RANGE)
        server = serve!(deputy, localhost, port)

        try
            r = HTTP.get("http://localhost:$port/health/ready"; status_exception=false)
            @test r.status == 503

            r = HTTP.get("http://localhost:$port/health/live")
            @test r.status == 200

            readied(deputy)

            r = HTTP.get("http://localhost:$port/health/ready")
            @test r.status == 200

            r = HTTP.get("http://localhost:$port/health/live")
            @test r.status == 200

            # Faking shutting down. Normal usage would call `shutdown` but we don't want to
            # terminate our test process.
            deputy.shutting_down = true

            r = HTTP.get("http://localhost:$port/health/ready")
            @test r.status == 200

            r = HTTP.get("http://localhost:$port/health/live"; status_exception=false)
            @test r.status == 503
        finally
            close(server)
        end
    end

    @testset "graceful termination" begin
        port = rand(EPHEMERAL_PORT_RANGE)
        code = quote
            using K8sDeputy, Sockets

            shutdown_handler() = @info "SHUTDOWN HANDLER"
            atexit(() -> @info "SHUTDOWN COMPLETE")

            deputy = Deputy(; shutdown_handler)
            graceful_terminator() do
                @info "GRACEFUL TERMINATION HANDLER"
                shutdown(deputy)
                return nothing
            end
            K8sDeputy.serve!(deputy, Sockets.localhost, $port)
            readied(deputy)
            sleep(60)
        end

        cmd = `$(Base.julia_cmd()) --color=no -e $code`
        buffer = IOBuffer()
        p = run(pipeline(cmd; stdout=buffer, stderr=buffer); wait=false)
        @test timedwait(() -> process_running(p), Second(5)) === :ok
        @test timedwait(Second(10)) do
            r = HTTP.get("http://localhost:$port/health/ready"; status_exception=false)
            return r.status == 200
        end === :ok

        graceful_terminate(getpid(p))  # Blocks untils the HTTP server goes down
        @test process_exited(p)
        @test p.exitcode == 1

        output = String(take!(buffer))
        expected = """
            [ Info: Listening on: 127.0.0.1:$port, thread id: 1
            [ Info: GRACEFUL TERMINATION HANDLER
            [ Info: SHUTDOWN HANDLER
            [ Info: SHUTDOWN COMPLETE
            """
        @test output == expected
    end
end
