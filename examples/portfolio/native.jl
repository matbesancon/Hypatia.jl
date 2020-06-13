#=
Copyright 2019, Chris Coey, Lea Kapelevich and contributors

maximize expected returns subject to risk constraints

TODO
- add entropic ball constraint using entropy cone (and optional extended formulation)
- describe formulation and options
=#

include(joinpath(@__DIR__, "../common_native.jl"))

struct PortfolioNative{T <: Real} <: ExampleInstanceNative{T}
    num_stocks::Int
    epinormeucl_constr::Bool # add L2 ball constraints, else don't add
    epinorminf_constrs::Bool # add Linfty ball constraints, else don't add
    use_epinorminf::Bool # use epinorminf cone, else nonnegative cones
    use_linops::Bool
end

example_tests(::Type{<:PortfolioNative{<:Real}}, ::MinimalInstances) = [
    ((3, true, false, true, false),),
    ((3, false, true, true, false),),
    ((3, false, true, false, false),),
    ((3, true, true, true, false),),
    ]
example_tests(::Type{PortfolioNative{Float64}}, ::FastInstances) = [
    # ((10, true, false, true, false),),
    ((10, false, true, true, false),),
    ((10, false, true, false, false),),
    # ((10, true, true, true, false),),
    # ((50, true, false, true, false),),
    ((50, false, true, true, false),),
    # ((50, false, true, false, false),),
    # ((50, true, true, true, false),),
    # ((400, true, false, true, false),),
    ((400, false, true, true, false),),
    # ((400, false, true, false, false),),
    # ((400, true, true, true, false),),
    ]
example_tests(::Type{PortfolioNative{Float64}}, ::SlowInstances) = [
    ((3000, true, false, true, false),),
    ((3000, false, true, true, false),),
    ((3000, false, true, false, false),),
    ((3000, true, true, true, false),),
    ]
example_tests(::Type{PortfolioNative{Float64}}, ::LinearOperatorsInstances) = [
    ((20, true, false, true, true),),
    ((20, false, true, true, true),),
    ((20, false, true, false, true),),
    ((20, true, true, true, true),),
    ]

function build(inst::PortfolioNative{T}) where {T <: Real}
    num_stocks = inst.num_stocks
    returns = rand(T, num_stocks)
    sigma_half = T.(randn(num_stocks, num_stocks))
    x = T.(randn(num_stocks))
    x ./= norm(x)
    gamma = sum(abs, sigma_half * x) / sqrt(T(num_stocks))

    c = -returns
    # investments add to one, nonnegativity
    if inst.use_linops
        A_blocks = Any[ones(T, 1, num_stocks)]
        A_rows = [1:1]
        A_cols = [1:num_stocks]
        G_blocks = Any[-I]
        G_rows = [1:num_stocks]
        G_cols = [1:num_stocks]
    else
        A = ones(T, 1, num_stocks)
        G = Matrix{T}(-I, num_stocks, num_stocks)
    end
    b = T[1]
    h = zeros(T, num_stocks)
    cones = Cones.Cone{T}[Cones.Nonnegative{T}(num_stocks)]
    cone_offset = num_stocks

    function add_ball_constr(cone, gamma_new)
        if inst.use_linops
            push!(G_blocks, -sigma_half)
            push!(G_rows, (cone_offset + 2):(cone_offset + num_stocks + 1))
            push!(G_cols, 1:num_stocks)
        else
            G = vcat(G, zeros(T, 1, num_stocks), -sigma_half)
        end
        h_risk = vcat(gamma_new, zeros(T, num_stocks))
        h = vcat(h, h_risk)
        push!(cones, cone)
        cone_offset += num_stocks + 1
    end

    last_idx(a::Vector{UnitRange{Int}}) = a[end][end]

    if inst.epinormeucl_constr
        add_ball_constr(Cones.EpiNormEucl{T}(num_stocks + 1), gamma)
    end

    if inst.epinorminf_constrs
        if inst.use_epinorminf
            add_ball_constr(Cones.EpiNormInf{T, T}(num_stocks + 1, use_dual = true), gamma * sqrt(T(num_stocks)))
            add_ball_constr(Cones.EpiNormInf{T, T}(num_stocks + 1), gamma)
        else
            c = vcat(c, zeros(T, 2 * num_stocks))
            if inst.use_linops
                push!(A_blocks, sigma_half)
                push!(A_blocks, -I)
                push!(A_blocks, I)

                A_offset = last_idx(A_rows)
                append!(A_rows, fill((A_offset + 1):(A_offset + num_stocks), 3))

                push!(A_cols, 1:num_stocks)
                push!(A_cols, (num_stocks + 1):(2 * num_stocks))
                push!(A_cols, (2 * num_stocks + 1):(3 * num_stocks))

                push!(G_blocks, -I)
                push!(G_blocks, ones(T, 1, 2 * num_stocks))
                push!(G_rows, (last_idx(G_rows) + 1):(last_idx(G_rows) + 2 * num_stocks))
                push!(G_rows, (last_idx(G_rows) + 1):(last_idx(G_rows) + 1))
                # must have `num_stocks` primal variables, append columns
                push!(G_cols, (num_stocks + 1):(3 * num_stocks))
                push!(G_cols, (num_stocks + 1):(3 * num_stocks))
            else
                id = Matrix{T}(I, num_stocks, num_stocks)
                id2 = Matrix{T}(I, 2 * num_stocks, 2 * num_stocks)
                A = [
                    A    zeros(T, 1, 2 * num_stocks);
                    sigma_half    -id    id;
                    ]
                G = [
                    G    zeros(T, size(G, 1), 2 * num_stocks);
                    zeros(T, 2 * num_stocks, num_stocks)    -id2;
                    zeros(T, 1, num_stocks)    ones(T, 1, 2 * num_stocks);
                    ]
            end
            b = vcat(b, zeros(T, num_stocks))
            h = vcat(h, zeros(T, 2 * num_stocks), gamma * sqrt(T(num_stocks)))
            push!(cones, Cones.Nonnegative{T}(2 * num_stocks + 1))
            cone_offset += 2 * num_stocks + 1

            if inst.use_linops
                push!(G_blocks, sigma_half)
                push!(G_blocks, -sigma_half)
                push!(G_rows, (cone_offset + 1):(cone_offset + num_stocks))
                push!(G_rows, (cone_offset + num_stocks + 1):(cone_offset + 2 * num_stocks))
                push!(G_cols, 1:num_stocks)
                push!(G_cols, 1:num_stocks)
            else
                padding = zeros(T, num_stocks, size(G, 2) - num_stocks)
                G = [
                    G;
                    sigma_half    padding;
                    -sigma_half    padding;
                    ]
            end
            h = vcat(h, gamma * ones(T, 2 * num_stocks))
            push!(cones, Cones.Nonnegative{T}(2 * num_stocks))
            cone_offset += 2 * num_stocks
        end
    end

    if inst.use_linops
        A = Hypatia.BlockMatrix{T}(last_idx(A_rows), last_idx(A_cols), A_blocks, A_rows, A_cols)
        G = Hypatia.BlockMatrix{T}(last_idx(G_rows), last_idx(G_cols), G_blocks, G_rows, G_cols)
    end

    model = Models.Model{T}(c, A, b, G, h, cones)
    return model
end

return PortfolioNative
