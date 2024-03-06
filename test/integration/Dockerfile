# Expected to be run from the context of the K8sDeputy package root:
# ```
# docker build -f test/integration/Dockerfile .
# ```

ARG JULIA_VERSION=1.9.4
FROM julia:${JULIA_VERSION}-bookworm

# Install Julia package registries
RUN julia -e 'using Pkg; Pkg.Registry.add("General")'

ENV JULIA_PROJECT=/root/K8sDeputy
COPY Project.toml Manifest.toml ${JULIA_PROJECT}/
RUN julia -e 'using Pkg; Pkg.Registry.update(); Pkg.instantiate(); Pkg.build(); Pkg.precompile(strict=true, timing=true)'

COPY . ${JULIA_PROJECT}
RUN mv ${JULIA_PROJECT}/test/integration/entrypoint.jl ${JULIA_PROJECT} && \
    rmdir ${JULIA_PROJECT}/test/integration
RUN julia -e 'using Pkg; Pkg.precompile(strict=true, timing=true)'

WORKDIR ${JULIA_PROJECT}
ENTRYPOINT ["julia", "entrypoint.jl"]
