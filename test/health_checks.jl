@testset "Custom Health Checks" begin
    @testset "HealthCheckResult" begin
        # Test basic construction
        result = HealthCheckResult(true)
        @test result.healthy == true
        @test isnothing(result.message)
        @test isempty(result.details)
        @test result.duration_ms == 0.0
        
        # Test with all parameters
        result = HealthCheckResult(false, "Database down", Dict("error" => "timeout"), 100.5)
        @test result.healthy == false
        @test result.message == "Database down"
        @test result.details["error"] == "timeout"
        @test result.duration_ms == 100.5
    end
    
    @testset "HealthCheck" begin
        check_fn = () -> HealthCheckResult(true)
        check = HealthCheck("test", check_fn)
        @test check.name == "test"
        @test check.critical == true
        @test isempty(check.tags)
        
        # Test with optional parameters
        check = HealthCheck("test2", check_fn, critical=false, tags=["liveness", "database"])
        @test check.critical == false
        @test "liveness" in check.tags
        @test "database" in check.tags
    end
    
    @testset "Deputy with custom health checks" begin
        deputy = Deputy(check_timeout=Second(2))
        
        @test isempty(deputy.custom_health_checks)
        @test deputy.check_timeout == Second(2)
        
        # Register a health check
        register_health_check!(deputy, "test_check", tags=["liveness"]) do
            return HealthCheckResult(true, "All good")
        end
        
        @test haskey(deputy.custom_health_checks, "test_check")
        @test deputy.custom_health_checks["test_check"].name == "test_check"
        
        # Unregister health check
        unregister_health_check!(deputy, "test_check")
        @test !haskey(deputy.custom_health_checks, "test_check")
    end
    
    @testset "run_health_checks" begin
        deputy = Deputy()
        
        # Register multiple health checks
        call_count = Ref(0)
        register_health_check!(deputy, "check1", tags=["liveness"]) do
            call_count[] += 1
            return HealthCheckResult(true, "Check 1 OK")
        end
        
        register_health_check!(deputy, "check2", tags=["readiness"]) do
            call_count[] += 1
            return HealthCheckResult(false, "Check 2 Failed")
        end
        
        register_health_check!(deputy, "check3", tags=["liveness", "readiness"]) do
            call_count[] += 1
            return HealthCheckResult(true, "Check 3 OK")
        end
        
        # Run all checks
        results = run_health_checks(deputy)
        @test length(results) == 3
        @test results["check1"].healthy == true
        @test results["check2"].healthy == false
        @test results["check3"].healthy == true
        @test call_count[] == 3
        
        # Run checks filtered by tag
        call_count[] = 0
        results = run_health_checks(deputy, tags=["liveness"])
        @test length(results) == 2
        @test haskey(results, "check1")
        @test haskey(results, "check3")
        @test !haskey(results, "check2")
        @test call_count[] == 2
    end
    
    @testset "health check timeout" begin
        deputy = Deputy(check_timeout=Second(1))
        
        register_health_check!(deputy, "slow_check") do
            sleep(2)  # Longer than timeout
            return HealthCheckResult(true)
        end
        
        results = run_health_checks(deputy)
        @test results["slow_check"].healthy == false
        @test occursin("timed out", results["slow_check"].message)
    end
    
    @testset "health check exception handling" begin
        deputy = Deputy()
        
        register_health_check!(deputy, "failing_check") do
            error("Unexpected error")
        end
        
        results = run_health_checks(deputy)
        @test results["failing_check"].healthy == false
        @test occursin("exception", results["failing_check"].message)
    end
    
    @testset "health_status" begin
        deputy = Deputy()
        readied!(deputy)
        
        # Register health checks
        register_health_check!(deputy, "critical_check", critical=true) do
            return HealthCheckResult(true, "Critical check OK")
        end
        
        register_health_check!(deputy, "non_critical_check", critical=false) do
            return HealthCheckResult(false, "Non-critical check failed")
        end
        
        status = health_status(deputy)
        @test status.healthy == true  # Non-critical failure doesn't affect overall health
        @test haskey(status.checks, "ready")
        @test haskey(status.checks, "live")
        @test haskey(status.checks, "critical_check")
        @test haskey(status.checks, "non_critical_check")
        
        # Make critical check fail
        unregister_health_check!(deputy, "critical_check")
        register_health_check!(deputy, "critical_check", critical=true) do
            return HealthCheckResult(false, "Critical check failed")
        end
        
        status = health_status(deputy)
        @test status.healthy == false  # Critical failure affects overall health
    end
    
    @testset "enhanced endpoints with custom checks" begin
        deputy = Deputy()
        port = rand(EPHEMERAL_PORT_RANGE)
        
        # Register health checks
        register_health_check!(deputy, "liveness_check", tags=["liveness"]) do
            return HealthCheckResult(true, "Liveness OK")
        end
        
        register_health_check!(deputy, "readiness_check", tags=["readiness"]) do
            return HealthCheckResult(true, "Readiness OK")
        end
        
        server = serve!(deputy, localhost, port; verbose=-1)
        
        try
            # Test liveness endpoint with JSON
            r = HTTP.get("http://$localhost:$port/health/live", 
                        ["Accept" => "application/json"])
            @test r.status == 200
            body = String(r.body)
            @test occursin("healthy", body)
            
            # Test readiness endpoint
            readied!(deputy)
            r = HTTP.get("http://$localhost:$port/health/ready",
                        ["Accept" => "application/json"])
            @test r.status == 200
            
            # Test comprehensive health endpoint
            r = HTTP.get("http://$localhost:$port/health")
            @test r.status == 200
            body = String(r.body)
            @test occursin("healthy", body)
            @test occursin("liveness_check", body)
            @test occursin("readiness_check", body)
        finally
            close(server)
        end
    end
    
    @testset "to_dict conversions" begin
        # Test HealthCheckResult to_dict
        result = HealthCheckResult(true, "Test message", Dict("key" => "value"), 50.0)
        dict = K8sDeputy.to_dict(result)
        @test dict["healthy"] == true
        @test dict["message"] == "Test message"
        @test dict["details"]["key"] == "value"
        @test dict["duration_ms"] == 50.0
        
        # Test HealthStatus to_dict
        checks = Dict(
            "check1" => HealthCheckResult(true, "OK"),
            "check2" => HealthCheckResult(false, "Failed")
        )
        status = HealthStatus(false, checks)
        dict = K8sDeputy.to_dict(status)
        @test dict["healthy"] == false
        @test haskey(dict, "timestamp")
        @test dict["checks"]["check1"]["healthy"] == true
        @test dict["checks"]["check2"]["healthy"] == false
    end
end