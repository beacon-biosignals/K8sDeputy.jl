# Expected to be run from the context of the K8sDeputy package root:
# ```
# docker build -f test/integration/Dockerfile .
# ```

# Minimum Julia version supported should match the Project.toml
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
RUN julia -e ' \
        using Pkg; \
        Pkg.Registry.update(); \
        Pkg.instantiate(); \
        if VERSION >= v"1.9.0-beta2.67" \
            Pkg.precompile(strict=true, timing=true); \
        else \
            Pkg.precompile(strict=true); \
        end;'

COPY . ${JULIA_PROJECT}
RUN mv ${JULIA_PROJECT}/test/integration/entrypoint.jl ${JULIA_PROJECT} && \
    rmdir ${JULIA_PROJECT}/test/integration
RUN julia -e ' \
        using Pkg; \
        if VERSION >= v"1.9.0-beta2.67" \
            Pkg.precompile(strict=true, timing=true); \
        else \
            Pkg.precompile(strict=true); \
        end;'

WORKDIR ${JULIA_PROJECT}
ENTRYPOINT ["julia", "entrypoint.jl"]
