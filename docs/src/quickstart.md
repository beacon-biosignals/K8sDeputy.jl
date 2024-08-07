# Quickstart

For users who want to get started quickly you can use the following template to incorporate liveness probes, readiness probes, graceful termination, binding to non-priviledged ports, and read-only filesystem support.

1. Add K8sDeputy.jl to your Julia project: `Pkg.add("K8sDeputy")`
2. Define the following `entrypoint.jl` in your application and include it in the `WORKDIR` of your `Dockerfile`:

   ```julia
   using K8sDeputy
   deputy = Deputy()
   server = K8sDeputy.serve!(deputy, "0.0.0.0")
   graceful_terminator(() -> shutdown!(deputy))
   
   # Application initialization code
   
   readied!(deputy)
   
   # Application code
   ```

3. Incorporate the following changes into your K8s resource manifest:

   ```yaml
   apiVersion: v1
   kind: Pod
   spec:
     containers:
       - name: app
         command: ["/bin/sh", "-c", "julia entrypoint.jl; sleep 1"]
         ports:
           - name: health-check
             containerPort: 8081  # Default K8sDeputy.jl heath check port
             protocol: TCP
         livenessProbe:
           httpGet:
             path: /health/live
             port: health-check
           timeoutSeconds: 5
         readinessProbe:
           httpGet:
             path: /health/ready
             port: health-check
           timeoutSeconds: 5
         lifecycle:
           preStop:
             exec:
               command: ["julia", "-e", "using K8sDeputy; graceful_terminate()"]
         securityContext:
           capabilities:
             drop:
               - all
           readOnlyRootFilesystem: true
         volumeMounts:
           - name: ipc
              mountPath: /run
              subPath: app  # Set the `subPath` to the container name to ensure per-container isolation
     terminationGracePeriodSeconds: 30
     volumes:
       - name: ipc
         emptyDir:
           medium: Memory
   ```
