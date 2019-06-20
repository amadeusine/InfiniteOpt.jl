# Extend convert to handle JuMP expression types
function Base.convert(::Type{JuMP.GenericAffExpr{C,V}}, x::JuMP.GenericAffExpr) where {C,V}
    return JuMP.GenericAffExpr{C,V}(x.constant, x.terms)
end
function Base.convert(::Type{JuMP.GenericQuadExpr{C,V}}, x::JuMP.GenericQuadExpr) where {C,V}
    return JuMP.GenericQuadExpr{C,V}(x.aff, x.terms)
end
function Base.convert(::Type{JuMP.UnorderedPair{T}}, x::JuMP.UnorderedPair) where {T}
    return JuMP.UnorderedPair{T}(x.a, x.b)
end

# Extend convert to handle JuMP containers
function Base.convert(::Type{JuMP.Containers.SparseAxisArray}, arr::Array)
    data = Dict(Tuple(k) => arr[k] for k in CartesianIndices(arr))
    return JuMP.Containers.SparseAxisArray(data)
end
function Base.convert(::Type{JuMP.Containers.SparseAxisArray}, arr::JuMP.Containers.DenseAxisArray)
    data = Dict(Tuple(k) => arr[k] for k in CartesianIndices(arr))
    return JuMP.Containers.SparseAxisArray(data)
end
