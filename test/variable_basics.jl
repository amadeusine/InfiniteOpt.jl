# Test extensions to basic Base methods
@testset "Base Extensions" begin
    # initialize models and references
    m = InfiniteModel()
    m2 = InfiniteModel()
    ivref = InfiniteVariableRef(m, 1)
    pvref = PointVariableRef(m, 2)
    hvref = HoldVariableRef(m, 3)
    pref = ParameterRef(m, 1)
    # variable compare
    @testset "(==)" begin
        @test ivref == ivref
        @test pvref == pvref
        @test hvref == hvref
        @test ivref == InfiniteVariableRef(m, 1)
        @test pvref == PointVariableRef(m, 2)
        @test hvref == HoldVariableRef(m, 3)
        @test !(ivref == InfiniteVariableRef(m, 2))
        @test !(ivref == InfiniteVariableRef(m2, 1))
        @test !(ivref != InfiniteVariableRef(m, 1))
        @test !(pref == ivref)
    end
    # copy(v)
    @testset "copy(v)" begin
        @test copy(ivref) == ivref
        @test copy(pvref) == pvref
        @test copy(hvref) == hvref
    end
    # copy(v, m)
    @testset "copy(v, m)" begin
        @test copy(ivref, m2) == InfiniteVariableRef(m2, 1)
        @test copy(pvref, m2) == PointVariableRef(m2, 2)
        @test copy(hvref, m2) == HoldVariableRef(m2, 3)
    end
    # broadcastable
    @testset "broadcastable" begin
        @test isa(Base.broadcastable(ivref), Base.RefValue{InfiniteVariableRef})
        @test isa(Base.broadcastable(pvref), Base.RefValue{PointVariableRef})
        @test isa(Base.broadcastable(hvref), Base.RefValue{HoldVariableRef})
    end
    # length
    @testset "length" begin
        @test length(ivref) == 1
        @test length(pvref) == 1
        @test length(hvref) == 1
    end
end

# Test core JuMP methods
@testset "Core JuMP Extensions" begin
    # initialize models and references
    m = InfiniteModel()
    m2 = InfiniteModel()
    ivref = InfiniteVariableRef(m, 1)
    pvref = PointVariableRef(m, 2)
    hvref = HoldVariableRef(m, 3)
    pref = ParameterRef(m, 1)
    # isequal_canonical
    @testset "JuMP.isequal_canonical" begin
        @test isequal_canonical(ivref, ivref)
        @test isequal_canonical(pvref, pvref)
        @test isequal_canonical(hvref, hvref)
        @test !isequal_canonical(ivref, InfiniteVariableRef(m2, 1))
        @test !isequal_canonical(ivref, InfiniteVariableRef(m, 2))
    end
    # variable_type(m)
    @testset "JuMP.variable_type(m)" begin
        @test variable_type(m) == GeneralVariableRef
    end
    # variable_type(m, t)
    @testset "JuMP.variable_type(m, t)" begin
        @test variable_type(m, Infinite) == InfiniteVariableRef
        @test variable_type(m, Point) == PointVariableRef
        @test variable_type(m, Hold) == HoldVariableRef
        @test variable_type(m, Parameter) == ParameterRef
        @test_throws ErrorException variable_type(m, :bad)
    end
end

# Test precursor functions needed for add_parameter
@testset "Basic Reference Queries" begin
    # initialize model and infinite variable
    m = InfiniteModel()
    ivref = InfiniteVariableRef(m, 1)
    info = VariableInfo(false, 0, false, 0, false, 0, false, 0, false, false)
    param = InfOptParameter(IntervalSet(0, 1), Number[], false)
    pref = add_parameter(m, param, "test")
    m.vars[1] = InfiniteVariable(info, VectorTuple(pref))
    # JuMP.index
    @testset "JuMP.index" begin
        @test JuMP.index(ivref) == 1
    end
    # JuMP.owner_model
    @testset "JuMP.owner_model" begin
        @test owner_model(ivref) == m
    end
    # JuMP.is_valid
    @testset "JuMP.is_valid" begin
        @test is_valid(m, ivref)
        @test !is_valid(InfiniteModel(), ivref)
        @test !is_valid(m, InfiniteVariableRef(m, 5))
    end
end
