# Health Checks

K8sDeputy.jl provides the following health endpoints:

- `/health/live`
- `/health/ready`

These endpoints respond with HTTP status `200 OK` on success or `503 Service Unavailable` on failure.

## Supporting liveness probes

In order to enable [liveness probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-command) you will need to start the K8sDeputy health check server from within your application:

```julia
using K8sDeputy
deputy = Deputy()
K8sDeputy.serve!(deputy, "0.0.0.0")

# Application code
```

!!! note

    We specify the HTTP service to listen to all addresses (i.e. `0.0.0.0`) on the container as the K8s [kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/) which uses the `livenessProbe` executes the requests from outside of the container.

Once `K8sDeputy.serve!` has been called the HTTP based liveness endpoint should now return successful responses.

Probe requests prior to running `K8sDeputy.serve!` will return failure responses. Application developers should consider starting the health check endpoints before running slow application initialization code. Alternatively, an [`initialDelaySeconds`](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#configure-probes) can be added to the `livenessProbe`.

You'll also need to configure your K8s container resource to specify the `livenessProbe`. For example here's a partial manifest for a K8s pod:

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: app
      ports:
        - name: health-check
          containerPort: 8081  # The default K8sDeputy.jl heath check port
          protocol: TCP
      livenessProbe:
        httpGet:
          path: /health/live
          port: health-check
        timeoutSeconds: 5
```

!!!note

    K8s probes require that applications must respond to the probe requests in under `timeoutSeconds` (defaults to 1 second). Since Julia's HTTP.jl server can be unresponsive we recommend using a `timeoutSeconds` of at least 5 seconds.

## Supporting readiness probes

Enabling [readiness probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-readiness-probes) is similar to [enabling the liveness probes](#supporting-liveness-probes) but requires an call to `readied`:

```julia
using K8sDeputy
deputy = Deputy()
K8sDeputy.serve!(deputy, "0.0.0.0")

# Application initialization code

readied(deputy)

# Application code
```

When you application is ready you should declare your application as "readied". Doing this causes the readiness endpoint to start returning successful responses. For K8s applications responding to network traffic this endpoint is critical for ensuring timely responses to external requests. Although, defining `readied` for non-network based applications is optional it can still be useful for administration/monitoring.

To configure your K8s container resource with a readiness probe you'll need to declare a `readinessProbe` in your manifest. For example here's a partial manifest for a K8s pod:

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: app
      ports:
        - name: health-check
          containerPort: 8081  # Default K8sDeputy.jl heath check port
          protocol: TCP
      readinessProbe:
        httpGet:
          path: /health/ready
          port: health-check
        timeoutSeconds: 5
```

## Shutdown

When it is time to shutdown your application you should inform the deputy by running the `shutdown` function:

```julia
using K8sDeputy
deputy = Deputy(; shutdown_handler=() -> @info "Shutting down")
K8sDeputy.serve!(deputy, "0.0.0.0")

try
    # Application code
finally
    shutdown(deputy)
end
```

Once `shutdown` is called the following occur:

1. The liveness endpoint starts returning failure responses
2. The deputy's `shutdown_handler` is called
3. The Julia process is terminated

By default the `shutdown_handler` only has 5 seconds to complete. If your `shutdown_handler` requires more time to execute you can change the timeout by using the keyword `shutdown_handler_timeout`.
