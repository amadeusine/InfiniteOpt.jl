# Define symbol inputs for different variable types
const Infinite = :Infinite
const Point = :Point
const Hold = :Hold

## Extend Base.copy for new variable types
# No new model
Base.copy(v::GeneralVariableRef) = v

# With new model
function Base.copy(v::T, new_model::InfiniteModel)::GeneralVariableRef where {T <: GeneralVariableRef}
    return T(new_model, v.index)
end

## Extend other Base functions
# Base.:(==)
function Base.:(==)(v::T, w::U)::Bool where {T <: GeneralVariableRef,
                                             U <: GeneralVariableRef}
    return v.model === w.model && v.index == w.index && T == U
end

# Base.broadcastable
Base.broadcastable(v::GeneralVariableRef) = Ref(v)

# Base.length
Base.length(v::GeneralVariableRef) = 1

# Extend JuMP functions
JuMP.isequal_canonical(v::GeneralVariableRef, w::GeneralVariableRef) = v == w
JuMP.variable_type(model::InfiniteModel) = GeneralVariableRef
function JuMP.variable_type(model::InfiniteModel, type::Symbol)
    if type == Infinite
        return InfiniteVariableRef
    elseif type == Point
        return PointVariableRef
    elseif type == Hold
        return HoldVariableRef
    elseif type == Parameter
        return ParameterRef
    else
        error("Invalid variable type.")
    end
end

# Check parameter tuple, ensure all elements contain parameter references
function _check_parameter_tuple(_error::Function, prefs::VectorTuple{T}) where {T}
    T <: ParameterRef || _error("Invalid parameter type(s) given.")
    return
end

# Ensure each tuple element only contains parameters with same group ID
function _check_tuple_groups(_error::Function, prefs::VectorTuple)
    # check that each tuple element has a unique group ID
    groups = [group_id(pref) for pref in prefs[:, 1]]
    allunique(groups) || _error("Cannot double specify infinite parameter references.")
    # check that each tuple element array contains parameters with same group ID
    for i in eachindex(size(prefs, 1))
        if length(prefs[i, :]) > 1
            first_group = groups[i]
            for j in 2:length(prefs[i, :])
                if group_id(prefs[i, j]) != first_group
                    _error("Each parameter tuple element must have contain only " *
                           "infinite parameters with the same group ID.")
                end
            end
        end
    end
    return
end

# Ensure parameter values match shape of parameter reference tuple stored in the
# infinite variable reference
function _check_tuple_shape(_error::Function,
                            ivref::InfiniteVariableRef,
                            values::VectorTuple)
    prefs = raw_parameter_refs(ivref)
    if !same_structure(prefs, values)
        _error("The dimensions and array formatting of the infinite parameter " *
               "values must match those of the parameter references for the " *
               "infinite variable.")
    end
    return
end

# Used to ensure values don't violate parameter bounds
function _check_tuple_values(_error::Function, ivref::InfiniteVariableRef,
                             param_values::VectorTuple)
    prefs = raw_parameter_refs(ivref)
    for i in eachindex(prefs)
        if !supports_in_set(param_values[i], infinite_set(prefs[i]))
            _error("Parameter values violate parameter bounds.")
        end
    end
    return
end

# Update point variable info to consider the infinite variable
function _update_point_info(info::JuMP.VariableInfo, ivref::InfiniteVariableRef)
    if JuMP.has_lower_bound(ivref) && !info.has_fix && !info.has_lb
        info = JuMP.VariableInfo(true, JuMP.lower_bound(ivref),
                                 info.has_ub, info.upper_bound,
                                 info.has_fix, info.fixed_value,
                                 info.has_start, info.start,
                                 info.binary, info.integer)
    end
    if JuMP.has_upper_bound(ivref) && !info.has_fix && !info.has_ub
        info = JuMP.VariableInfo(info.has_lb, info.lower_bound,
                                 true, JuMP.upper_bound(ivref),
                                 info.has_fix, info.fixed_value,
                                 info.has_start, info.start,
                                 info.binary, info.integer)
    end
    if JuMP.is_fixed(ivref) && !info.has_fix  && !info.has_lb  && !info.has_ub
        info = JuMP.VariableInfo(info.has_lb, info.lower_bound,
                                 info.has_ub, info.upper_bound,
                                 true, JuMP.fix_value(ivref),
                                 info.has_start, info.start,
                                 info.binary, info.integer)
    end
    if !(JuMP.start_value(ivref) === NaN) && !info.has_start
        info = JuMP.VariableInfo(info.has_lb, info.lower_bound,
                                 info.has_ub, info.upper_bound,
                                 info.has_fix, info.fixed_value,
                                 true, JuMP.start_value(ivref),
                                 info.binary, info.integer)
    end
    if JuMP.is_binary(ivref) && !info.integer
        info = JuMP.VariableInfo(info.has_lb, info.lower_bound,
                                 info.has_ub, info.upper_bound,
                                 info.has_fix, info.fixed_value,
                                 info.has_start, info.start,
                                 true, info.integer)
    end
    if JuMP.is_integer(ivref) && !info.binary
        info = JuMP.VariableInfo(info.has_lb, info.lower_bound,
                                 info.has_ub, info.upper_bound,
                                 info.has_fix, info.fixed_value,
                                 info.has_start, info.start,
                                 info.binary, true)
    end
    return info
end

# Check that parameter_bounds argument is valid
function _check_bounds(bounds::ParameterBounds; _error = error)
    for (pref, set) in bounds.intervals
        # check that respects lower bound
        if JuMP.has_lower_bound(pref) && (set.lower_bound < JuMP.lower_bound(pref))
                _error("Specified parameter lower bound exceeds that defined " *
                       "for $pref.")
        end
        # check that respects upper bound
        if JuMP.has_upper_bound(pref) && (set.upper_bound > JuMP.upper_bound(pref))
                _error("Specified parameter upper bound exceeds that defined " *
                       "for $pref.")
        end
    end
    return
end

## Check to ensure correct inputs and build variables and return
# InfiniteVariable
function _make_variable(_error::Function, info::JuMP.VariableInfo, ::Val{Infinite};
                        parameter_refs::Union{ParameterRef,
                                              AbstractArray{<:ParameterRef},
                                              Tuple, Nothing} = nothing,
                        extra_kw_args...)::InfiniteVariable
    # check for unneeded keywords
    for (kwarg, _) in extra_kw_args
        _error("Keyword argument $kwarg is not for use with infinite variables.")
    end
    # check that we have been given parameter references
    if parameter_refs == nothing
        _error("Parameter references not specified, use the var(params...) " *
               "syntax or the parameter_refs keyword argument.")
    end
    # format parameter_refs into a VectorTuple
    parameter_refs = VectorTuple(parameter_refs)
    # check tuple for validity and format
    _check_parameter_tuple(_error, parameter_refs)
    _check_tuple_groups(_error, parameter_refs)
    # make the variable and return
    return InfiniteVariable(info, parameter_refs)
end

# PointVariable
function _make_variable(_error::Function, info::JuMP.VariableInfo, ::Val{Point};
                        infinite_variable_ref::Union{InfiniteVariableRef,
                                                     Nothing} = nothing,
                        parameter_values::Union{Number,
                                                AbstractArray{<:Number},
                                                Tuple, Nothing} = nothing,
                        extra_kw_args...)::PointVariable
    # check for unneeded keywords
    for (kwarg, _) in extra_kw_args
        _error("Keyword argument $kwarg is not for use with point variables.")
    end
    # ensure the needed arguments are given
    if parameter_values == nothing || infinite_variable_ref == nothing
        _error("Must specify the infinite variable and the values of its " *
               "infinite parameters")
    end
    # format tuple as VectorTuple
    parameter_values = VectorTuple{Float64}(parameter_values)
    # check information and prepare format
    _check_tuple_shape(_error, infinite_variable_ref, parameter_values)
    _check_tuple_values(_error, infinite_variable_ref, parameter_values)
    info = _update_point_info(info, infinite_variable_ref)
    # make variable and return
    return PointVariable(info, infinite_variable_ref, parameter_values)
end

# HoldVariable
function _make_variable(_error::Function, info::JuMP.VariableInfo, ::Val{Hold};
                        parameter_bounds::ParameterBounds = ParameterBounds(),
                        extra_kw_args...)::HoldVariable
    # check for unneeded keywords
    for (kwarg, _) in extra_kw_args
        _error("Keyword argument $kwarg is not for use with hold variables.")
    end
    # check that the bounds don't violate parameter domains
    _check_bounds(parameter_bounds)
    # make variable and return
    return HoldVariable(info, parameter_bounds)
end

# Fallback method
function _make_variable(_error::Function, info::JuMP.VariableInfo, type;
                        extra_kw_args...)
    _error("Unrecognized variable type $type, should be Infinite, " *
           "Point, or Hold.")
end

"""
    JuMP.build_variable(_error::Function, info::JuMP.VariableInfo,
                        var_type::Symbol;
                        [parameter_refs::Union{ParameterRef,
                                              AbstractArray{<:ParameterRef},
                                              Tuple, Nothing} = nothing,
                        infinite_variable_ref::Union{InfiniteVariableRef,
                                                     Nothing} = nothing,
                        parameter_values::Union{Number, AbstractArray{<:Number},
                                                Tuple, Nothing} = nothing,
                        parameter_bounds::Union{Dict{ParameterRef, IntervalSet},
                                                Nothing} = nothing])

Extend the `JuMP.build_variable` function to accomodate `InfiniteOpt`
variable types. Returns the appropriate variable Datatype (i.e.,
[`InfiniteVariable`](@ref), [`PointVariable`](@ref), and
[`HoldVariable`](@ref)). Primarily this method is to be used internally by the
appropriate constructor macros [`@infinite_variable`](@ref),
[`@point_variable`](@ref), and [`@hold_variable`](@ref). However, it can be
called manually to build `InfiniteOpt` variables. Errors if an unneeded keyword
argument is given or if the keywoard arguments are formatted incorrectly (e.g.,
`parameter_refs` contains repeated parameter references when an infinite variable
is defined). Also errors if needed kewword arguments are negated.

**Examples**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel())
julia> @infinite_parameter(m, 0 <= t <= 1)
t

julia> info = VariableInfo(false, 0, false, 0, false, 0, false, 0, false, false);

julia> inf_var = build_variable(error, info, Infinite, parameter_refs = t)
InfiniteVariable{Int64,Int64,Int64,Int64}(VariableInfo{Int64,Int64,Int64,Int64}(false, 0, false, 0, false, 0, false, 0, false, false), (t,))

julia> ivref = add_variable(m, inf_var, "var_name")
var_name(t)

julia> pt_var = build_variable(error, info, Point, infinite_variable_ref = ivref,
                               parameter_values = 0.5)
PointVariable{Int64,Int64,Int64,Float64}(VariableInfo{Int64,Int64,Int64,Float64}(false, 0, false, 0, false, 0, true, 0.0, false, false), var_name(t), (0.5,))

julia> hd_var = build_variable(error, info, Hold)
HoldVariable{Int64,Int64,Int64,Int64}(VariableInfo{Int64,Int64,Int64,Int64}(false, 0, false, 0, false, 0, false, 0, false, false), Subdomain bounds (0): )
```
"""
function JuMP.build_variable(_error::Function, info::JuMP.VariableInfo,
                             var_type::Symbol;
                             macro_error::Union{Function, Nothing} = nothing,
                             kw_args...)
    if macro_error != nothing
        _error = macro_error # replace with macro error function
    end
    # make the variable and conduct necessary checks
    return _make_variable(_error, info, Val(var_type); kw_args...)
end

# check the pref tuple contains only valid parameters
function _check_parameters_valid(model::InfiniteModel, prefs::VectorTuple)
    for pref in prefs
        JuMP.is_valid(model, pref) || error("Invalid Parameter reference " *
                                            "provided.")
    end
    return
end

# Used to update the model.param_to_vars field
function _update_param_var_mapping(vref::InfiniteVariableRef, prefs::VectorTuple)
    model = JuMP.owner_model(vref)
    for pref in prefs
        if haskey(model.param_to_vars, JuMP.index(pref))
            push!(model.param_to_vars[JuMP.index(pref)], JuMP.index(vref))
        else
            model.param_to_vars[JuMP.index(pref)] = [JuMP.index(vref)]
        end
    end
    return
end

# Used to add point variable support to parameter supports if necessary
function _update_param_supports(ivref::InfiniteVariableRef,
                                param_values::VectorTuple)
    prefs = raw_parameter_refs(ivref)
    for i in eachindex(prefs)
        add_supports(prefs[i], param_values[i])
    end
    return
end

# Used to update mapping infinite_to_points
function _update_infinite_point_mapping(pvref::PointVariableRef,
                                        ivref::InfiniteVariableRef)
    model = JuMP.owner_model(pvref)
    if haskey(model.infinite_to_points, JuMP.index(ivref))
        push!(model.infinite_to_points[JuMP.index(ivref)], JuMP.index(pvref))
    else
        model.infinite_to_points[JuMP.index(ivref)] = [JuMP.index(pvref)]
    end
    return
end

# Validate parameter bounds and add support(s) if needed
function _validate_bounds(model::InfiniteModel, bounds::ParameterBounds;
                          _error = error)
    for (pref, set) in bounds.intervals
        # check validity
        JuMP.is_valid(model, pref) || _error("Parameter bound reference " *
                                             "is invalid.")
        # ensure has a support if a point constraint was given
        if set.lower_bound == set.upper_bound
            add_supports(pref, set.lower_bound)
        end
    end
    return
end

## Make the variable reference and do checks/mapping updates
# InfiniteVariable
function _check_and_make_variable_ref(model::InfiniteModel,
                                      v::InfiniteVariable)::InfiniteVariableRef
    _check_parameters_valid(model, v.parameter_refs)
    vref = InfiniteVariableRef(model, model.next_var_index)
    _update_param_var_mapping(vref, v.parameter_refs)
    return vref
end

# PointVariable
function _check_and_make_variable_ref(model::InfiniteModel,
                                      v::PointVariable)::PointVariableRef
    ivref = v.infinite_variable_ref
    JuMP.is_valid(model, ivref) || error("Invalid infinite variable reference.")
    vref = PointVariableRef(model, model.next_var_index)
    _update_param_supports(ivref, v.parameter_values)
    _update_infinite_point_mapping(vref, ivref)
    return vref
end

# HoldVariable
function _check_and_make_variable_ref(model::InfiniteModel,
                                      v::HoldVariable)::HoldVariableRef
    _validate_bounds(model, v.parameter_bounds)
    vref = HoldVariableRef(model, model.next_var_index)
    if length(v.parameter_bounds.intervals) != 0
        model.has_hold_bounds = true
    end
    return vref
end

# Fallback
function _check_and_make_variable_ref(model::InfiniteModel, v::T) where {T}
    throw(ArgumentError("Invalid variable object type `$T`."))
end

"""
    JuMP.add_variable(model::InfiniteModel, var::InfOptVariable, [name::String = ""])

Extend the [`JuMP.add_variable`](@ref JuMP.add_variable(::JuMP.Model, ::JuMP.ScalarVariable, ::String))
function to accomodate `InfiniteOpt` variable types. Adds a variable to an
infinite model `model` and returns an appropriate variable reference (i.e.,
[`InfiniteVariableRef`](@ref), [`PointVariableRef`](@ref), or
[`HoldVariableRef`](@ref)). Primarily intended to be an internal function of the
constructor macros [`@infinite_variable`](@ref), [`@point_variable`](@ref), and
[`@hold_variable`](@ref). However, it can be used in combination with
[`JuMP.build_variable`](@ref) to add variables to an infinite model object.
Errors if invalid parameters reference(s) or an invalid infinite variable
reference is included in `var`.

**Examples**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel())
julia> @infinite_parameter(m, t in [0, 10]);

julia> info = VariableInfo(false, 0, false, 0, false, 0, false, 0, false, false);

julia> inf_var = build_variable(error, info, Infinite, parameter_refs = t);

julia> ivref = add_variable(m, inf_var, "var_name")
var_name(t)

julia> pt_var = build_variable(error, info, Point, infinite_variable_ref = ivref,
                               parameter_values = 0.5);

julia> pvref = add_variable(m, pt_var, "var_alias")
var_alias

julia> hd_var = build_variable(error, info, Hold);

julia> hvref = add_variable(m, hd_var, "var_name")
var_name
```
"""
function JuMP.add_variable(model::InfiniteModel, var::InfOptVariable,
                           name::String = "")
    model.next_var_index += 1
    vref = _check_and_make_variable_ref(model, var)
    model.vars[JuMP.index(vref)] = var
    JuMP.set_name(vref, name)
    if var.info.has_lb
        newset = MOI.GreaterThan(convert(Float64, var.info.lower_bound))
        cref = JuMP.add_constraint(JuMP.owner_model(vref),
                                   JuMP.ScalarConstraint(vref, newset))
        _set_lower_bound_index(vref, JuMP.index(cref))
        model.constr_in_var_info[JuMP.index(cref)] = true
    end
    if var.info.has_ub
        newset = MOI.LessThan(convert(Float64, var.info.upper_bound))
        cref = JuMP.add_constraint(JuMP.owner_model(vref),
                                   JuMP.ScalarConstraint(vref, newset))
        _set_upper_bound_index(vref, JuMP.index(cref))
        model.constr_in_var_info[JuMP.index(cref)] = true
    end
    if var.info.has_fix
        newset = MOI.EqualTo(convert(Float64, var.info.fixed_value))
        cref = JuMP.add_constraint(model, JuMP.ScalarConstraint(vref, newset))
        _set_fix_index(vref, JuMP.index(cref))
        model.constr_in_var_info[JuMP.index(cref)] = true
    end
    if var.info.binary
        cref = JuMP.add_constraint(JuMP.owner_model(vref),
                                   JuMP.ScalarConstraint(vref, MOI.ZeroOne()))
        _set_binary_index(vref, JuMP.index(cref))
        model.constr_in_var_info[JuMP.index(cref)] = true
    elseif var.info.integer
        cref = JuMP.add_constraint(JuMP.owner_model(vref),
                                   JuMP.ScalarConstraint(vref, MOI.Integer()))
        _set_integer_index(vref, JuMP.index(cref))
        model.constr_in_var_info[JuMP.index(cref)] = true
    end
    model.var_in_objective[JuMP.index(vref)] = false
    return vref
end

"""
    JuMP.owner_model(vref::GeneralVariableRef)::InfiniteModel

Extend [`JuMP.owner_model`](@ref JuMP.owner_model(::JuMP.AbstractVariableRef)) function
for `InfiniteOpt` variables. Returns the infinite model associated with `vref`.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @hold_variable(m, 0 <= vref <= 1))
julia> owner_model(vref)
An InfiniteOpt Model
Feasibility problem with:
Variable: 1
`HoldVariableRef`-in-`MathOptInterface.GreaterThan{Float64}`: 1 constraint
`HoldVariableRef`-in-`MathOptInterface.LessThan{Float64}`: 1 constraint
Names registered in the model: vref
Optimizer model backend information:
Model mode: AUTOMATIC
CachingOptimizer state: NO_OPTIMIZER
Solver name: No optimizer attached.
```
"""
JuMP.owner_model(vref::GeneralVariableRef)::InfiniteModel = vref.model

"""
    JuMP.index(v::GeneralVariableRef)::Int

Extent [`JuMP.index`](@ref JuMP.index(::JuMP.VariableRef)) to return the index of a
`InfiniteOpt` variable.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @hold_variable(m, vref))
julia> index(vref)
1
```
"""
JuMP.index(v::GeneralVariableRef)::Int = v.index

"""
    used_by_constraint(vref::InfOptVariableRef)::Bool

Return a `Bool` indicating if `vref` is used by a constraint.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @hold_variable(m, vref))
julia> used_by_constraint(vref)
false
```
"""
function used_by_constraint(vref::InfOptVariableRef)::Bool
    return haskey(JuMP.owner_model(vref).var_to_constrs, JuMP.index(vref))
end

"""
    used_by_measure(vref::InfOptVariableRef)::Bool

Return a `Bool` indicating if `vref` is used by a measure.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @hold_variable(m, vref); m.var_to_meas[1] = [1])
julia> used_by_measure(vref)
true
```
"""
function used_by_measure(vref::InfOptVariableRef)::Bool
    return haskey(JuMP.owner_model(vref).var_to_meas, JuMP.index(vref))
end

"""
    used_by_objective(vref::InfOptVariableRef)::Bool

Return a `Bool` indicating if `vref` is used by the objective.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @hold_variable(m, vref); m.var_in_objective[1] = true)
julia> used_by_objective(vref)
true
```
"""
function used_by_objective(vref::InfOptVariableRef)::Bool
    return JuMP.owner_model(vref).var_in_objective[JuMP.index(vref)]
end

"""
    is_used(vref::InfOptVariableRef)::Bool

Return a `Bool` indicating if `vref` is used in the model.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @hold_variable(m, 0 <= vref))
julia> is_used(vref)
true
```
"""
function is_used(vref::InfOptVariableRef)::Bool
    return used_by_measure(vref) || used_by_constraint(vref) || used_by_objective(vref)
end

"""
    used_by_point_variable(vref::InfiniteVariableRef)::Bool

Return a `Bool` indicating if `vref` is used by a point variable.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @infinite_variable(m, vref(@infinite_parameter(m, t in [0, 1]))))
julia> used_by_point_variable(vref)
false
```
"""
function used_by_point_variable(vref::InfiniteVariableRef)::Bool
    return haskey(JuMP.owner_model(vref).infinite_to_points, JuMP.index(vref))
end

"""
    used_by_reduced_variable(vref::InfiniteVariableRef)::Bool

Return a `Bool` indicating if `vref` is used by a reduced infinite variable.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @infinite_variable(m, vref(@infinite_parameter(m, t in [0, 1]))))
julia> used_by_reduced_variable(vref)
false
```
"""
function used_by_reduced_variable(vref::InfiniteVariableRef)::Bool
    return haskey(JuMP.owner_model(vref).infinite_to_reduced, JuMP.index(vref))
end

"""
    is_used(vref::InfiniteVariableRef)::Bool

Return a `Bool` indicating if `vref` is used in the model.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @infinite_variable(m, vref(@infinite_parameter(m, t in [0, 1]))))
julia> is_used(vref)
false
```
"""
function is_used(vref::InfiniteVariableRef)::Bool
    if used_by_measure(vref) || used_by_constraint(vref)
        return true
    end
    if used_by_point_variable(vref)
        for vindex in JuMP.owner_model(vref).infinite_to_points[JuMP.index(vref)]
            if is_used(PointVariableRef(JuMP.owner_model(vref), vindex))
                return true
            end
        end
    end
    if used_by_reduced_variable(vref)
        for rindex in JuMP.owner_model(vref).infinite_to_reduced[JuMP.index(vref)]
            rvref = ReducedInfiniteVariableRef(JuMP.owner_model(vref), rindex)
            if used_by_constraint(rvref) || used_by_measure(rvref)
                return true
            end
        end
    end
    return false
end

"""
    JuMP.delete(model::InfiniteModel, vref::InfOptVariableRef)

Extend [`JuMP.delete`](@ref JuMP.delete(::JuMP.Model, ::JuMP.VariableRef)) to delete
`InfiniteOpt` variables and their dependencies. Errors if variable is invalid,
meaning it has already been deleted or it belongs to another model.

**Example**
```julia-repl
julia> print(model)
Min measure(g(t)*t) + z
Subject to
 z ≥ 0.0
 g(t) + z ≥ 42.0
 g(0.5) = 0
 t ∈ [0, 6]

julia> delete(model, g)

julia> print(model)
Min measure(t) + z
Subject to
 z ≥ 0.0
 z ≥ 42.0
 t ∈ [0, 6]
```
"""
function JuMP.delete(model::InfiniteModel, vref::InfOptVariableRef)
    @assert JuMP.is_valid(model, vref) "Variable is invalid."
    # update the optimizer model status
    if is_used(vref)
        set_optimizer_model_ready(model, false)
    end
    # remove variable info constraints associated with vref
    if JuMP.has_lower_bound(vref)
        JuMP.delete_lower_bound(vref)
    end
    if JuMP.has_upper_bound(vref)
        JuMP.delete_upper_bound(vref)
    end
    if JuMP.is_fixed(vref)
        JuMP.unfix(vref)
    end
    if JuMP.is_binary(vref)
        JuMP.unset_binary(vref)
    elseif JuMP.is_integer(vref)
        JuMP.unset_integer(vref)
    end
    # remove dependencies from measures and update them
    if used_by_measure(vref)
        for mindex in model.var_to_meas[JuMP.index(vref)]
            if isa(model.measures[mindex].func, InfOptVariableRef)
                model.measures[mindex] = Measure(zero(JuMP.AffExpr),
                                                 model.measures[mindex].data)
            else
                _remove_variable(model.measures[mindex].func, vref)
            end
            JuMP.set_name(MeasureRef(model, mindex),
                           _make_meas_name(model.measures[mindex]))
        end
        # delete mapping
        delete!(model.var_to_meas, JuMP.index(vref))
    end
    # remove dependencies from measures and update them
    if used_by_constraint(vref)
        for cindex in model.var_to_constrs[JuMP.index(vref)]
            if isa(model.constrs[cindex].func, InfOptVariableRef)
                model.constrs[cindex] = JuMP.ScalarConstraint(zero(JuMP.AffExpr),
                                                      model.constrs[cindex].set)
            else
                _remove_variable(model.constrs[cindex].func, vref)
            end
        end
        # delete mapping
        delete!(model.var_to_constrs, JuMP.index(vref))
    end
    # remove from objective if vref is in it
    if used_by_objective(vref)
        if isa(model.objective_function, InfOptVariableRef)
            model.objective_function = zero(JuMP.AffExpr)
        else
            _remove_variable(model.objective_function, vref)
        end
    end
    # do specific updates if vref is infinite
    if isa(vref, InfiniteVariableRef)
        # update parameter mapping
        all_prefs = parameter_list(vref)
        for pref in all_prefs
            filter!(e -> e != JuMP.index(vref),
                    model.param_to_vars[JuMP.index(pref)])
            if length(model.param_to_vars[JuMP.index(pref)]) == 0
                delete!(model.param_to_vars, JuMP.index(pref))
            end
        end
        # delete associated point variables and mapping
        if used_by_point_variable(vref)
            for index in model.infinite_to_points[JuMP.index(vref)]
                JuMP.delete(model, PointVariableRef(model, index))
            end
            delete!(model.infinite_to_points, JuMP.index(vref))
        end
        # delete associated reduced variables and mapping
        if used_by_reduced_variable(vref)
            for index in model.infinite_to_reduced[JuMP.index(vref)]
                JuMP.delete(model, ReducedInfiniteVariableRef(model, index))
            end
            delete!(model.infinite_to_reduced, JuMP.index(vref))
        end
    end
    # update mappings if is point variable
    if isa(vref, PointVariableRef)
        ivref = infinite_variable_ref(vref)
        filter!(e -> e != JuMP.index(vref),
                model.infinite_to_points[JuMP.index(ivref)])
        if length(model.infinite_to_points[JuMP.index(ivref)]) == 0
            delete!(model.infinite_to_points, JuMP.index(ivref))
        end
    end
    # delete the variable information
    delete!(model.var_in_objective, JuMP.index(vref))
    delete!(model.vars, JuMP.index(vref))
    delete!(model.var_to_name, JuMP.index(vref))
    return
end

"""
    JuMP.is_valid(model::InfiniteModel, vref::InfOptVariableRef)::Bool

Extend [`JuMP.is_valid`](@ref JuMP.is_valid(::JuMP.Model, ::JuMP.VariableRef))
to accomodate `InfiniteOpt` variables.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel(); @hold_variable(model, vref))
julia> is_valid(model, vref)
true
```
"""
function JuMP.is_valid(model::InfiniteModel, vref::InfOptVariableRef)::Bool
    return (model === JuMP.owner_model(vref) && JuMP.index(vref) in keys(model.vars))
end

"""
    JuMP.num_variables(model::InfiniteModel)::Int

Extend [`JuMP.num_variables`](@ref JuMP.num_variables(::JuMP.Model)) to return the
number of `InfiniteOpt` variables assigned to `model`.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel(); @hold_variable(model, vref[1:3]))
julia> num_variables(model)
3
```
"""
JuMP.num_variables(model::InfiniteModel)::Int = length(model.vars)

# Include all the extension functions for manipulating the properties associated
# with VariableInfo
include("variable_info.jl")

"""
    JuMP.name(vref::InfOptVariableRef)::String

Extend [`JuMP.name`](@ref JuMP.name(::JuMP.VariableRef)) to return the names of
`InfiniteOpt` variables.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @hold_variable(m, vref, base_name = "var_name"))
julia> name(vref)
"var_name"
```
"""
function JuMP.name(vref::InfOptVariableRef)::String
    return JuMP.owner_model(vref).var_to_name[JuMP.index(vref)]
end

"""
    JuMP.set_name(vref::HoldVariableRef, name::String)

Extend [`JuMP.set_name`](@ref JuMP.set_name(::JuMP.VariableRef, ::String)) to set
names of hold variables.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @hold_variable(m, vref))
julia> set_name(vref, "var_name")

julia> name(vref)
"var_name"
```
"""
function JuMP.set_name(vref::HoldVariableRef, name::String)
    JuMP.owner_model(vref).var_to_name[JuMP.index(vref)] = name
    JuMP.owner_model(vref).name_to_var = nothing
    return
end

"""
    infinite_variable_ref(vref::PointVariableRef)::InfiniteVariableRef

Return the `InfiniteVariableRef` associated with the point variable `vref`.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel(); @infinite_parameter(model, t in [0, 1]))
julia> @infinite_variable(model, T(t))
T(t)

julia> vref = @point_variable(model, T(0))
T(0)

julia> infinite_variable_ref(vref)
T(t)
```
"""
function infinite_variable_ref(vref::PointVariableRef)::InfiniteVariableRef
    return JuMP.owner_model(vref).vars[JuMP.index(vref)].infinite_variable_ref
end

"""
    raw_parameter_values(vref::PointVariableRef)::VectorTuple{<:Number}

Return the raw [`VectorTuple`](@ref) support point associated with the
point variable `vref`.
```
"""
function raw_parameter_values(vref::PointVariableRef)::VectorTuple{<:Number}
    return JuMP.owner_model(vref).vars[JuMP.index(vref)].parameter_values
end

"""
    parameter_values(vref::PointVariableRef)::Tuple

Return the support point associated with the point variable `vref`.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel(); @infinite_parameter(model, t in [0, 1]))
julia> @infinite_variable(model, T(t))
T(t)

julia> vref = @point_variable(model, T(0))
T(0)

julia> parameter_values(vref)
(0,)
```
"""
function parameter_values(vref::PointVariableRef)::Tuple
    return Tuple(raw_parameter_values(vref))
end

# Internal function used to change the parameter value tuple of a point variable
function _update_variable_param_values(vref::PointVariableRef,
                                       pref_vals::VectorTuple)
    info = JuMP.owner_model(vref).vars[JuMP.index(vref)].info
    ivref = JuMP.owner_model(vref).vars[JuMP.index(vref)].infinite_variable_ref
    JuMP.owner_model(vref).vars[JuMP.index(vref)] = PointVariable(info, ivref,
                                                                  pref_vals)
    return
end

# Get root name of infinite variable
function _root_name(vref::InfiniteVariableRef)
    name = JuMP.name(vref)
    return name[1:findfirst(isequal('('), name)-1]
end

## Return the parameter value as an appropriate string
# Number
function _make_str_value(value)::String
    return string(JuMP._string_round(value))
end

# Array{<:Number}
function _make_str_value(values::Array)::String
    if length(values) == 1
        return _make_str_value(first(values))
    end
    if length(values) <= 4
        str_value = "["
        counter = 1
        for value in values
            if counter != length(values)
                str_value *= JuMP._string_round(value) * ", "
            else
                str_value *= JuMP._string_round(value) * "]"
            end
            counter += 1
        end
        return string(str_value)
    else
        return string("[", JuMP._string_round(first(values)), ", ..., ",
                      JuMP._string_round(last(values)), "]")
    end
end

"""
    JuMP.set_name(vref::PointVariableRef, name::String)

Extend [`JuMP.set_name`](@ref JuMP.set_name(::JuMP.VariableRef, ::String)) to set
the names of point variables.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel(); @infinite_parameter(model, t in [0, 1]))
julia> @infinite_variable(model, T(t))
T(t)

julia> vref = @point_variable(model, T(0))
T(0)

julia> set_name(vref, "new_name")

julia> name(vref)
"new_name"
```
"""
function JuMP.set_name(vref::PointVariableRef, name::String)
    if length(name) == 0
        ivref = infinite_variable_ref(vref::PointVariableRef)
        name = _root_name(ivref)
        values = JuMP.owner_model(vref).vars[JuMP.index(vref)].parameter_values
        name = string(name, "(")
        for i in 1:size(values, 1)
            if i != size(values, 1)
                name *= _make_str_value(values[i, :]) * ", "
            else
                name *= _make_str_value(values[i, :]) * ")"
            end
        end
    end
    JuMP.owner_model(vref).var_to_name[JuMP.index(vref)] = name
    JuMP.owner_model(vref).name_to_var = nothing
    return
end

"""
    raw_parameter_refs(vref::InfiniteVariableRef)::VectorTuple{ParameterRef}

Return the raw [`VectorTuple`](@ref) of the parameter references that `vref`
depends on. This is primarily an internal method where
[`parameter_refs`](@ref parameter_refs(vref::InfiniteVariableRef))
is intended as the preferred user function.
"""
function raw_parameter_refs(vref::InfiniteVariableRef)::VectorTuple{ParameterRef}
    return JuMP.owner_model(vref).vars[JuMP.index(vref)].parameter_refs
end

"""
    parameter_refs(vref::InfiniteVariableRef)::Tuple

Return the `ParameterRef`(s) associated with the infinite variable `vref`. This
is formatted as a Tuple of containing the parameter references as they inputted
to define `vref`.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel(); @infinite_parameter(model, t in [0, 1]))
julia> @infinite_variable(model, T(t))
T(t)

julia> parameter_refs(T)
(t,)
```
"""
function parameter_refs(vref::InfiniteVariableRef)::Tuple
    return Tuple(raw_parameter_refs(vref))
end

"""
    parameter_list(vref::InfiniteVariableRef)::Vector{ParameterRef}

Return a vector of the parameter references that `vref` depends on. This is
primarily an internal method where [`parameter_refs`](@ref parameter_refs(vref::InfiniteVariableRef))
is intended as the preferred user function.
"""
function parameter_list(vref::InfiniteVariableRef)::Vector{ParameterRef}
    return raw_parameter_refs(vref).values
end

# get parameter list from raw VectorTuple
function parameter_list(prefs::VectorTuple{ParameterRef})::Vector{ParameterRef}
    return prefs.values
end

# Internal function used to change the parameter reference tuple of an infinite
# variable
function _update_variable_param_refs(vref::InfiniteVariableRef, prefs::VectorTuple)
    info = JuMP.owner_model(vref).vars[JuMP.index(vref)].info
    JuMP.owner_model(vref).vars[JuMP.index(vref)] = InfiniteVariable(info, prefs)
    return
end

"""
    set_parameter_refs(vref::InfiniteVariableRef, prefs::Tuple)

Specify a new parameter reference tuple `prefs` for the infinite variable `vref`.
Note each element must contain a single parameter reference or an array of
parameter references. Errors if a parameter is double specified, if an element
contains parameters with different group IDs, or if there are point variables
that depend on `vref`.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel(); @infinite_parameter(model, t in [0, 1]))
julia> @infinite_variable(model, T(t))
T(t)

julia> @infinite_parameter(model, x[1:2] in [-1, 1])
2-element Array{ParameterRef,1}:
 x[1]
 x[2]

julia> set_parameter_refs(T, (t, x))

julia> parameter_refs(T)
(t, [x[1], x[2]])
```
"""
function set_parameter_refs(vref::InfiniteVariableRef, prefs::Tuple)
    if used_by_point_variable(vref) || used_by_reduced_variable(vref)
        error("Cannot modify parameter dependencies if infinite variable has " *
              "dependent point variables and/or reduced infinite variables.")
    end
    prefs = VectorTuple(prefs)
    _check_parameter_tuple(error, prefs)
    _check_tuple_groups(error, prefs)
    _update_variable_param_refs(vref, prefs)
    JuMP.set_name(vref, _root_name(vref))
    if is_used(vref)
        set_optimizer_model_ready(JuMP.owner_model(vref), false)
    end
    return
end

"""
    add_parameter_ref(vref::InfiniteVariableRef,
                      pref::Union{ParameterRef, AbstractArray{<:ParameterRef}})

Add additional parameter reference or group of parameter references to be
associated with the infinite variable `vref`. Errors if the parameter references
are already added to the variable, if the added parameters have different
group IDs, or if `vref` has point variable dependencies.

```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel(); @infinite_parameter(model, t in [0, 1]))
julia> @infinite_variable(model, T(t))
T(t)

julia> @infinite_parameter(model, x[1:2] in [-1, 1])
2-element Array{ParameterRef,1}:
 x[1]
 x[2]

julia> add_parameter_ref(T, x)

julia> name(T)
"T(t, x)"
```
"""
function add_parameter_ref(vref::InfiniteVariableRef,
                       pref::Union{ParameterRef, AbstractArray{<:ParameterRef}})
    if used_by_point_variable(vref) || used_by_reduced_variable(vref)
       error("Cannot modify parameter dependencies if infinite variable has " *
             "dependent point variables and/or reduced infinite variables.")
    end
    # check that array only contains one group ID
    if pref isa AbstractArray
        first_group = group_id(first(pref))
        for i in 2:length(pref)
            if group_id(pref[i]) == first_group
                error("Each parameter tuple element must have contain only " *
                      "infinite parameters with the same group ID.")
            end
        end
    end
    # check that new group is unique from old ones
    prefs = raw_parameter_refs(vref)
    if !allunique(group_id.([prefs[:, 1]; first(pref)]))
        error("Cannot double specify infinite parameter references.")
    end
    # add the new parameter(s)
    prefs = push!(prefs, pref)
    _update_variable_param_refs(vref, prefs)
    JuMP.set_name(vref, _root_name(vref))
    if is_used(vref)
        set_optimizer_model_ready(JuMP.owner_model(vref), false)
    end
    return
end

"""
    parameter_bounds(vref::HoldVariableRef)::ParameterBounds

Return the [`ParameterBounds`](@ref) object associated with the hold variable
`vref`. It contains a dictionary where each key is a `ParameterRef` which points
to an `IntervalSet` that that defines a sub-domain for `vref` relative to that
parameter reference.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 10])
t

julia> @hold_variable(model, vref, parameter_bounds = (t in [0, 2]))
vref

julia> parameter_bounds(vref)
Subdomain bounds (1): t ∈ [0, 2]
```
"""
function parameter_bounds(vref::HoldVariableRef)::ParameterBounds
    return JuMP.owner_model(vref).vars[JuMP.index(vref)].parameter_bounds
end

"""
    has_parameter_bounds(vref::HoldVariableRef)::Bool

Return a `Bool` indicating if `vref` is limited to a sub-domain as defined
by parameter bound.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 10])
t

julia> @hold_variable(model, vref, parameter_bounds = (t in [0, 2]))
vref

julia> has_parameter_bounds(vref)
true
```
"""
function has_parameter_bounds(vref::HoldVariableRef)::Bool
    return length(parameter_bounds(vref)) != 0
end

# Other variable types
function has_parameter_bounds(vref::GeneralVariableRef)::Bool
    return false
end

# Internal function used to change the parameter bounds of a hold variable
function _update_variable_param_bounds(vref::HoldVariableRef,
                                       bounds::ParameterBounds)
    info = JuMP.owner_model(vref).vars[JuMP.index(vref)].info
    JuMP.owner_model(vref).vars[JuMP.index(vref)] = HoldVariable(info, bounds)
    return
end

## Check that the bounds dictionary is compadable with existing dependent measures
function _check_meas_bounds(bounds::ParameterBounds, data::AbstractMeasureData;
                            _error = error)
    if !measure_data_in_hold_bounds(data, bounds)
        _error("New bounds don't span existing dependent measure bounds.")
    end
    return
end

# Update the current bounds to overlap with the new bounds if possible
function _update_bounds(bounds1::Dict, bounds2::Dict; _error = error)
    # check each new bound
    for (pref, set) in bounds2
        # we have a new bound
        if !haskey(bounds1, pref)
            bounds1[pref] = set
        # the previous set and the new one do not overlap
        elseif set.lower_bound > bounds1[pref].upper_bound || set.upper_bound < bounds1[pref].lower_bound
            _error("Sub-domains of constraint and/or hold variable(s) do not" *
                   " overlap. Consider changing the parameter bounds of the" *
                   " constraint and/or hold variable(s).")
        # we have an existing bound
        else
            # we have a new stricter lower bound to update with
            if set.lower_bound > bounds1[pref].lower_bound
                bounds1[pref] = IntervalSet(set.lower_bound, bounds1[pref].upper_bound)
            end
            # we have a new stricter upper bound to update with
            if set.upper_bound < bounds1[pref].upper_bound
                bounds1[pref] = IntervalSet(bounds1[pref].lower_bound, set.upper_bound)
            end
        end
    end
    return
end

## Update the variable bounds if it has any
# GeneralVariableRef
function _update_var_bounds(vref::GeneralVariableRef,
                            constr_bounds::ParameterBounds)
    return
end

# HoldVariableRef
function _update_var_bounds(vref::HoldVariableRef,
                            constr_bounds::ParameterBounds)
    if has_parameter_bounds(vref)
        _update_bounds(constr_bounds.intervals, parameter_bounds(vref).intervals)
    end
    return
end

# MeasureRef
function _update_var_bounds(mref::MeasureRef,
                            constr_bounds::ParameterBounds)
    vrefs = _all_function_variables(measure_function(mref))
    for vref in vrefs
        _update_var_bounds(vref, constr_bounds)
    end
    return
end

## Rebuild the constraint bounds (don't change in case of error)
# BoundedScalarConstraint
function _rebuild_constr_bounds(c::BoundedScalarConstraint,
                                var_bounds::ParameterBounds; _error = error)
    # prepare new constraint
    vrefs = _all_function_variables(c.func)
    c_new = BoundedScalarConstraint(c.func, c.set, copy(c.orig_bounds), c.orig_bounds)
    # look for bounded hold variables and update bounds
    for vref in vrefs
        _update_var_bounds(vref, c_new.bounds)
    end
    # check if the constraint bounds have and update if doesn't
    if length(c_new.bounds) == 0
        c_new = JuMP.ScalarConstraint(c.func, c.set)
    end
    return c_new
end

# ScalarConstraint
function _rebuild_constr_bounds(c::JuMP.ScalarConstraint,
                                var_bounds::ParameterBounds; _error = error)
    return BoundedScalarConstraint(c.func, c.set, var_bounds, ParameterBounds())
end

"""
    set_parameter_bounds(vref::HoldVariableRef, bounds::ParameterBounds;
                         [force = false])

Specify a new dictionary of parameter bounds `bounds` for the hold variable `vref`.
These are stored in a [`ParameterBounds`](@ref) object which contains a dictionary.
Note the dictionary keys must be `ParameterRef`s and the values must be
`IntervalSet`s that indicate a particular sub-domain for which `vref` is defined.
This is meant to be primarily used by [`@set_parameter_bounds`](@ref) which
provides a more intuitive syntax.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 10])
t

julia> @hold_variable(model, vref)
vref

julia> set_parameter_bounds(vref, ParameterBounds(Dict(t => IntervalSet(0, 2))))

julia> parameter_bounds(vref)
Subdomain bounds (1): t ∈ [0, 2]
```
"""
function set_parameter_bounds(vref::HoldVariableRef, bounds::ParameterBounds;
                              force = false, _error = error)
    if has_parameter_bounds(vref) && !force
        _error("$vref already has parameter bounds. Consider adding more using " *
               "`add_parameter_bounds` or overwriting them by setting " *
               "the keyword argument `force = true`")
    else
        # check that bounds are valid and add support(s) if necessary
        _check_bounds(bounds, _error = _error)
        # check dependent measures
        cindices = Int[]
        if used_by_measure(vref)
            for mindex in JuMP.owner_model(vref).var_to_meas[JuMP.index(vref)]
                meas = JuMP.owner_model(vref).measures[mindex]
                _check_meas_bounds(bounds, meas.data, _error = _error)
                if used_by_constraint(MeasureRef(JuMP.owner_model(vref), mindex))
                    indices = JuMP.owner_model(vref).meas_to_constrs[mindex]
                    push!(cindices, indices...)
                end
            end
        end
        # set the new bounds
        _validate_bounds(JuMP.owner_model(vref), bounds, _error = _error)
        _update_variable_param_bounds(vref, bounds)
        # check and update dependent constraints
        if used_by_constraint(vref)
            union!(cindices, JuMP.owner_model(vref).var_to_constrs[JuMP.index(vref)])
        end
        for cindex in cindices
            constr = JuMP.owner_model(vref).constrs[cindex]
            new_constr = _rebuild_constr_bounds(constr, bounds, _error = _error)
            JuMP.owner_model(vref).constrs[cindex] = new_constr
        end
        # update status
        JuMP.owner_model(vref).has_hold_bounds = true
        if is_used(vref)
            set_optimizer_model_ready(JuMP.owner_model(vref), false)
        end
    end
    return
end

## Check and update the constraint bounds (don't change in case of error)
# BoundedScalarConstraint
function _update_constr_bounds(bounds::ParameterBounds, c::BoundedScalarConstraint;
                               _error = error)
    new_bounds_dict = copy(c.bounds.intervals)
    _update_bounds(new_bounds_dict, bounds.intervals, _error = _error)
    return BoundedScalarConstraint(c.func, c.set, ParameterBounds(new_bounds_dict),
                                   c.orig_bounds)
end

# ScalarConstraint
function _update_constr_bounds(bounds::ParameterBounds, c::JuMP.ScalarConstraint;
                               _error = error)
    return BoundedScalarConstraint(c.func, c.set, bounds, ParameterBounds())
end

"""
    add_parameter_bound(vref::HoldVariableRef, pref::ParameterRef,
                        lower::Number, upper::Number)

Add an additional parameter bound to `vref` such that it is defined over the
sub-domain based on `pref` from `lower` to `upper`. This is primarily meant to be
used by [`@add_parameter_bounds`](@ref).

```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 10])
t

julia> @hold_variable(model, vref)
vref

julia> add_parameter_bound(vref, t, 0, 2)

julia> parameter_bounds(vref)
Subdomain bounds (1): t ∈ [0, 2]
```
"""
function add_parameter_bound(vref::HoldVariableRef, pref::ParameterRef,
                             lower::Number, upper::Number; _error = error)
    # check the new bounds
    new_bounds = ParameterBounds(Dict(pref => IntervalSet(lower, upper)))
    _check_bounds(new_bounds, _error = _error)
    # check dependent measures
    meas_cindices = []
    if used_by_measure(vref)
        for mindex in JuMP.owner_model(vref).var_to_meas[JuMP.index(vref)]
            meas = JuMP.owner_model(vref).measures[mindex]
            _check_meas_bounds(new_bounds, meas.data, _error = _error)
            if used_by_constraint(MeasureRef(JuMP.owner_model(vref), mindex))
                indices = JuMP.owner_model(vref).meas_to_constrs[mindex]
                meas_cindices = [meas_cindices; indices]
            end
        end
    end
    # check and update dependent constraints
    if used_by_constraint(vref) || length(meas_cindices) != 0
        for cindex in unique([meas_cindices; JuMP.owner_model(vref).var_to_constrs[JuMP.index(vref)]])
            constr = JuMP.owner_model(vref).constrs[cindex]
            new_constr = _update_constr_bounds(new_bounds, constr, _error = _error)
            JuMP.owner_model(vref).constrs[cindex] = new_constr
        end
    end
    _validate_bounds(JuMP.owner_model(vref), new_bounds, _error = _error)
    # add the bounds
    parameter_bounds(vref).intervals[pref] = IntervalSet(lower, upper)
    # update status
    JuMP.owner_model(vref).has_hold_bounds = true
    if is_used(vref)
        set_optimizer_model_ready(JuMP.owner_model(vref), false)
    end
    return
end

"""
    delete_parameter_bound(vref::HoldVariableRef, pref::ParameterRef)

Delete the parameter bound of the hold variable `vref` associated with the
infinite parameter `pref` if `vref` has such a bound. Note that any other
parameter bounds will be unaffected. Any constraints that employ `vref` will
be updated accordingly.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel())
julia> @infinite_parameter(model, x[1:2] in [0, 10])
2-element Array{ParameterRef,1}:
 x[1]
 x[2]

julia> @hold_variable(model, z, parameter_bounds = (x in [0, 1]))
z

julia> delete_parameter_bound(z, x[2])

julia> parameter_bounds(z)
Subdomain bounds (1): x[1] ∈ [0, 1]
```
"""
function delete_parameter_bound(vref::HoldVariableRef, pref::ParameterRef)
    # get the current bounds
    bounds = parameter_bounds(vref)
    # check if there are bounds for pref and act accordingly
    if haskey(bounds.intervals, pref)
        delete!(bounds.intervals, pref)
        # check for dependent measures that are used by constraints
        meas_cindices = []
        if used_by_measure(vref)
            for mindex in JuMP.owner_model(vref).var_to_meas[JuMP.index(vref)]
                if used_by_constraint(MeasureRef(JuMP.owner_model(vref), mindex))
                    indices = JuMP.owner_model(vref).meas_to_constrs[mindex]
                    meas_cindices = [meas_cindices; indices]
                end
            end
        end
        # check and update dependent constraints
        if used_by_constraint(vref) || length(meas_cindices) != 0
            for cindex in unique([meas_cindices; JuMP.owner_model(vref).var_to_constrs[JuMP.index(vref)]])
                constr = JuMP.owner_model(vref).constrs[cindex]
                new_constr = _rebuild_constr_bounds(constr, bounds)
                JuMP.owner_model(vref).constrs[cindex] = new_constr
            end
        end
    end
    return
end

"""
    delete_parameter_bounds(vref::HoldVariableRef)

Delete all the parameter bounds of the hold variable `vref`. Any constraints
that employ `vref` will be updated accordingly.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; model = InfiniteModel())
julia> @infinite_parameter(model, x[1:2] in [0, 10])
2-element Array{ParameterRef,1}:
 x[1]
 x[2]

julia> @hold_variable(model, z, parameter_bounds = (x in [0, 1]))
z

julia> delete_parameter_bounds(z)

julia> parameter_bounds(z)
Subdomain bounds (0):
```
"""
function delete_parameter_bounds(vref::HoldVariableRef)
    # get the current bounds
    bounds = parameter_bounds(vref)
    # check if there are bounds and act accordingly
    if length(bounds) > 0
        _update_variable_param_bounds(vref, ParameterBounds())
        # check for dependent measures that are used by constraints
        meas_cindices = []
        if used_by_measure(vref)
            for mindex in JuMP.owner_model(vref).var_to_meas[JuMP.index(vref)]
                if used_by_constraint(MeasureRef(JuMP.owner_model(vref), mindex))
                    indices = JuMP.owner_model(vref).meas_to_constrs[mindex]
                    meas_cindices = [meas_cindices; indices]
                end
            end
        end
        # check and update dependent constraints
        if used_by_constraint(vref) || length(meas_cindices) != 0
            for cindex in unique([meas_cindices; JuMP.owner_model(vref).var_to_constrs[JuMP.index(vref)]])
                constr = JuMP.owner_model(vref).constrs[cindex]
                new_constr = _rebuild_constr_bounds(constr, bounds)
                JuMP.owner_model(vref).constrs[cindex] = new_constr
            end
        end
    end
    return
end

"""
    JuMP.set_name(vref::InfiniteVariableRef, root_name::String)

Extend [`JuMP.set_name`](@ref JuMP.set_name(::JuMP.VariableRef, ::String)) to set
names of infinite variables. Adds on to `root_name` the ending `(prefs...)`
where the parameter reference names are listed in the same format as input in
the parameter reference tuple.

**Example**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @infinite_variable(m, vref(@infinite_parameter(m, t in [0, 1]))))
julia> name(vref)
"vref(t)"

julia> set_name(vref, "new_name")

julia> name(vref)
"new_name(t)"
```
"""
function JuMP.set_name(vref::InfiniteVariableRef, root_name::String)
    if length(root_name) == 0
        root_name = "noname"
    end
    prefs = raw_parameter_refs(vref)
    param_names = [_root_name(pref) for pref in prefs[:, 1]]
    param_name_tuple = "("
    for i in eachindex(param_names)
        if i != length(param_names)
            param_name_tuple *= string(param_names[i], ", ")
        else
            param_name_tuple *= string(param_names[i])
        end
    end
    param_name_tuple *= ")"
    var_name = string(root_name, param_name_tuple)
    JuMP.owner_model(vref).var_to_name[JuMP.index(vref)] = var_name
    JuMP.owner_model(vref).name_to_var = nothing
    return
end

# Make a variable reference
function _make_variable_ref(model::InfiniteModel, index::Int)::GeneralVariableRef
    if isa(model.vars[index], InfiniteVariable)
        return InfiniteVariableRef(model, index)
    elseif isa(model.vars[index], PointVariable)
        return PointVariableRef(model, index)
    else
        return HoldVariableRef(model, index)
    end
end

"""
    JuMP.variable_by_name(model::InfiniteModel,
                          name::String)::Union{GeneralVariableRef, Nothing}

Extend [`JuMP.variable_by_name`](@ref JuMP.variable_by_name(::JuMP.Model, ::String))
for `InfiniteModel` objects. Return the variable reference assoociated with a
variable name. Errors if multiple variables have the same name. Returns nothing
if no such name exists.

**Examples**
```jldoctest; setup = :(using InfiniteOpt, JuMP; m = InfiniteModel(); @hold_variable(m, base_name = "var_name"))
julia> variable_by_name(m, "var_name")
var_name

julia> variable_by_name(m, "fake_name")

```
"""
function JuMP.variable_by_name(model::InfiniteModel,
                               name::String)::Union{GeneralVariableRef, Nothing}
    if model.name_to_var === nothing
        # Inspired from MOI/src/Utilities/model.jl
        model.name_to_var = Dict{String, Int}()
        for (var, var_name) in model.var_to_name
            if haskey(model.name_to_var, var_name)
                # -1 is a special value that means this string does not map to
                # a unique variable name.
                model.name_to_var[var_name] = -1
            else
                model.name_to_var[var_name] = var
            end
        end
    end
    index = get(model.name_to_var, name, nothing)
    if index isa Nothing
        return nothing
    elseif index == -1
        error("Multiple variables have the name $name.")
    else
        return _make_variable_ref(model, index)
    end
end

"""
    JuMP.all_variables(model::InfiniteModel)::Vector{GeneralVariableRef}

Extend [`JuMP.all_variables`](@ref JuMP.all_variables(::JuMP.Model)) to return a
list of all the variable references associated with `model`.

**Examples**
```julia-repl
julia> all_variables(model)
4-element Array{GeneralVariableRef,1}:
 y(t)
 w(t, x)
 y(0)
 z
```
"""
function JuMP.all_variables(model::InfiniteModel)::Vector{GeneralVariableRef}
    vrefs_list = Vector{GeneralVariableRef}(undef, JuMP.num_variables(model))
    indexes = sort([index for index in keys(model.vars)])
    counter = 1
    for index in indexes
        vrefs_list[counter] = _make_variable_ref(model, index)
        counter += 1
    end
    return vrefs_list
end
