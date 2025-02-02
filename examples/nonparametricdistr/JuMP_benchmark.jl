
nonparametricdistr_insts(ext::VecSpecExt) = [
    [(d, ext)
    for d in vcat(10, 500, 1000, 2500, 5000:5000:25000)] # includes compile run
    ]

insts = OrderedDict()
insts["nat"] = (nothing, vcat(
    nonparametricdistr_insts(VecNegGeom()),
    nonparametricdistr_insts(VecNegLog()),
    nonparametricdistr_insts(VecNegEntropy()),
    ))
insts["vecext"] = (nothing, vcat(
    nonparametricdistr_insts(VecNegGeomEFExp()),
    nonparametricdistr_insts(VecNegLogEF()),
    nonparametricdistr_insts(VecNegEntropyEF()),
    ))
return (NonparametricDistrJuMP, insts)
