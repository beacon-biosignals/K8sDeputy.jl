# Expected to be run from the context of the K8sDeputy package root:
# ```
# docker build -f test/integration/Dockerfile .
# ```

ARG JULIA_VERSION=1.10.2
FROM julia:${JULIA_VERSION}-bookworm

# Install Julia General package registry
RUN julia -e 'using Pkg; Pkg.Registry.add("General")'

# Copy only the essentials from the package such that we can pre-install the package's
# dependencies. By only installing the minimum required files we should be able to make
# better use of Docker layer caching. Only modifications to the Project.toml/Manifest.toml
# will require a rebuild of these steps.
ENV PKG_NAME="K8sDeputy"
ENV JULIA_PROJECT=/root/.julia/dev/${PKG_NAME}
COPY Project.toml *Manifest.toml ${JULIA_PROJECT}/
RUN mkdir $JULIA_PROJECT/src && \
    echo "module ${PKG_NAME} end" >${JULIA_PROJECT}/src/${PKG_NAME}.jl
RUN julia -e 'using Pkg; Pkg.Registry.update(); Pkg.instantiate(); Pkg.precompile(strict=true, timing=true)'

COPY . ${JULIA_PROJECT}
RUN mv ${JULIA_PROJECT}/test/integration/entrypoint.jl ${JULIA_PROJECT} && \
    rmdir ${JULIA_PROJECT}/test/integration
RUN julia -e 'using Pkg; Pkg.precompile(strict=true, timing=true)'

WORKDIR ${JULIA_PROJECT}
ENTRYPOINT ["julia", "entrypoint.jl"]
