#=
Copyright 2018, Chris Coey, Lea Kapelevich and contributors

see description in native.jl
=#

include(joinpath(@__DIR__, "../common_JuMP.jl"))
import DelimitedFiles
import DynamicPolynomials
import PolyJuMP

struct DensityEstJuMP{T <: Real} <: ExampleInstanceJuMP{T}
    dataset_name::Symbol
    X::Matrix{T}
    deg::Int
    use_wsos::Bool # use WSOS cone formulation, else PSD formulation
end
function DensityEstJuMP{Float64}(
    dataset_name::Symbol,
    deg::Int,
    use_wsos::Bool)
    if dataset_name == :Uniform
        X = (rand(num_obs, n) .- 0.5) .* 2
    else
        X = DelimitedFiles.readdlm(joinpath(@__DIR__, "data", "$dataset_name.txt"))
    end
    return DensityEstJuMP{Float64}(dataset_name, X, deg, use_wsos)
end
function DensityEstJuMP{Float64}(
    num_obs::Int,
    n::Int,
    args...)
    X = randn(num_obs, n)
    return DensityEstJuMP{Float64}(:Random, X, args...)
end

example_tests(::Type{DensityEstJuMP{Float64}}, ::MinimalInstances) = [
    ((5, 1, 2, true),),
    ((:iris, 2, true),),
    ((:Uniform, 2, true), nothing, options),
    ((:Uniform, 2, false), nothing, options),
    ]
example_tests(::Type{DensityEstJuMP{Float64}}, ::FastInstances) = begin
    options = (tol_feas = 1e-7, tol_rel_opt = 1e-6, tol_abs_opt = 1e-6)
    return [
    # ((100, 1, 5, true), nothing, options),
    # ((100, 1, 10, true), nothing, options),
    # ((100, 1, 20, true), nothing, options),
    # ((100, 1, 50, true), nothing, options),
    # ((100, 1, 100, true), nothing, options),
    # ((100, 1, 200, true), nothing, options),
    # ((100, 1, 500, true), nothing, options),
    ((100, 2, 5, true), nothing, options),
    ((100, 2, 10, true), nothing, options),
    ((100, 2, 20, true), nothing, options),
    # ((50, 3, 2, true), nothing, options),
    # ((50, 3, 4, true), nothing, options),
    # ((50, 4, 2, true), nothing, options),
    # ((100, 8, 2, true), nothing, options),
    # ((100, 8, 2, false), nothing, options),
    # ((250, 4, 4, true), nothing, options),
    # ((250, 4, 4, false), nothing, options),
    # ((:iris, 4, true), nothing, options),
    # ((:iris, 5, true), nothing, options),
    # ((:iris, 6, true), nothing, options),
    # ((:iris, 4, false), nothing, options),
    # ((:cancer, 4, true), nothing, options),
    ]
end
example_tests(::Type{DensityEstJuMP{Float64}}, ::SlowInstances) = begin
    options = (tol_feas = 1e-7, tol_rel_opt = 1e-6, tol_abs_opt = 1e-6)
    return [
    ((100, 2, 50, true), nothing, options),
    ((100, 2, 70, true), nothing, options),
    # ((200, 4, 4, false), nothing, options),
    # ((200, 4, 6, true), nothing, options),
    # ((200, 4, 6, false), nothing, options),
    ]
end

function build(inst::DensityEstJuMP{T}) where {T <: Float64} # TODO generic reals
    X = inst.X
    (num_obs, n) = size(X)
    domain = ModelUtilities.Box{Float64}(-ones(n), ones(n)) # domain is unit box [-1,1]^n

    # rescale X to be in unit box
    minX = minimum(X, dims = 1)
    maxX = maximum(X, dims = 1)
    X .-= (minX + maxX) / 2
    X ./= (maxX - minX) / 2

    # setup interpolation
    halfdeg = div(inst.deg + 1, 2)
    (U, _, Ps, V, w) = ModelUtilities.interpolate(domain, halfdeg, calc_V = true, calc_w = true) # return F parts for qr(V') instead??
    # TODO maybe incorporate this interp-basis transform into MU, and do something smarter for uni/bi-variate
    F = qr!(Array(V'), Val(true)) # TODO reuse QR parts
    V_X = ModelUtilities.make_chebyshev_vandermonde(X, halfdeg)
    X_pts_polys = F \ V_X'

    model = JuMP.Model()
    JuMP.@variable(model, z)
    JuMP.@objective(model, Max, z)
    JuMP.@variable(model, f_pts[1:U])

    # objective epigraph
    JuMP.@constraint(model, vcat(z, X_pts_polys' * f_pts) in MOI.GeometricMeanCone(1 + num_obs))

    # density integrates to 1
    JuMP.@constraint(model, dot(w, f_pts) == 1)

    # density nonnegative
    if inst.use_wsos
        # WSOS formulation
        JuMP.@constraint(model, f_pts in Hypatia.WSOSInterpNonnegativeCone{Float64, Float64}(U, Ps))
    else
        # PSD formulation
        psd_vars = []
        for (r, Pr) in enumerate(Ps)
            Lr = size(Pr, 2)
            psd_r = JuMP.@variable(model, [1:Lr, 1:Lr], Symmetric)
            push!(psd_vars, psd_r)
            JuMP.@SDconstraint(model, psd_r >= 0)
        end
        coeffs_lhs = JuMP.@expression(model, [u in 1:U], sum(sum(Pr[u, k] * Pr[u, l] * psd_r[k, l] * (k == l ? 1 : 2) for k in 1:size(Pr, 2) for l in 1:k) for (Pr, psd_r) in zip(Ps, psd_vars)))
        JuMP.@constraint(model, coeffs_lhs .== f_pts)
    end

    return model
end

function test_extra(inst::DensityEstJuMP{T}, model::JuMP.Model) where T
    @test JuMP.termination_status(model) == MOI.OPTIMAL
    if JuMP.termination_status(model) == MOI.OPTIMAL && inst.dataset_name == :Uniform
        error("TODO: finish this and add instances")
        # check objective value is correct
        tol = eps(T)^0.25
        @test JuMP.objective_value(model) ≈ 1 atol = tol rtol = tol
    end
end

return DensityEstJuMP
