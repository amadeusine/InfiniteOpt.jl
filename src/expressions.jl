# Define type hierchical parser for use in building expressions with mixed types
# This is tested in test/operators.jl
function _var_type_parser(V::Type{<:GeneralVariableRef},
                          W::Type{<:GeneralVariableRef})::Type{<:GeneralVariableRef}
    if V == W
        return V
    elseif V isa Type{<:FiniteVariableRef} && W isa Type{<:FiniteVariableRef}
        return FiniteVariableRef
    elseif V isa Type{<:MeasureFiniteVariableRef} && W isa Type{<:MeasureFiniteVariableRef}
        return MeasureFiniteVariableRef
    else
        return GeneralVariableRef
    end
end

## Extend add_to_expression! for some more functionality, tested in test/operators.jl
# Mixed variable addition
function JuMP.add_to_expression!(quad::JuMP.GenericQuadExpr{C, Z}, new_coef::C,
                                 new_var1::V, new_var2::W
                                 )::JuMP.GenericQuadExpr where {C,
                                 Z <: GeneralVariableRef, V <: GeneralVariableRef,
                                 W <: GeneralVariableRef}
    type = _var_type_parser(Z, _var_type_parser(V, W))
    key = JuMP.UnorderedPair{type}(new_var1, new_var2)
    new_quad = convert(JuMP.GenericQuadExpr{C, type}, quad)
    JuMP._add_or_set!(new_quad.terms, key, new_coef)
    return new_quad
end

# var1 is a number
function JuMP.add_to_expression!(quad::JuMP.GenericQuadExpr{C, Z},
                                 new_coef::Number, new_var1::Number, new_var2::V
                                 )::JuMP.GenericQuadExpr where {C,
                                 Z <: GeneralVariableRef, V <: GeneralVariableRef}
    type = _var_type_parser(Z, V)
    new_quad = convert(JuMP.GenericQuadExpr{C, type}, quad)
    return JuMP.add_to_expression!(new_quad, new_coef * new_var1, new_var2)
end

# var2 is a number
function JuMP.add_to_expression!(quad::JuMP.GenericQuadExpr{C, Z},
                                 new_coef::Number, new_var1::V, new_var2::Number
                                 )::JuMP.GenericQuadExpr where {C,
                                 Z <: GeneralVariableRef, V <: GeneralVariableRef}
    type = _var_type_parser(Z, V)
    new_quad = convert(JuMP.GenericQuadExpr{C, type}, quad)
    return JuMP.add_to_expression!(new_quad, new_coef * new_var2, new_var1)
end

# var1 and var2 are numbers
function JuMP.add_to_expression!(quad::JuMP.GenericQuadExpr, new_coef::Number,
                                 new_var1::Number, new_var2::Number
                                 )::JuMP.GenericQuadExpr
    JuMP.add_to_expression!(quad.aff, new_coef * new_var2 * new_var1)
    return quad
end

## Extend for better comparisons than default
# GenericAffExpr
function Base.:(==)(aff1::JuMP.GenericAffExpr{C, V},
                    aff2::JuMP.GenericAffExpr{C, W}) where {C, V <: GeneralVariableRef,
                                                            W <: GeneralVariableRef}
    return aff1.constant == aff2.constant && collect(pairs(aff1.terms)) == collect(pairs(aff2.terms))
end

# GenericQuadExpr
function Base.:(==)(quad1::JuMP.GenericQuadExpr{C, V},
                    quad2::JuMP.GenericQuadExpr{C, W}) where {C, V <: GeneralVariableRef,
                                                              W <: GeneralVariableRef}
    pairs1 = collect(pairs(quad1.terms))
    pairs2 = collect(pairs(quad2.terms))
    if length(pairs1) != length(pairs2)
        return false
    end
    for i = 1:length(pairs1)
        if pairs1[i][1].a != pairs2[i][1].a || pairs1[i][1].b != pairs2[i][1].b || pairs1[i][2] != pairs2[i][2]
            return false
        end
    end
    return quad1.aff == quad2.aff
end

## Determine which variables are present in a function
# GeneralVariableRef
function _all_function_variables(f::GeneralVariableRef)::Vector{<:GeneralVariableRef}
    return [f]
end

# GenericAffExpr
function _all_function_variables(f::JuMP.GenericAffExpr)::Vector{<:GeneralVariableRef}
    return GeneralVariableRef[vref for vref in keys(f.terms)]
end

# GenericQuadExpr
function _all_function_variables(f::JuMP.GenericQuadExpr)::Vector{<:GeneralVariableRef}
    aff_vrefs = _all_function_variables(f.aff)
    vref_pairs = [k for k in keys(f.terms)]
    a_vrefs = GeneralVariableRef[pair.a for pair in vref_pairs]
    b_vrefs = GeneralVariableRef[pair.b for pair in vref_pairs]
    return unique([aff_vrefs; a_vrefs; b_vrefs])
end

# Fallback
function _all_function_variables(f)
    error("Can only use InfiniteOpt variables and expressions.")
    return
end

## Return a tuple of the parameter references in an expr
# FiniteVariableRef
_all_parameter_refs(expr::FiniteVariableRef) = ()

# InfiniteVariableRef
_all_parameter_refs(expr::InfiniteVariableRef) = parameter_refs(expr)

# ParameterRef
_all_parameter_refs(expr::ParameterRef) = (expr, )

# ReducedInfiniteVariableRef
_all_parameter_refs(expr::ReducedInfiniteVariableRef) = parameter_refs(expr)

# GenericAffExpr
function _all_parameter_refs(expr::JuMP.GenericAffExpr{C,
                              <:GeneralVariableRef}) where {C}
    pref_list = []
    for (var, coef) in expr.terms
        push!(pref_list, _all_parameter_refs(var)...)
    end
    groups = [group_id(pref) for pref in pref_list]
    unique_groups = sort(unique(groups))
    unique_indexes = zeros(Int64, length(unique_groups))
    for i = 1:length(unique_indexes)
        unique_indexes[i] = findfirst(isequal(unique_groups[i]), groups)
    end
    return Tuple(pref_list[i] for i in unique_indexes)
end

# GenericQuadExpr
function _all_parameter_refs(expr::JuMP.GenericQuadExpr{C,
                             <:GeneralVariableRef}) where {C}
    pref_list = []
    push!(pref_list, _all_parameter_refs(expr.aff)...)
    for (pair, coef) in expr.terms
        push!(pref_list, _all_parameter_refs(pair.a)...)
        push!(pref_list, _all_parameter_refs(pair.b)...)
    end
    groups = [group_id(pref) for pref in pref_list]
    unique_groups = sort(unique(groups))
    unique_indexes = zeros(Int64, length(unique_groups))
    for i = 1:length(unique_indexes)
        unique_indexes[i] = findfirst(isequal(unique_groups[i]), groups)
    end
    return Tuple(pref_list[i] for i in unique_indexes)
end

## Delete variables from an expression
# GenericAffExpr
function _remove_variable(f::JuMP.GenericAffExpr, vref::GeneralVariableRef)
    if haskey(f.terms, vref)
        delete!(f.terms, vref)
    end
    return
end

# GenericQuadExpr
function _remove_variable(f::JuMP.GenericQuadExpr, vref::GeneralVariableRef)
    _remove_variable(f.aff, vref)
    vref_pairs = [k for k in keys(f.terms)]
    for i = 1:length(vref_pairs)
        if vref_pairs[i].a == vref
            delete!(f.terms, vref_pairs[i])
        elseif vref_pairs[i].b == vref
            delete!(f.terms, vref_pairs[i])
        end
    end
    return
end

# Check expression for a particular variable type via a recursive search
# This is tested in test/measures.jl
function _has_variable(vrefs::Vector{<:GeneralVariableRef},
                       vref::GeneralVariableRef; prior=[])
    if vrefs[1] == vref
        return true
    elseif isa(vrefs[1], MeasureRef)
        if length(vrefs) > 1
            return _has_variable(_all_function_variables(measure_function(vrefs[1])),
                          vref, prior = GeneralVariableRef[prior; vrefs[2:end]])
        else
            return _has_variable(_all_function_variables(measure_function(vrefs[1])),
                                 vref, prior = prior)
        end
    elseif length(vrefs) > 1
        return _has_variable(vrefs[2:end], vref, prior = prior)
    elseif length(prior) > 0
        return _has_variable(prior, vref)
    else
        return false
    end
end