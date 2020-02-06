#=
Copyright 2020, Chris Coey, Lea Kapelevich and contributors

for variables X in R^{n, m} and Y in S^n:
    max tr(C*X) :
    Y - X*X' in S^n_+
    Y_ij = P_ij for (i, j) in Omega
where Omega is a set of fixed indices and P is a random PSD matrix

the nonlinear constraint Y - X*X' in S^n_+ is equivalent to
the conic constraint (Y, 0.5, X) in MatrixEpiPerSquareCone(),
and also to the larger conic constraint [I X'; X Y] in S^{n + m}_+
(see Lecture 4 of "Lectures on Convex Optimization" (2018) by Y. Nesterov)
=#

import JuMP
import MathOptInterface
const MOI = MathOptInterface
import Hypatia
CO = Hypatia.Cones
import Random
using LinearAlgebra
using SparseArrays
using Test

function matrixquadraticJuMP(
    W_rows::Int,
    W_cols::Int;
    use_matrixepipersquare::Bool = true,
    )
    C = randn(W_cols, W_rows)
    P = randn(W_rows, W_rows)
    P = Symmetric(P * P')
    (row_idxs, col_idxs, _) = findnz(tril!(sprand(Bool, W_rows, W_rows, inv(sqrt(W_rows)))) + I)

    model = JuMP.Model()
    JuMP.@variable(model, X[1:W_rows, 1:W_cols])
    JuMP.@variable(model, Y[1:W_rows, 1:W_rows], Symmetric)
    JuMP.@objective(model, Max, tr(C * X))
    JuMP.@constraint(model, [(row, col) in zip(row_idxs, col_idxs)], Y[row, col] == P[row, col])

    if use_matrixepipersquare
        U_svec = zeros(JuMP.GenericAffExpr{Float64, JuMP.VariableRef}, CO.svec_length(W_rows))
        U_svec = CO.smat_to_svec!(U_svec, 1.0 * Y, sqrt(2))
        JuMP.@constraint(model, vcat(U_svec, 0.5, vec(X)) in Hypatia.MatrixEpiPerSquareCone{Float64, Float64}(W_rows, W_cols))
    else
        JuMP.@constraint(model, Symmetric([Matrix(I, W_cols, W_cols) X'; X Y]) in JuMP.PSDCone())
    end

    return (model = model,)
end

matrixquadraticJuMP1() = matrixquadraticJuMP(5, 6, use_matrixepipersquare = true)
matrixquadraticJuMP2() = matrixquadraticJuMP(5, 6, use_matrixepipersquare = false)
matrixquadraticJuMP3() = matrixquadraticJuMP(10, 20, use_matrixepipersquare = true)
matrixquadraticJuMP4() = matrixquadraticJuMP(10, 20, use_matrixepipersquare = false)
matrixquadraticJuMP5() = matrixquadraticJuMP(25, 30, use_matrixepipersquare = true)
matrixquadraticJuMP6() = matrixquadraticJuMP(25, 30, use_matrixepipersquare = false)

function test_matrixquadraticJuMP(instance::Function; options, rseed::Int = 1)
    Random.seed!(rseed)
    d = instance()
    JuMP.set_optimizer(d.model, () -> Hypatia.Optimizer(; options...))
    JuMP.optimize!(d.model)
    @test JuMP.termination_status(d.model) == MOI.OPTIMAL
    return
end

test_matrixquadraticJuMP_all(; options...) = test_matrixquadraticJuMP.([
    matrixquadraticJuMP1,
    matrixquadraticJuMP2,
    matrixquadraticJuMP3,
    matrixquadraticJuMP4,
    matrixquadraticJuMP5,
    matrixquadraticJuMP6,
    ], options = options)

test_matrixquadraticJuMP(; options...) = test_matrixquadraticJuMP.([
    matrixquadraticJuMP1,
    matrixquadraticJuMP2,
    matrixquadraticJuMP3,
    matrixquadraticJuMP4,
    ], options = options)