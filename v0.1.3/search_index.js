var documenterSearchIndex = {"docs":
[{"location":"api/#API","page":"API","title":"API","text":"","category":"section"},{"location":"api/","page":"API","title":"API","text":"Deputy\nK8sDeputy.serve!\nreadied!\nshutdown!\ngraceful_terminator\ngraceful_terminate","category":"page"},{"location":"api/#K8sDeputy.Deputy","page":"API","title":"K8sDeputy.Deputy","text":"Deputy(; shutdown_handler=nothing, shutdown_handler_timeout::Period=Second(5))\n\nConstruct an application Deputy which provides health check endpoints.\n\nKeywords\n\nshutdown_handler (optional): A zero-argument function which allows the user to provide a custom callback function for when shutdown!(::Deputy) is called.\nshutdown_handler_timeout::Period (optional): Specifies the maximum execution duration of a shutdown_handler.\n\n\n\n\n\n","category":"type"},{"location":"api/#K8sDeputy.serve!","page":"API","title":"K8sDeputy.serve!","text":"K8sDeputy.serve!(deputy::Deputy, [host], [port::Integer]; kwargs...) -> HTTP.Server\n\nStarts a non-blocking HTTP.Server responding to requests to deputy health checks. The following health check endpoints are available:\n\n/health/live: Is the server is alive/running?\n/health/ready: Is the server ready (has readied!(deputy) been called)?\n\nThese endpoints will respond with HTTP status 200 OK on success or 503 Service Unavailable on failure.\n\nArguments\n\nhost (optional): The address to listen to for incoming requests. Defaults to Sockets.localhost.\nport::Integer (optional): The port to listen on. Defaults to the port number specified by the environmental variable DEPUTY_HEALTH_CHECK_PORT, otherwise 8081.\n\nAny kwargs provided are passed to HTTP.serve!.\n\n\n\n\n\n","category":"function"},{"location":"api/#K8sDeputy.readied!","page":"API","title":"K8sDeputy.readied!","text":"readied!(deputy::Deputy) -> Nothing\n\nMark the application as \"ready\". Sets the readiness endpoint to respond with successful responses.\n\n\n\n\n\n","category":"function"},{"location":"api/#K8sDeputy.shutdown!","page":"API","title":"K8sDeputy.shutdown!","text":"shutdown!(deputy::Deputy) -> Nothing\n\nInitiates a shutdown of the application by:\n\nMark the application as shutting down (\"non-live\").\nExecuting the deputy's shutdown_handler (if defined).\nExiting the current Julia process.\n\nIf a deputy.shutdown_handler is defined it must complete within the deputy.shutdown_handler_timeout or a warning will be logged and the Julia process will immediately exit. Any exceptions that occur in the deputy.shutdown_handler will also be logged and result in the Julia process exiting.\n\nA shutdown_handler may optionally call exit if a user wants to specify the exit status. By default shutdown! uses an exit status of 1.\n\n\n\n\n\n","category":"function"},{"location":"api/#K8sDeputy.graceful_terminator","page":"API","title":"K8sDeputy.graceful_terminator","text":"graceful_terminator(f; set_entrypoint::Bool=true) -> Nothing\n\nRegister a zero-argument function to be called when graceful_terminate is called targeting this process. The user-defined function f is expected to call exit to terminate the Julia process. The graceful_terminator function is only allowed to be called once within a Julia process.\n\nKeywords\n\nset_entrypoint::Bool (optional): Sets the calling Julia process as the \"entrypoint\" to be targeted by default when running graceful_terminate in another Julia process. Users who want to utilize graceful_terminator in multiple Julia processes should use set_entrypoint=false and specify process IDs when calling graceful_terminate. Defaults to true.\n\nExamples\n\napp_status = AppStatus()\ngraceful_terminator(() -> shutdown!(app_status))\n\nKubernetes Setup\n\nWhen using Kubernetes (K8s) you can enable graceful termination of a Julia process by defining a pod preStop container hook. Typically, K8s initiates graceful termination via the TERM signal but as Julia forcefully terminates when receiving this signal and Julia does not support user-defined signal handlers we utilize preStop instead.\n\nThe following K8s pod manifest snippet will specify K8s to call the user-defined function specified by the graceful_terminator:\n\nspec:\n  containers:\n    - lifecycle:\n        preStop:\n          exec:\n            command: [\"julia\", \"-e\", \"using K8sDeputy; graceful_terminate()\"]\n\nAdditionally, the entrypoint for the container should also not directly use the Julia process as the init process (PID 1). Instead, users should define their entrypoint similarly to [\"/bin/sh\", \"-c\", \"julia entrypoint.jl; sleep 1\"] as this allows for both the Julia process and the preStop process to cleanly terminate.\n\n\n\n\n\n","category":"function"},{"location":"api/#K8sDeputy.graceful_terminate","page":"API","title":"K8sDeputy.graceful_terminate","text":"graceful_terminate(pid::Int32=entrypoint_pid(); wait::Bool=true) -> Nothing\n\nInitiates the execution of the graceful_terminator user callback in the process pid. See graceful_terminator for more details.\n\n\n\n\n\n","category":"function"},{"location":"quickstart/#Quickstart","page":"Quickstart","title":"Quickstart","text":"","category":"section"},{"location":"quickstart/","page":"Quickstart","title":"Quickstart","text":"For users who want to get started quickly you can use the following template to incorporate liveness probes, readiness probes, graceful termination, binding to non-priviledged ports, and read-only filesystem support.","category":"page"},{"location":"quickstart/","page":"Quickstart","title":"Quickstart","text":"Add K8sDeputy.jl to your Julia project: Pkg.add(\"K8sDeputy\")\nDefine the following entrypoint.jl in your application and include it in the WORKDIR of your Dockerfile:\nusing K8sDeputy\ndeputy = Deputy()\nserver = K8sDeputy.serve!(deputy, \"0.0.0.0\")\ngraceful_terminator(() -> shutdown!(deputy))\n\n# Application initialization code\n\nreadied!(deputy)\n\n# Application code\nIncorporate the following changes into your K8s resource manifest:\napiVersion: v1\nkind: Pod\nspec:\n  containers:\n    - name: app\n      command: [\"/bin/sh\", \"-c\", \"julia entrypoint.jl; sleep 1\"]\n      env:\n        - name: DEPUTY_IPC_DIR\n          value: /mnt/deputy-ipc\n      ports:\n        - name: health-check\n          containerPort: 8081  # Default K8sDeputy.jl heath check port\n          protocol: TCP\n      livenessProbe:\n        httpGet:\n          path: /health/live\n          port: health-check\n        timeoutSeconds: 5\n      readinessProbe:\n        httpGet:\n          path: /health/ready\n          port: health-check\n        timeoutSeconds: 5\n      lifecycle:\n        preStop:\n          exec:\n            command: [\"julia\", \"-e\", \"using K8sDeputy; graceful_terminate()\"]\n      securityContext:\n        capabilities:\n          drop:\n            - all\n        readOnlyRootFilesystem: true\n      volumeMounts:\n        - mountPath: /mnt/deputy-ipc\n          name: deputy-ipc\n  terminationGracePeriodSeconds: 30\n  volumes:\n    - name: deputy-ipc\n      emptyDir:\n        medium: Memory","category":"page"},{"location":"graceful_termination/#Graceful-Termination","page":"Graceful Termination","title":"Graceful Termination","text":"","category":"section"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"Kubernetes (K8s) applications are expected to handle graceful termination. Typically, applications will initiate a graceful termination by handling the TERM signal when a K8s pod is to be terminated.","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"At this point in time Julia does not provide user-definable signal handlers and the internal Julia signal handler for TERM results in the process reporting the signal (with a stack trace) to standard error and exiting. Julia provides users with atexit to define callbacks when Julia is terminating but unfortunately this callback system only allows for trivial actions to occur when Julia is shutdown due to handling the TERM signal.","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"These limitations resulted in K8sDeputy.jl providing an alternative path for handling graceful termination Julia processes. This avoids logging unnecessary error messages and also provides a reliable shutdown callback system for graceful termination.","category":"page"},{"location":"graceful_termination/#Interface","page":"Graceful Termination","title":"Interface","text":"","category":"section"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"The K8sDeputy.jl package provides the graceful_terminator function for registering a single user callback upon receiving a graceful termination event. The graceful_terminate function can be used from another Julia process to terminate the graceful_terminator caller process. For example run the following code in an interactive Julia REPL:","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"using K8sDeputy\ngraceful_terminator(() -> (@info \"Gracefully terminating...\"; exit()))","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"In another terminal run the following code to initiate graceful termination:","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"julia -e 'using K8sDeputy; graceful_terminate()'","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"Once graceful_terminate has been called the first process will: execute the callback, log the message, and exit the Julia process.","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"note: Note\nBy default the graceful_terminator function registers the caller Julia process as the \"entrypoint\" Julia process. Primarily, this allows for out-of-the-box support for Julia applications running as non-init processes but only allows one Julia process to be defined as the \"entrypoint\". If you require multiple Julia processes to support graceful termination concurrently you can use set_entrypoint=false (e.g. graceful_terminator(...; set_entrypoint=false)) and pass in the target process ID to graceful_terminate.","category":"page"},{"location":"graceful_termination/#Deputy-Integration","page":"Graceful Termination","title":"Deputy Integration","text":"","category":"section"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"The graceful_terminator function can be combined with the deputy's shutdown! function to allow graceful termination of the application and the deputy:","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"using K8sDeputy\ndeputy = Deputy(; shutdown_handler=() -> @info \"Shutting down\")\nserver = K8sDeputy.serve!(deputy, \"0.0.0.0\")\ngraceful_terminator(() -> shutdown!(deputy))\n\n# Application code","category":"page"},{"location":"graceful_termination/#Kubernetes-Setup","page":"Graceful Termination","title":"Kubernetes Setup","text":"","category":"section"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"To configure your K8s container resource to call graceful_terminate when terminating you can configure a preStop hook:","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"apiVersion: v1\nkind: Pod\nspec:\n  containers:\n    - name: app\n      # command: [\"/bin/sh\", \"-c\", \"julia entrypoint.jl; sleep 1\"]\n      lifecycle:\n        preStop:\n          exec:\n            command: [\"julia\", \"-e\", \"using K8sDeputy; graceful_terminate()\"]\n  # terminationGracePeriodSeconds: 30","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"note: Note\nApplications with slow shutdown callbacks may want to consider specifying terminationGracePeriodSeconds which specifies the maximum duration a pod can take when gracefully terminating. Once the timeout is reached the processes running in the pod are forcibly halted with a KILL signal.","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"Finally, the entrypoint for the container should also not directly use the Julia as the init process (PID 1). Instead, users should define their entrypoint similarly to [\"/bin/sh\", \"-c\", \"julia entrypoint.jl; sleep 1\"] as this allows both the Julia process and the preStop process to cleanly terminate.","category":"page"},{"location":"graceful_termination/#Read-only-Filesystem","page":"Graceful Termination","title":"Read-only Filesystem","text":"","category":"section"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"If you have a read-only filesystem on your container you'll need to configure a writeable volume mount for K8sDeputy.jl. The DEPUTY_IPC_DIR environmental variable can be used to instruct K8sDeputy.jl where to store the named pipes it creates for interprocess communication:","category":"page"},{"location":"graceful_termination/","page":"Graceful Termination","title":"Graceful Termination","text":"apiVersion: v1\nkind: Pod\nspec:\n  containers:\n    - name: app\n      # command: [\"/bin/sh\", \"-c\", \"julia entrypoint.jl; sleep 1\"]\n      env:\n        - name: DEPUTY_IPC_DIR\n          value: /mnt/deputy-ipc\n      lifecycle:\n        preStop:\n          exec:\n            command: [\"julia\", \"-e\", \"using K8sDeputy; graceful_terminate()\"]\n      securityContext:\n        readOnlyRootFilesystem: true\n      volumeMounts:\n        - mountPath: /mnt/deputy-ipc\n          name: deputy-ipc\n  volumes:\n    - name: deputy-ipc\n      emptyDir:\n        medium: Memory","category":"page"},{"location":"health_checks/#Health-Checks","page":"Health Checks","title":"Health Checks","text":"","category":"section"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"K8sDeputy.jl provides the following health endpoints:","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"/health/live\n/health/ready","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"These endpoints respond with HTTP status 200 OK on success or 503 Service Unavailable on failure.","category":"page"},{"location":"health_checks/#Supporting-liveness-probes","page":"Health Checks","title":"Supporting liveness probes","text":"","category":"section"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"In order to enable liveness probes you will need to start the K8sDeputy health check server from within your application:","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"using K8sDeputy\ndeputy = Deputy()\nK8sDeputy.serve!(deputy, \"0.0.0.0\")\n\n# Application code","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"note: Note\nWe specify the HTTP service to listen to all addresses (i.e. 0.0.0.0) on the container as the K8s kubelet which uses the livenessProbe executes the requests from outside of the container.","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"Once K8sDeputy.serve! has been called the HTTP based liveness endpoint should now return successful responses.","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"Probe requests prior to running K8sDeputy.serve! will return failure responses. Application developers should consider starting the health check endpoints before running slow application initialization code. Alternatively, an initialDelaySeconds can be added to the livenessProbe.","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"You'll also need to configure your K8s container resource to specify the livenessProbe. For example here's a partial manifest for a K8s pod:","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"apiVersion: v1\nkind: Pod\nspec:\n  containers:\n    - name: app\n      ports:\n        - name: health-check\n          containerPort: 8081  # The default K8sDeputy.jl heath check port\n          protocol: TCP\n      livenessProbe:\n        httpGet:\n          path: /health/live\n          port: health-check\n        timeoutSeconds: 5","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"note: Note\nK8s probes require that applications must respond to the probe requests in under timeoutSeconds (defaults to 1 second). Since Julia's HTTP.jl server can be unresponsive we recommend using a timeoutSeconds of at least 5 seconds.","category":"page"},{"location":"health_checks/#Supporting-readiness-probes","page":"Health Checks","title":"Supporting readiness probes","text":"","category":"section"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"Enabling readiness probes is similar to enabling the liveness probes but requires an call to readied!:","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"using K8sDeputy\ndeputy = Deputy()\nK8sDeputy.serve!(deputy, \"0.0.0.0\")\n\n# Application initialization code\n\nreadied!(deputy)\n\n# Application code","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"When your application is ready you should declare your application as such with readied!. Doing this causes the readiness endpoint to start returning successful responses. For K8s applications responding to network traffic this endpoint is critical for ensuring timely responses to external requests. Although, defining readied! for non-network based applications is optional it can still be useful for administration/monitoring.","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"To configure your K8s container resource with a readiness probe you'll need to declare a readinessProbe in your manifest. For example here's a partial manifest for a K8s pod:","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"apiVersion: v1\nkind: Pod\nspec:\n  containers:\n    - name: app\n      ports:\n        - name: health-check\n          containerPort: 8081  # Default K8sDeputy.jl heath check port\n          protocol: TCP\n      readinessProbe:\n        httpGet:\n          path: /health/ready\n          port: health-check\n        timeoutSeconds: 5","category":"page"},{"location":"health_checks/#Shutdown","page":"Health Checks","title":"Shutdown","text":"","category":"section"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"When it is time to shutdown your application you should inform the deputy by running the shutdown! function:","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"using K8sDeputy\ndeputy = Deputy(; shutdown_handler=() -> @info \"Shutting down\")\nK8sDeputy.serve!(deputy, \"0.0.0.0\")\n\ntry\n    # Application code\nfinally\n    shutdown!(deputy)\nend","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"Once shutdown! is called the following occurs:","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"The liveness endpoint starts returning failure responses\nThe deputy's shutdown_handler is called\nThe Julia process is terminated","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"By default the shutdown_handler only has 5 seconds to complete. If your shutdown_handler requires more time to execute you can change the timeout by using the keyword shutdown_handler_timeout.","category":"page"},{"location":"health_checks/","page":"Health Checks","title":"Health Checks","text":"Depending on your application you may want to define multiple calls to shutdown!. For example you may want to call shutdown! from within graceful_terminator to enable graceful termination support for you application.","category":"page"},{"location":"#K8sDeputy.jl","page":"Home","title":"K8sDeputy.jl","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"(Image: CI) (Image: codecov) (Image: Code Style: YASGuide) (Image: Stable Documentation) (Image: Dev Documentation)","category":"page"},{"location":"","page":"Home","title":"Home","text":"Provides K8s health checks and graceful termination support on behalf of Julia services.","category":"page"}]
}
