"""
    JuMP.owner_model(cref::GeneralConstraintRef)::InfiniteModel

Extend [`JuMP.owner_model`](@ref JuMP.owner_model(::JuMP.ConstraintRef)) to
return the infinite model associated with `cref`.

**Example**
```julia-repl
julia> model = owner_model(cref)
An InfiniteOpt Model
Minimization problem with:
Variables: 3
Objective function type: HoldVariableRef
`GenericAffExpr{Float64,FiniteVariableRef}`-in-`MathOptInterface.EqualTo{Float64}`: 1 constraint
Names registered in the model: g, t, h, x
Optimizer model backend information:
Model mode: AUTOMATIC
CachingOptimizer state: NO_OPTIMIZER
Solver name: No optimizer attached.
```
"""
JuMP.owner_model(cref::GeneralConstraintRef)::InfiniteModel = cref.model

"""
    JuMP.index(cref::GeneralConstraintRef)::Int

Extend [`JuMP.index`](@ref JuMP.index(::JuMP.ConstraintRef)) to return the index
of an `InfiniteOpt` constraint `cref`.

**Example**
```jldoctest; setup = :(using JuMP, InfiniteOpt; model = InfiniteModel(); cref = GeneralVariableRef(model, 2))
julia> index(cref)
2
```
"""
JuMP.index(cref::GeneralConstraintRef)::Int = cref.index

# Extend Base and JuMP functions
function Base.:(==)(v::GeneralConstraintRef, w::GeneralConstraintRef)::Bool
    return v.model === w.model && v.index == w.index && v.shape == w.shape && typeof(v) == typeof(w)
end
Base.broadcastable(cref::GeneralConstraintRef) = Ref(cref)
JuMP.constraint_type(m::InfiniteModel) = GeneralConstraintRef

# This might not be necessary...
function JuMP.build_constraint(_error::Function,
                               v::Union{InfiniteVariableRef,
                                        ReducedInfiniteVariableRef, MeasureRef},
                               set::MOI.AbstractScalarSet;
                               parameter_bounds::ParameterBounds = ParameterBounds())
    # make the constraint
    if length(parameter_bounds) != 0
        _check_bounds(parameter_bounds)
        return BoundedScalarConstraint(v, set, parameter_bounds,
                                       copy(parameter_bounds))
    else
        return JuMP.ScalarConstraint(v, set)
    end
end

"""
    JuMP.build_constraint(_error::Function, expr::InfiniteExpr,
                          set::MOI.AbstractScalarSet;
                          [parameter_bounds::ParameterBounds = ParameterBounds()])

Extend `JuMP.build_constraint` to accept the ```parameter_bounds``` argument
and return a [`BoundedScalarConstraint`](@ref) if the ```parameter_bounds``` keyword
argument is specifed or return a [`JuMP.ScalarConstraint`](@ref) otherwise. This is
primarily intended to work as an internal function for constraint macros.

**Example**
```jldoctest; setup = :(using JuMP, InfiniteOpt; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 10]);

julia> @infinite_variable(model, g(t));

julia> @hold_variable(model, x);

julia> constr = build_constraint(error, g + x, MOI.EqualTo(42.0),
              parameter_bounds = ParameterBounds(Dict(t => IntervalSet(0, 1))));

julia> isa(constr, BoundedScalarConstraint)
true
```
"""
function JuMP.build_constraint(_error::Function,
                               expr::Union{InfiniteExpr, MeasureExpr},
                               set::MOI.AbstractScalarSet;
                               parameter_bounds::ParameterBounds = ParameterBounds())
    # make the constraint
    offset = JuMP.constant(expr)
    JuMP.add_to_expression!(expr, -offset)
    if length(parameter_bounds) != 0
        _check_bounds(parameter_bounds)
        return BoundedScalarConstraint(expr, MOIU.shift_constant(set, -offset),
                                       parameter_bounds, copy(parameter_bounds))
    else
        return JuMP.ScalarConstraint(expr, MOIU.shift_constant(set, -offset))
    end
end

# Used to update the model.var_to_constrs field
function _update_var_constr_mapping(vrefs::Vector{<:GeneralVariableRef},
                                    cindex::Int)
    for vref in vrefs
        model = JuMP.owner_model(vref)
        if isa(vref, InfOptVariableRef)
            if haskey(model.var_to_constrs, JuMP.index(vref))
                push!(model.var_to_constrs[JuMP.index(vref)], cindex)
            else
                model.var_to_constrs[JuMP.index(vref)] = [cindex]
            end
        elseif isa(vref, ParameterRef)
            if haskey(model.param_to_constrs, JuMP.index(vref))
                push!(model.param_to_constrs[JuMP.index(vref)], cindex)
            else
                model.param_to_constrs[JuMP.index(vref)] = [cindex]
            end
        elseif isa(vref, MeasureRef)
            if haskey(model.meas_to_constrs, JuMP.index(vref))
                push!(model.meas_to_constrs[JuMP.index(vref)], cindex)
            else
                model.meas_to_constrs[JuMP.index(vref)] = [cindex]
            end
            if haskey(model.constr_to_meas, cindex)
                push!(model.constr_to_meas[cindex], JuMP.index(vref))
            else
                model.constr_to_meas[cindex] = [JuMP.index(vref)]
            end
        elseif isa(vref, ReducedInfiniteVariableRef)
            if haskey(model.reduced_to_constrs, JuMP.index(vref))
                push!(model.reduced_to_constrs[JuMP.index(vref)], cindex)
            else
                model.reduced_to_constrs[JuMP.index(vref)] = [cindex]
            end
        end
    end
    return
end

# Define variable references that aren't hold varriables
const NoHoldRefs = Union{ParameterRef, MeasureRef, InfiniteVariableRef,
                         ReducedInfiniteVariableRef, PointVariableRef}

## Perfrom bound checks and update them if needed, then return the updated constraint
# BoundedScalarConstraint with no hold variables
function _check_and_update_bounds(model::InfiniteModel, c::BoundedScalarConstraint,
                                  vrefs::Vector{<:NoHoldRefs})::JuMP.AbstractConstraint
    _validate_bounds(model, c.bounds)
    return c
end

# BoundedScalarConstraint with hold variables
function _check_and_update_bounds(model::InfiniteModel, c::BoundedScalarConstraint,
                                  vrefs::Vector)::JuMP.AbstractConstraint
    # look for bounded hold variables and update bounds
    for vref in vrefs
        _update_var_bounds(vref, c.bounds)
    end
    # now validate and return
    _validate_bounds(model, c.bounds)
    # TODO should we check that bounds don't violate point variables?
    return c
end

# ScalarConstraint with no hold variables
function _check_and_update_bounds(model::InfiniteModel, c::JuMP.ScalarConstraint,
                                  vrefs::Vector{<:NoHoldRefs})::JuMP.AbstractConstraint
    return c
end

# ScalarConstraint with hold variables
function _check_and_update_bounds(model::InfiniteModel, c::JuMP.ScalarConstraint,
                                  vrefs::Vector)::JuMP.AbstractConstraint
    bounds = ParameterBounds()
    # check for bounded hold variables and build the intersection of the bounds
    for vref in vrefs
        _update_var_bounds(vref, bounds)
    end
    # if we added bounds, change to a bounded constraint and validate
    if length(bounds) != 0
        c = BoundedScalarConstraint(c.func, c.set, bounds, ParameterBounds())
        _validate_bounds(model, c.bounds)
    end
    # TODO should we check that bounds don't violate point variables?
    return c
end

# Extend functions for bounded constraints
JuMP.shape(c::BoundedScalarConstraint) = JuMP.shape(JuMP.ScalarConstraint(c.func, c.set))
JuMP.jump_function(c::BoundedScalarConstraint) = c.func
JuMP.moi_set(c::BoundedScalarConstraint) = c.set

"""
    JuMP.add_constraint(model::InfiniteModel, c::JuMP.AbstractConstraint,
                        [name::String = ""])

Extend [`JuMP.add_constraint`](@ref JuMP.add_constraint(::JuMP.Model, ::JuMP.AbstractConstraint, ::String))
to add a constraint `c` to an infinite model
`model` with name `name`. Returns an appropriate constraint reference whose type
depends on what variables are used to define the constraint. Errors if a vector
constraint is used, the constraint only constains parameters, or if any
variables do not belong to `model`. This is primarily used as an internal
method for the cosntraint macros.

**Example**
```jldoctest; setup = :(using JuMP, InfiniteOpt; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 10]);

julia> @infinite_variable(model, g(t));

julia> @hold_variable(model, x);

julia> constr = build_constraint(error, g + x, MOI.EqualTo(42));

julia> cref = add_constraint(model, constr, "name")
name : g(t) + x = 42.0
```
"""
function JuMP.add_constraint(model::InfiniteModel, c::JuMP.AbstractConstraint,
                             name::String = "")
    isa(c, JuMP.VectorConstraint) && error("Vector constraints not supported.")
    JuMP.check_belongs_to_model(c.func, model)
    vrefs = _all_function_variables(c.func)
    isa(vrefs, Vector{ParameterRef}) && error("Constraints cannot contain " *
                                              "only parameters.")
    if model.has_hold_bounds
        c = _check_and_update_bounds(model, c, vrefs)
    elseif c isa BoundedScalarConstraint
        _validate_bounds(model, c.bounds)
    end
    model.next_constr_index += 1
    index = model.next_constr_index
    if length(vrefs) != 0
        _update_var_constr_mapping(vrefs, index)
    end
    if c.func isa InfiniteExpr
        cref = InfiniteConstraintRef(model, index, JuMP.shape(c))
    elseif c.func isa MeasureExpr
        cref = MeasureConstraintRef(model, index, JuMP.shape(c))
    else
        cref = FiniteConstraintRef(model, index, JuMP.shape(c))
    end
    model.constrs[index] = c
    JuMP.set_name(cref, name)
    model.constr_in_var_info[index] = false
    set_optimizer_model_ready(model, false)
    return cref
end

"""
    JuMP.delete(model::InfiniteModel, cref::GeneralConstraintRef)

Extend [`JuMP.delete`](@ref JuMP.delete(::JuMP.Model, ::JuMP.ConstraintRef{JuMP.Model}))
to delete an `InfiniteOpt` constraint and all associated information. Errors
if `cref` is invalid.

**Example**
```julia-repl
julia> print(model)
Min measure(g(t)*t) + z
Subject to
 z ≥ 0.0
 g(t) + z ≥ 42.0
 t ∈ [0, 6]

julia> delete(model, cref)

julia> print(model)
Min measure(g(t)*t) + z
Subject to
 z ≥ 0.0
 t ∈ [0, 6]
```
"""
function JuMP.delete(model::InfiniteModel, cref::GeneralConstraintRef)
    # check valid reference
    @assert JuMP.is_valid(model, cref) "Invalid constraint reference."
    # update variable dependencies
    all_vrefs = _all_function_variables(model.constrs[JuMP.index(cref)].func)
    for vref in all_vrefs
        if isa(vref, InfOptVariableRef)
            filter!(e -> e != JuMP.index(cref),
                    model.var_to_constrs[JuMP.index(vref)])
            if length(model.var_to_constrs[JuMP.index(vref)]) == 0
                delete!(model.var_to_constrs, JuMP.index(vref))
            end
        elseif isa(vref, ParameterRef)
            filter!(e -> e != JuMP.index(cref),
                    model.param_to_constrs[JuMP.index(vref)])
            if length(model.param_to_constrs[JuMP.index(vref)]) == 0
                delete!(model.param_to_constrs, JuMP.index(vref))
            end
        elseif isa(vref, MeasureRef)
            filter!(e -> e != JuMP.index(cref),
                    model.meas_to_constrs[JuMP.index(vref)])
            if length(model.meas_to_constrs[JuMP.index(vref)]) == 0
                delete!(model.meas_to_constrs, JuMP.index(vref))
            end
        elseif isa(vref, ReducedInfiniteVariableRef)
            filter!(e -> e != JuMP.index(cref),
                    model.reduced_to_constrs[JuMP.index(vref)])
            if length(model.reduced_to_constrs[JuMP.index(vref)]) == 0
                delete!(model.reduced_to_constrs, JuMP.index(vref))
            end
        end
    end
    # delete constraint information
    delete!(model.constrs, JuMP.index(cref))
    delete!(model.constr_to_name, JuMP.index(cref))
    delete!(model.constr_in_var_info, JuMP.index(cref))
    delete!(model.constr_to_meas, JuMP.index(cref))
    # reset optimizer model status
    set_optimizer_model_ready(model, false)
    return
end

"""
    JuMP.is_valid(model::InfiniteModel, cref::GeneralConstraintRef)::Bool

Extend [`JuMP.is_valid`](@ref JuMP.is_valid(::JuMP.Model, ::JuMP.ConstraintRef{JuMP.Model}))
to return `Bool` whether an `InfiniteOpt` constraint reference is valid.

**Example**
```jldoctest; setup = :(using JuMP, InfiniteOpt; model = InfiniteModel(); cref = @constraint(model, 2 == 2))
julia> is_valid(model, cref)
true
```
"""
function JuMP.is_valid(model::InfiniteModel, cref::GeneralConstraintRef)::Bool
    return (model === JuMP.owner_model(cref) && JuMP.index(cref) in keys(model.constrs))
end

"""
    JuMP.constraint_object(cref::GeneralConstraintRef)::JuMP.AbstractConstraint

Extend [`JuMP.constraint_object`](@ref JuMP.constraint_object)
to return the constraint object associated with `cref`.

**Example**
```jldoctest; setup = :(using JuMP, InfiniteOpt; model = InfiniteModel())
julia> @infinite_parameter(model, t in [0, 10]);

julia> @hold_variable(model, x <= 1);

julia> cref = UpperBoundRef(x);

julia> obj = constraint_object(cref)
ScalarConstraint{HoldVariableRef,MathOptInterface.LessThan{Float64}}(x,
MathOptInterface.LessThan{Float64}(1.0))
```
"""
function JuMP.constraint_object(cref::GeneralConstraintRef)::JuMP.AbstractConstraint
    return JuMP.owner_model(cref).constrs[JuMP.index(cref)]
end

"""
    JuMP.name(cref::GeneralConstraintRef)::String

Extend [`JuMP.name`](@ref JuMP.name(::JuMP.ConstraintRef{JuMP.Model,<:JuMP._MOICON})
to return the name of an `InfiniteOpt` constraint.

**Example**
```jldoctest; setup = :(using JuMP, InfiniteOpt; model = InfiniteModel(); cref = @constraint(model, constr_name, 2 == 2))
julia> name(cref)
"constr_name"
```
"""
function JuMP.name(cref::GeneralConstraintRef)::String
    return JuMP.owner_model(cref).constr_to_name[JuMP.index(cref)]
end

"""
    JuMP.set_name(cref::GeneralConstraintRef, name::String)

Extend [`JuMP.set_name`](@ref JuMP.set_name(::JuMP.ConstraintRef{JuMP.Model,<:JuMP._MOICON}, ::String))
to specify the name of a constraint `cref`.

**Example**
```jldoctest; setup = :(using JuMP, InfiniteOpt; model = InfiniteModel(); cref = @constraint(model, 2 == 2))
julia> set_name(cref, "new_name")

julia> name(cref)
"new_name"
```
"""
function JuMP.set_name(cref::GeneralConstraintRef, name::String)
    JuMP.owner_model(cref).constr_to_name[JuMP.index(cref)] = name
    JuMP.owner_model(cref).name_to_constr = nothing
    return
end

"""
    has_parameter_bounds(cref::GeneralConstraintRef)::Bool

Return a `Bool` indicating if `cref` is limited to a sub-domain as defined
by a [`ParameterBounds`](@ref) object.

**Example**
```julia-repl
julia> has_parameter_bounds(cref)
true
```
"""
function has_parameter_bounds(cref::GeneralConstraintRef)::Bool
    if JuMP.constraint_object(cref) isa BoundedScalarConstraint
        return length(JuMP.constraint_object(cref).bounds) != 0
    else
        return false
    end
end

"""
    parameter_bounds(cref::GeneralConstraintRef)::ParameterBounds

Return the [`ParameterBounds`](@ref) object associated with the constraint
`cref`. Errors if `cref` does not have parameter bounds.

**Example**
```julia-repl
julia> parameter_bounds(cref)
Subdomain bounds (1): t ∈ [0, 2]
```
"""
function parameter_bounds(cref::GeneralConstraintRef)::ParameterBounds
    !has_parameter_bounds(cref) && error("$cref does not have parameter bounds.")
    return JuMP.constraint_object(cref).bounds
end

# Internal function used to change the parameter bounds of a constraint
function _update_constr_param_bounds(cref::GeneralConstraintRef,
                                     bounds::ParameterBounds,
                                     orig_bounds::ParameterBounds)
    c = JuMP.constraint_object(cref)
    if length(bounds) != 0
        JuMP.owner_model(cref).constrs[JuMP.index(cref)] = BoundedScalarConstraint(
                                             c.func, c.set, bounds, orig_bounds)
    else
        JuMP.owner_model(cref).constrs[JuMP.index(cref)] = JuMP.ScalarConstraint(
                                                                  c.func, c.set)
    end
    return
end

"""
    set_parameter_bounds(cref::GeneralConstraintRef, bounds:ParameterBounds;
                         [force = false])

Specify a new [`ParameterBounds`](@ref) object `bounds` for the constraint `cref`.
This is meant to be primarily used by [`@set_parameter_bounds`](@ref) which
provides a more intuitive syntax.

**Example**
```julia-repl
julia> set_parameter_bounds(cref, ParameterBounds(Dict(t => IntervalSet(0, 2))))

julia> parameter_bounds(cref)
Subdomain bounds (1): t ∈ [0, 2]
```
"""
function set_parameter_bounds(cref::GeneralConstraintRef, bounds::ParameterBounds;
                              force = false, _error = error)
    if has_parameter_bounds(cref) && !force
        _error("$cref already has parameter bounds. Consider adding more using " *
               "`add_parameter_bounds` or overwriting them by setting " *
               "the keyword argument `force = true`")
    else
        # check that bounds are valid and add support(s) if necessary
        _check_bounds(bounds, _error = _error)
        _validate_bounds(JuMP.owner_model(cref), bounds, _error = _error)
        # consider hold variables
        orig_bounds = copy(bounds)
        vrefs = _all_function_variables(JuMP.constraint_object(cref).func)
        for vref in vrefs
            _update_var_bounds(vref, bounds)
        end
        # set the new bounds
        _update_constr_param_bounds(cref, bounds, orig_bounds)
        # update status
        set_optimizer_model_ready(JuMP.owner_model(cref), false)
    end
    return
end

"""
    add_parameter_bound(cref::GeneralConstraintRef, pref::ParameterRef,
                        lower::Number, upper::Number)

Add an additional parameter bound to `cref` such that it is defined over the
sub-domain based on `pref` from `lower` to `upper`. This is primarily meant to be
used by [`@add_parameter_bounds`](@ref).

```julia-repl
julia> add_parameter_bound(cref, t, 0, 2)

julia> parameter_bounds(cref)
Subdomain bounds (1): t ∈ [0, 2]
```
"""
function add_parameter_bound(cref::GeneralConstraintRef, pref::ParameterRef,
                             lower::Number, upper::Number; _error = error)
    # check the new bounds
    new_bounds = ParameterBounds(Dict(pref => IntervalSet(lower, upper)))
    _check_bounds(new_bounds, _error = _error)
    _validate_bounds(JuMP.owner_model(cref), new_bounds, _error = _error)
    # add the bounds
    if JuMP.constraint_object(cref) isa BoundedScalarConstraint
        _update_bounds(parameter_bounds(cref).intervals, new_bounds.intervals,
                        _error = _error)
        _update_bounds(JuMP.constraint_object(cref).orig_bounds.intervals,
                       new_bounds.intervals, _error = _error)
    else
        _update_constr_param_bounds(cref, new_bounds, copy(new_bounds))
    end
    # update the optimizer model status
    set_optimizer_model_ready(JuMP.owner_model(cref), false)
    return
end

"""
    delete_parameter_bound(cref::GeneralConstraintRef, pref::ParameterRef)

Delete the parameter bound of the constraint `cref` associated with the
infinite parameter `pref` if `cref` has such a bound. Note that any other
parameter bounds will be unaffected. Note any bounds that are needed for
hold variables inside in `cref` will be unaffected.

**Example**
```julia-repl
julia> @BDconstraint(model, c1(x == 0), y <= 42)
c1 : y(x) ≤ 42, ∀ x[1] = 0, x[2] = 0

julia> delete_parameter_bounds(c1, x[2])

julia> c1
c1 : y(x) ≤ 42, ∀ x[1] = 0
```
"""
function delete_parameter_bound(cref::GeneralConstraintRef, pref::ParameterRef)
    # check if has bounds on pref from the constraint
    constr = JuMP.constraint_object(cref)
    if has_parameter_bounds(cref) && haskey(constr.orig_bounds.intervals, pref)
        delete!(constr.orig_bounds.intervals, pref)
        # consider hold variables
        new_bounds = copy(constr.orig_bounds)
        vrefs = _all_function_variables(constr.func)
        for vref in vrefs
            _update_var_bounds(vref, new_bounds)
        end
        # set the new bounds
        _update_constr_param_bounds(cref, new_bounds, constr.orig_bounds)
    end
    return
end

"""
    delete_parameter_bounds(cref::GeneralConstraintRef)

Delete all the parameter bounds of the constraint `cref`. Note any bounds that
are needed for hold variables inside in `cref` will be unaffected.

**Example**
```julia-repl
julia> @BDconstraint(model, c1(x == 0), y <= 42)
c1 : y(x) ≤ 42, ∀ x[1] = 0, x[2] = 0

julia> delete_parameter_bounds(c1)

julia> c1
c1 : y(x) ≤ 42
```
"""
function delete_parameter_bounds(cref::GeneralConstraintRef)
    # check if has bounds on pref from the constraint
    constr = JuMP.constraint_object(cref)
    if has_parameter_bounds(cref) && length(constr.orig_bounds) != 0
        # consider hold variables
        new_bounds = ParameterBounds()
        vrefs = _all_function_variables(constr.func)
        for vref in vrefs
            _update_var_bounds(vref, new_bounds)
        end
        # set the new bounds
        _update_constr_param_bounds(cref, new_bounds, ParameterBounds())
    end
    return
end

# Return a constraint set with an updated value
function _set_set_value(set::S, value::Real) where {T, S <: Union{MOI.LessThan{T},
                                            MOI.GreaterThan{T}, MOI.EqualTo{T}}}
    return S(convert(T, value))
end

"""
    JuMP.set_normalized_rhs(cref::GeneralConstraintRef, value::Real)

Set the right-hand side term of `constraint` to `value`.
Note that prior to this step, JuMP will aggregate all constant terms onto the
right-hand side of the constraint. For example, given a constraint `2x + 1 <=
2`, `set_normalized_rhs(con, 4)` will create the constraint `2x <= 4`, not `2x +
1 <= 4`.

```julia-repl
julia> @constraint(model, con, 2x + 1 <= 2)
con : 2 x ≤ 1.0

julia> set_normalized_rhs(con, 4)

julia> con
con : 2 x ≤ 4.0
```
"""
function JuMP.set_normalized_rhs(cref::GeneralConstraintRef, value::Real)
    old_constr = JuMP.constraint_object(cref)
    new_set = _set_set_value(old_constr.set, value)
    if old_constr isa BoundedScalarConstraint
        new_constr = BoundedScalarConstraint(old_constr.func, new_set,
                                             old_constr.bounds,
                                             old_constr.orig_bounds)
    else
        new_constr = JuMP.ScalarConstraint(old_constr.func, new_set)
    end
    JuMP.owner_model(cref).constrs[JuMP.index(cref)] = new_constr
    return
end

"""
    JuMP.normalized_rhs(cref::GeneralConstraintRef)::Number

Return the right-hand side term of `cref` after JuMP has converted the
constraint into its normalized form.
"""
function JuMP.normalized_rhs(cref::GeneralConstraintRef)::Number
    con = JuMP.constraint_object(cref)
    return MOI.constant(con.set)
end

"""
    JuMP.add_to_function_constant(cref::GeneralConstraintRef, value::Real)

Add `value` to the function constant term.
Note that for scalar constraints, JuMP will aggregate all constant terms onto the
right-hand side of the constraint so instead of modifying the function, the set
will be translated by `-value`. For example, given a constraint `2x <=
3`, `add_to_function_constant(c, 4)` will modify it to `2x <= -1`.
```
"""
function JuMP.add_to_function_constant(cref::GeneralConstraintRef, value::Real)
    current_value = JuMP.normalized_rhs(cref)
    JuMP.set_normalized_rhs(cref, current_value - value)
    return
end

"""
    JuMP.set_normalized_coefficient(cref::GeneralConstraintRef,
                                    variable::GeneralVariableRef, value::Real)

Set the coefficient of `variable` in the constraint `constraint` to `value`.
Note that prior to this step, JuMP will aggregate multiple terms containing the
same variable. For example, given a constraint `2x + 3x <= 2`,
`set_normalized_coefficient(con, x, 4)` will create the constraint `4x <= 2`.

```julia-repl
julia> con
con : 5 x ≤ 2.0

julia> set_normalized_coefficient(con, x, 4)

julia> con
con : 4 x ≤ 2.0
```
"""
function JuMP.set_normalized_coefficient(cref::GeneralConstraintRef,
                                         variable::GeneralVariableRef,
                                         value::Real)
    # update the constraint expression and update the constraint
    old_constr = JuMP.constraint_object(cref)
    new_expr = _set_variable_coefficient!(old_constr.func, variable, value)
    if old_constr isa BoundedScalarConstraint
        new_constr = BoundedScalarConstraint(new_expr, old_constr.set,
                                             old_constr.bounds,
                                             old_constr.orig_bounds)
    else
        new_constr = JuMP.ScalarConstraint(new_expr, old_constr.set)
    end
    JuMP.owner_model(cref).constrs[JuMP.index(cref)] = new_constr
    return
end

"""
    JuMP.normalized_coefficient(cref::GeneralConstraintRef,
                                variable::GeneralVariableRef)::Number

Return the coefficient associated with `variable` in `constraint` after JuMP has
normalized the constraint into its standard form.
"""
function JuMP.normalized_coefficient(cref::GeneralConstraintRef,
                                     variable::GeneralVariableRef)::Number
    con = JuMP.constraint_object(cref)
    if con.func isa GeneralVariableRef && con.func == variable
        return 1.0
    elseif con.func isa GeneralVariableRef
        return 0.0
    else
        return JuMP._affine_coefficient(con.func, variable)
    end
end

# Return the appropriate constraint reference given the index and model
function _make_constraint_ref(model::InfiniteModel,
                              index::Int)::GeneralConstraintRef
    if model.constrs[index].func isa InfiniteExpr
        return InfiniteConstraintRef(model, index,
                                     JuMP.shape(model.constrs[index]))
    elseif model.constrs[index].func isa MeasureExpr
        return MeasureConstraintRef(model, index,
                                    JuMP.shape(model.constrs[index]))
    else
        return FiniteConstraintRef(model, index,
                                   JuMP.shape(model.constrs[index]))
    end
end

"""
    JuMP.constraint_by_name(model::InfiniteModel,
                            name::String)::Union{GeneralConstraintRef, Nothing}

Extend [`JuMP.constraint_by_name`](@ref JuMP.constraint_by_name)
to return the constraint reference
associated with `name` if one exists or returns nothing. Errors if more than
one constraint uses the same name.

**Example**
```julia-repl
julia> constraint_by_name(model, "constr_name")
constr_name : x + pt = 3.0
```
"""
function JuMP.constraint_by_name(model::InfiniteModel, name::String)
    if model.name_to_constr === nothing
        # Inspired from MOI/src/Utilities/model.jl
        model.name_to_constr = Dict{String, Int}()
        for (constr, constr_name) in model.constr_to_name
            if haskey(model.name_to_constr, constr_name)
                # -1 is a special value that means this string does not map to
                # a unique constraint name.
                model.name_to_constr[constr_name] = -1
            else
                model.name_to_constr[constr_name] = constr
            end
        end
    end
    index = get(model.name_to_constr, name, nothing)
    if index isa Nothing
        return nothing
    elseif index == -1
        error("Multiple constraints have the name $name.")
    else
        return _make_constraint_ref(model, index)
    end
end

"""
    JuMP.num_constraints(model::InfiniteModel,
                         function_type::Type{<:JuMP.AbstractJuMPScalar},
                         set_type::Type{<:MOI.AbstractSet})::Int

Extend [`JuMP.num_constraints`](@ref JuMP.num_constraints(::JuMP.Model, ::Type{<:Union{JuMP.AbstractJuMPScalar, Vector{<:JuMP.AbstractJuMPScalar}}}, ::Type{<:MOI.AbstractSet}))
to return the number of constraints
with a partiuclar function type and set type.

**Example**
```julia-repl
julia> num_constraints(model, HoldVariableRef, MOI.LessThan)
1
```
"""
function JuMP.num_constraints(model::InfiniteModel,
                              function_type::Type{<:JuMP.AbstractJuMPScalar},
                              set_type::Type{<:MOI.AbstractSet})::Int
    counter = 0
    for (index, constr) in model.constrs
        if isa(constr.func, function_type) && isa(constr.set, set_type)
            counter += 1
        end
    end
    return counter
end

"""
    JuMP.num_constraints(model::InfiniteModel,
                         function_type::Type{<:JuMP.AbstractJuMPScalar})::Int

Extend [`JuMP.num_constraints`](@ref JuMP.num_constraints(::JuMP.Model, ::Type{<:Union{JuMP.AbstractJuMPScalar, Vector{<:JuMP.AbstractJuMPScalar}}}, ::Type{<:MOI.AbstractSet}))
to search by function types for all MOI
sets and return the total number of constraints with a particular function type.

```julia-repl
julia> num_constraints(model, HoldVariableRef)
3
```
"""
function JuMP.num_constraints(model::InfiniteModel,
                            function_type::Type{<:JuMP.AbstractJuMPScalar})::Int
    return JuMP.num_constraints(model, function_type, MOI.AbstractSet)
end

"""
    JuMP.num_constraints(model::InfiniteModel,
                         function_type::Type{<:MOI.AbstractSet})::Int

Extend [`JuMP.num_constraints`](@ref JuMP.num_constraints(::JuMP.Model, ::Type{<:Union{JuMP.AbstractJuMPScalar, Vector{<:JuMP.AbstractJuMPScalar}}}, ::Type{<:MOI.AbstractSet}))
to search by MOI set type for all function
types and return the total number of constraints that use a particular MOI set
type.

```julia-repl
julia> num_constraints(model, MOI.LessThan)
2
```
"""
function JuMP.num_constraints(model::InfiniteModel,
                              set_type::Type{<:MOI.AbstractSet})::Int
    return JuMP.num_constraints(model, JuMP.AbstractJuMPScalar, set_type)
end

"""
    JuMP.num_constraints(model::InfiniteModel)::Int

Extend [`JuMP.num_constraints`](@ref JuMP.num_constraints(::JuMP.Model, ::Type{<:Union{JuMP.AbstractJuMPScalar, Vector{<:JuMP.AbstractJuMPScalar}}}, ::Type{<:MOI.AbstractSet}))
to return the total number of constraints
in an infinite model `model`.

```julia-repl
julia> num_constraints(model)
4
```
"""
function JuMP.num_constraints(model::InfiniteModel)::Int
    return length(model.constrs)
end

"""
    JuMP.all_constraints(model::InfiniteModel,
                         function_type::Type{<:JuMP.AbstractJuMPScalar},
                         set_type::Type{<:MOI.AbstractSet}
                         )::Vector{<:GeneralConstraintRef}

Extend [`JuMP.all_constraints`](@ref JuMP.all_constraints(::JuMP.Model, ::Type{<:Union{JuMP.AbstractJuMPScalar, Vector{<:JuMP.AbstractJuMPScalar}}}, ::Type{<:MOI.AbstractSet}))
to return a list of all the constraints with a particular function type and set type.

```julia-repl
julia> all_constraints(model, HoldVariableRef, MOI.LessThan)
1-element Array{GeneralConstraintRef,1}:
 x ≤ 1.0
```
"""
function JuMP.all_constraints(model::InfiniteModel,
                              function_type::Type{<:JuMP.AbstractJuMPScalar},
                              set_type::Type{<:MOI.AbstractSet}
                              )::Vector{<:GeneralConstraintRef}
    constr_list = Vector{GeneralConstraintRef}(undef,
                           JuMP.num_constraints(model, function_type, set_type))
    indexes = sort(collect(keys(model.constrs)))
    counter = 1
    for index in indexes
        if isa(model.constrs[index].func, function_type) && isa(model.constrs[index].set, set_type)
            constr_list[counter] = _make_constraint_ref(model, index)
            counter += 1
        end
    end
    return constr_list
end

"""
    JuMP.all_constraints(model::InfiniteModel,
                         function_type::Type{<:JuMP.AbstractJuMPScalar}
                         )::Vector{<:GeneralConstraintRef}

Extend [`JuMP.all_constraints`](@ref JuMP.all_constraints(::JuMP.Model, ::Type{<:Union{JuMP.AbstractJuMPScalar, Vector{<:JuMP.AbstractJuMPScalar}}}, ::Type{<:MOI.AbstractSet}))
to search by function types for all MOI
sets and return a list of all constraints use a particular function type.

```julia-repl
julia> all_constraints(model, HoldVariableRef)
3-element Array{GeneralConstraintRef,1}:
 x ≥ 0.0
 x ≤ 3.0
 x integer
```
"""
function JuMP.all_constraints(model::InfiniteModel,
                              function_type::Type{<:JuMP.AbstractJuMPScalar}
                              )::Vector{<:GeneralConstraintRef}
    return JuMP.all_constraints(model, function_type, MOI.AbstractSet)
end

"""
    JuMP.all_constraints(model::InfiniteModel,
                         set_type::Type{<:MOI.AbstractSet}
                         )::Vector{<:GeneralConstraintRef}

Extend [`JuMP.all_constraints`](@ref JuMP.all_constraints(::JuMP.Model, ::Type{<:Union{JuMP.AbstractJuMPScalar, Vector{<:JuMP.AbstractJuMPScalar}}}, ::Type{<:MOI.AbstractSet}))
to search by MOI set type for all function
types and return a list of all constraints that use a particular set type.

```julia-repl
julia> all_constraints(model, MOI.GreaterThan)
3-element Array{GeneralConstraintRef,1}:
 x ≥ 0.0
 g(t) ≥ 0.0
 g(0.5) ≥ 0.0
```
"""
function JuMP.all_constraints(model::InfiniteModel,
                              set_type::Type{<:MOI.AbstractSet}
                              )::Vector{<:GeneralConstraintRef}
    return JuMP.all_constraints(model, JuMP.AbstractJuMPScalar, set_type)
end

"""
    JuMP.all_constraints(model::InfiniteModel)::Vector{<:GeneralConstraintRef}

Extend [`JuMP.all_constraints`](@ref JuMP.all_constraints(::JuMP.Model, ::Type{<:Union{JuMP.AbstractJuMPScalar, Vector{<:JuMP.AbstractJuMPScalar}}}, ::Type{<:MOI.AbstractSet}))
to return all a list of all the constraints
in an infinite model `model`.

```julia-repl
julia> all_constraints(model)
5-element Array{GeneralConstraintRef,1}:
 x ≥ 0.0
 x ≤ 3.0
 x integer
 g(t) ≥ 0.0
 g(0.5) ≥ 0.0
```
"""
function JuMP.all_constraints(model::InfiniteModel)::Vector{<:GeneralConstraintRef}
    return JuMP.all_constraints(model, JuMP.AbstractJuMPScalar, MOI.AbstractSet)
end

"""
    JuMP.list_of_constraint_types(model::InfiniteModel)::Vector{Tuple)

Extend [`JuMP.list_of_constraint_types`](@ref JuMP.list_of_constraint_types(::JuMP.Model))
to return a list of tuples that
contain all the used combinations of function types and set types in the model.

```julia-repl
julia> all_constraints(model)
5-element Array{Tuple{DataType,DataType},1}:
 (HoldVariableRef, MathOptInterface.LessThan{Float64})
 (PointVariableRef, MathOptInterface.GreaterThan{Float64})
 (HoldVariableRef, MathOptInterface.GreaterThan{Float64})
 (HoldVariableRef, MathOptInterface.Integer)
 (InfiniteVariableRef, MathOptInterface.GreaterThan{Float64})
```
"""
function JuMP.list_of_constraint_types(model::InfiniteModel)::Vector{Tuple}
    type_list = Vector{Tuple{DataType, DataType}}(undef,
                                                  JuMP.num_constraints(model))
    indexes = sort(collect(keys(model.constrs)))
    counter = 1
    for index in indexes
        type_list[counter] = (typeof(model.constrs[index].func),
                              typeof(model.constrs[index].set))
        counter += 1
    end
    return unique(type_list)
end
