


# for exp cone barrier
# TODO combine Hi * g into one
function newton_dir(point, dual_point) where {T <: Real}
    (u, v, w) = point

    lwv = log(w / v)
    vlwv = v * lwv
    vlwvu = vlwv - u
    denom = vlwvu + 2 * v
    wvdenom = w * v / denom
    vvdenom = (vlwvu + v) / denom

    g = -dual_point
    g[1] -= inv(vlwvu)
    g[2] += (lwv - 1) / vlwvu + inv(v)
    g[3] += (1 + v / vlwvu) / w

    Hi = similar(point, 3, 3)
    Hi[1, 1] = 2 * (abs2(vlwv - v) + vlwv * (v - u)) + abs2(u) - v / denom * abs2(vlwv - 2 * v)
    Hi[1, 2] = (abs2(vlwv) + u * (v - vlwv)) / denom * v
    Hi[1, 3] = wvdenom * (2 * vlwv - u)
    Hi[2, 2] = v * vvdenom * v
    Hi[2, 3] = wvdenom * v
    Hi[3, 3] = w * vvdenom * w
    Hi = Symmetric(Hi, :U)

    newton_dir = Hi * g

    return (g, newton_dir)
end



function update_dual_grad(cone::Cone{T}) where {T <: Real}
    @assert cone.is_feas
    point = cone.point
    dual_point = cone.dual_point
    curr = cone.dual_grad

    max_iter = 200 # TODO reduce: shouldn't really take > 40
    eta = eps(T) / 10 # TODO adjust

    # damped Newton
    curr .= point
    iter = 0
    while true
        (gr, dir) = newton_dir(curr, dual_point)
        nnorm = dot(gr, dir)
        denom = 1 + nnorm
        @. curr += dir / denom
        iter += 1
        if nnorm < eta || iter >= max_iter
            break
        end
    end

    # # TODO remove check
    # if norm(ForwardDiff.gradient(cone.barrier, curr) + cone.dual_point) > sqrt(eps(T))
    #     @warn("conjugate grad calculation inaccurate")
    # end

    curr .*= -1

    cone.dual_grad_updated = true
    return cone.dual_grad
end



# function newton_step(cone::Cone)
#     mock_cone = cone.newton_cone
#     reset_data(mock_cone)
#     load_point(mock_cone, cone.newton_point)
#     @assert update_feas(mock_cone)
#     g = grad(mock_cone)
#     @. cone.newton_grad = -g - cone.dual_point
#     inv_hess_prod!(cone.newton_stepdir, cone.newton_grad, mock_cone)
#     cone.newton_norm = dot(cone.newton_grad, cone.newton_stepdir)
#     return
# end

# function update_dual_grad(cone::Cone{T}) where {T <: Real}
#     @assert cone.is_feas
#
#     max_iter = 200 # TODO reduce: shouldn't really take > 40
#     eta = eps(T) / 10 # TODO adjust
#     # initial iterate
#     copyto!(cone.newton_point, cone.point)
#     newton_step(cone)
#     # damped Newton
#     iter = 0
#     while cone.newton_norm > eta
#         @. cone.newton_point += cone.newton_stepdir / (1 + cone.newton_norm)
#         newton_step(cone)
#         iter += 1
#         # iter > max_iter && @warn("iteration limit in Newton method")
#     end
#
#     # can avoid a field unless we want to use switched Newton later
#     @. cone.dual_grad = -cone.newton_point
#     cone.dual_grad_updated = true
#
#     # TODO remove check
#     if norm(ForwardDiff.gradient(cone.barrier, cone.newton_point) + cone.dual_point) > sqrt(eps(T))
#         @warn("conjugate grad calculation inaccurate")
#     end
#
#     return cone.dual_grad
# end