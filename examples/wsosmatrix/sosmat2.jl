#=
Copyright 2018, Chris Coey, Lea Kapelevich and contributors

example modified from https://github.com/JuliaOpt/SumOfSquares.jl/blob/master/test/choi.jl
verifies that a given polynomial matrix is not a Sum-of-Squares matrix
see Choi, M. D., "Positive semidefinite biquadratic forms",
Linear Algebra and its Applications, 1975, 12(2), 95-100
=#

import Hypatia
const HYP = Hypatia
const CO = HYP.Cones
const MU = HYP.ModelUtilities

import MathOptInterface
const MOI = MathOptInterface
import JuMP
import MultivariatePolynomials
import DynamicPolynomials
import SumOfSquares
import PolyJuMP
using Test
import Random

const rt2 = sqrt(2)

function run_JuMP_sosmat2(use_matrixwsos::Bool, use_dual::Bool)
    Random.seed!(1)

    DynamicPolynomials.@polyvar x y z
    C = [
        (x^2 + 2y^2) (-x * y) (-x * z);
        (-x * y) (y^2 + 2z^2) (-y * z);
        (-x * z) (-y * z) (z^2 + 2x^2);
        ] .* (x * y * z)^0
    dom = MU.FreeDomain(3)
    d = div(maximum(DynamicPolynomials.maxdegree.(C)) + 1, 2)

    model = JuMP.Model(JuMP.with_optimizer(HYP.Optimizer, verbose = true))

    if use_matrixwsos
        (U, pts, P0, _, _) = MU.interpolate(dom, d, sample = false)
        mat_wsos_cone = HYP.WSOSPolyInterpMatCone(3, U, [P0], use_dual)
        if use_dual
            JuMP.@variable(model, z[i in 1:3, 1:i, 1:U])
            JuMP.@constraint(model, [z[i, j, u] * (i == j ? 1.0 : rt2) for i in 1:3 for j in 1:i for u in 1:U] in mat_wsos_cone)
            JuMP.@objective(model, Min, sum(z[i, j, u] * C[i, j](pts[u, :]...) * (i == j ? 1.0 : 2.0) for i in 1:3 for j in 1:i for u in 1:U))
        else
            JuMP.@constraint(model, [C[i, j](pts[u, :]) * (i == j ? 1.0 : rt2) for i in 1:3 for j in 1:i for u in 1:U] in mat_wsos_cone)
        end
    else
        if use_dual
            error("dual formulation not implemented for scalar SOS formulation")
        end
        dom2 = MU.add_free_vars(dom)
        (U, pts, P0, _, _) = MU.interpolate(dom2, d + 2, sample_factor = 20, sample = true)
        scalar_wsos_cone = HYP.WSOSPolyInterpCone(U, [P0])
        DynamicPolynomials.@polyvar w[1:3]
        wCw = w' * C * w
        JuMP.@constraint(model, [wCw(pts[u, :]) for u in 1:U] in scalar_wsos_cone)
    end

    JuMP.optimize!(model)
    if use_dual
        @test JuMP.termination_status(model) == MOI.DUAL_INFEASIBLE
        @test JuMP.primal_status(model) == MOI.INFEASIBILITY_CERTIFICATE
    else
        @test JuMP.termination_status(model) == MOI.INFEASIBLE
        @test JuMP.dual_status(model) == MOI.INFEASIBILITY_CERTIFICATE
    end
end

run_JuMP_sosmat2_scalar() = run_JuMP_sosmat2(false, false)
run_JuMP_sosmat2_matrix() = run_JuMP_sosmat2(true, false)
run_JuMP_sosmat2_matrix_dual() = run_JuMP_sosmat2(true, true)