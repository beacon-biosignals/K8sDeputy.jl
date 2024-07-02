using Base: @deprecate

@deprecate graceful_terminate(pid::Integer; wait::Bool=true) graceful_terminate(Int32(pid); wait) true
