using Statistics
using ThreadsX
using Statistics
using LinearAlgebra

"""
The `UpdateRule` abstract type defines mechanisms to update the best composition estimate between
iteration steps.
"""
abstract type UpdateRule end

"""
The `NaiveUpdateRule` implements the 'method of successive approximations' to update
the composition between iteration steps.
"""
struct NaiveUpdateRule <: UpdateRule end

"""
    update(
        ::NaiveUpdateRule,
        prevcomp::Material,
        measured::Vector{KRatio},
        zafs::Dict{Element, Float64}
    )::Dict{Element, Float64}

Determine the next estimate of the composition that brings the estimate k-ratios closer to measured.
"""
function update(
    ::NaiveUpdateRule, #
    prevcomp::Material, #
    measured::Vector{KRatio}, #
    zafs::Dict{Element,Float64},
    state::Union{Nothing,Tuple} #
)::Tuple
    cnp1 = Dict(kr.element => value(nonnegk(kr)) * value(kr.standard[kr.element]) / zafs[kr.element] for kr in measured)
    return (cnp1, nothing)

end

"""
The `WegsteinUpdateRule` implements the very effective method of Reed and Mason (S.J.B. Reed and P.K. Mason,
Transactions ofthe Second National Conference on Electron Microprobe Analysis, Boston, 1967.) for updating
the composition estimate between iteration steps.
"""
struct WegsteinUpdateRule <: UpdateRule end

function update( #
    ::WegsteinUpdateRule,
    prevcomp::Material,
    measured::Vector{KRatio},
    zafs::Dict{Element,Float64},
    state::Union{Nothing,Tuple}
)::Tuple
    cnp1 = Dict(kr.element => value(nonnegk(kr)) * value(kr.standard[kr.element]) / zafs[kr.element] for kr in measured)
    fn = Dict(kr.element => value(kr.standard[kr.element]) / zafs[kr.element] for kr in measured)
    if !isnothing(state)
        cn = prevcomp
        cnm1, fnm1 = state
        for mkr in measured
            elm, km = mkr.element, value(nonnegk(mkr))
            if km > 0
                δfδc = (fn[elm] - fnm1[elm]) / (value(cn[elm]) - value(cnm1[elm]))
                den = 1.0 - km * δfδc
                if (abs(δfδc) < 10.0) && (abs(den) > 0.2)
                    Δc = (km * fn[elm] - cn[elm]) / den # Wegstein
                    cnp1[elm] = cn[elm] + Δc
                end
            end
        end
    end
    return (cnp1, (prevcomp, fn))
end

"""
The `ConvergenceTest` abstract type represents mechanisms to decide when the iteration has converged.

    converged(ct::ConvergenceTest, meas::Vector{KRatio}, computed::Dict{Element,<:AbstractFloat})::Bool
"""
abstract type ConvergenceTest end

"""
The `RMSBelowTolerance` `ConvergenceTest` ensures that the root-mean-squared difference between
measured and computed is below a threshold.
"""
struct RMSBelowTolerance <: ConvergenceTest
    tolerance::Float64
end

converged(rbt::RMSBelowTolerance, meas::Vector{KRatio}, computed::Dict{Element,<:AbstractFloat})::Bool =
    sum((value(nonnegk(kr)) - computed[kr.element])^2 for kr in meas) < rbt.tolerance^2

"""
The `AllBelowTolerance` `ConvergenceTest` ensures that the difference between
measured and computed is below a threshold for each k-ratio.
"""
struct AllBelowTolerance <: ConvergenceTest
    tolerance::Float64
end

converged(abt::AllBelowTolerance, meas::Vector{KRatio}, computed::Dict{Element,<:AbstractFloat})::Bool =
    all(abs(value(nonnegk(kr)) - computed[kr.element]) < abt.tolerance for kr in meas)


"""
The `IsApproximate` `ConvergenceTest` checks that the k-ratio differences are either below an absolute threshold
or a relative tolerance.
"""
struct IsApproximate <: ConvergenceTest
    atol::Float64
    rtol::Float64
end

converged(ia::IsApproximate, meas::Vector{KRatio}, computed::Dict{Element,<:AbstractFloat}) = all(
    (abs(1.0 - value(nonnegk(kr)) / computed[kr.element]) < ia.rtol) ||
    (abs(value(nonnegk(kr)) - computed[kr.element]) < ia.atol) for kr in meas
)
"""
    Iteration(;
        mc::Type{<:MatrixCorrection} = XPP,
        fc::Type{<:FluorescenceCorrection} = ReedFluorescence,
        cc::Type{<:CoatingCorrection} = Coating,
        updater = WegsteinUpdateRule(),
        converged = RMSBelowTolerance(0.00001),
        unmeasured = NullUnmeasuredRule(),
    )

Collects the information necessary to define the iteration process including the `MatrixCorrection` and
`FLuorescenceCorrection` algorithms, the iteration `UpdateRule`, the `ConvergenceTest`, and an
`UnmeasuredElementRule`.
"""
struct Iteration
    mctype::Type{<:MatrixCorrection}
    fctype::Type{<:FluorescenceCorrection}
    cctype::Type{<:CoatingCorrection}
    updater::UpdateRule
    converged::ConvergenceTest
    unmeasured::UnmeasuredElementRule

    Iteration(;
        mc::Type{<:MatrixCorrection}=XPP,
        fc::Type{<:FluorescenceCorrection}=ReedFluorescence,
        cc::Type{<:CoatingCorrection}=Coating,
        updater=WegsteinUpdateRule(),
        converged=RMSBelowTolerance(0.00001),
        unmeasured=NullUnmeasuredRule()
    ) = new(mc, fc, cc, updater, converged, unmeasured)
end


"""
`IterationResult` contains the results of the iteration process including a Label identifying the source of
the k-ratios, the resulting Material, the initial and final k-ratios, whether the iteration converged and the
number of steps.  The results can be output using `DataFrame(ir::IterationResult)` (must `import DataFrames`).
"""
struct IterationResult
    label::Label
    comp::Material
    kratios::Vector{KRatio}
    computed::Dict{Element,Float64}
    converged::Bool
    iterations::Int
    iterate::Iteration
end

"""
The source of the k-ratio data as a Label (often a CharXRayLabel).
"""
source(ir::IterationResult)::Label = ir.label


Base.show(io::IO, itres::IterationResult) = print(
    io,
    itres.converged ? "Converged to $(itres.comp) in $(itres.iterations) steps." :
    "Failed to converge in $(itres.iterations) iterations: Best estimate = $(itres.comp).",
)


"""
    NeXLCore.material(itres::IterationResult)::Material
"""
NeXLCore.material(itres::IterationResult) = itres.comp
NeXLCore.material(itress::AbstractVector{IterationResult}) = mean(material.(itress))

_ZAF(iter::Iteration, mat::Material, props::Dict{Symbol,Any}, xrays::Vector{CharXRay}) =
    zafcorrection(iter.mctype, iter.fctype, iter.cctype, convert(Material{Float64,Float64}, mat), xrays, props[:BeamEnergy], get(props, :Coating, missing))

"""
    computeZAFs(
        iter::Iteration,
        mat::Material{Float64, Float64},
        stdZafs::Dict{KRatio,MultiZAF}
    )::Dict{Element, Float64}

Given an estimate of the composition compute the corresponding gZAFc matrix correction.
"""
function computeZAFs(iter::Iteration, est::Material, stdZafs::Dict{<:NeXLCore.KRatioBase,MultiZAF})
    mat = asnormalized(est, 1.0) # This reduces memory usage by a factor of >2 for hyper-spectra
    zaf(kr, zafs) =
        gZAFc(_ZAF(iter, mat, kr.unkProps, kr.xrays), zafs, kr.unkProps[:TakeOffAngle], kr.stdProps[:TakeOffAngle])
    return Dict(kr.element => zaf(kr, zafs) for (kr, zafs) in stdZafs)
end


"""
    estimatecoating(substrate::Material, coating::Material, kcoating::KRatio, mc::Type{<:MatrixCorrection}=XPP)::Film

Use the measured k-ratio to estimate the mass-thickness of the coating material on the specified substrate.
Return the result as a Film which may be assigned to the :Coating property for k-ratios associated with the
substrate.

Assumptions:
  * The coating is the same for all measurements of the unknown
  * The coating element k-ratio is assumed to be assigned to the brightest line
"""
function estimatecoating(substrate::Material, coating::Material, kcoating::Union{KRatio,KRatios}, mc::Type{<:MatrixCorrection}=XPP)::Film
    coatingasfilm(mc, substrate, coating, #
        brightest(kcoating.xrays), kcoating.unkProps[:BeamEnergy], # 
        kcoating.unkProps[:TakeOffAngle], value(kcoating.kratio))
end

"""
    quantify(
        name::Union{String, Label},
        measured::Vector{KRatio}, 
        iteration::Iteration = Iteration(mc=XPP, fc=ReedFluorescence, cc=Coating);
        maxIter::Int = 100, 
        estComp::Union{Nothing,Material}=nothing, 
        coating::Union{Nothing, Pair{CharXRay, <:Material}}=nothing
    )::IterationResult

    quantify(
        measured::AbstractVector{KRatios{T}},
        iteration::Iteration = Iteration(mc=XPP, fc=NullFluorescence, cc=NullCoating);
        kro::KRatioOptimizer = SimpleKRatioOptimizer(1.5),
        maxIter::Int = 100, 
        estComp::Union{Nothing,Material}=nothing, 
        coating::Union{Nothing, Pair{CharXRay, Material}}=nothing
    )

Perform the iteration procedurer as described in `iter` using the `measured` k-ratios to produce the best
estimate `Material` in an `IterationResult` object.  The third form makes it easier to quantify the
k-ratios from filter fit spectra.  `estComp` is an optional first estimate of the composition.  This can
be a useful optimization when quantifying many similar k-ratios (like, for example, points on a 
hyper-spectrum.)

`coating` defines a CharXRay not present in the sample that is used to estimate the thickness of the coating
layer (of the paired `Material`).
"""
function quantify(
    name::Union{Label,String},
    measured::Vector{KRatio},
    iteration::Iteration=Iteration();
    maxIter::Int=100,
    estComp::Union{Nothing,Material}=nothing,
    coating::Union{Nothing,Pair{CharXRay,<:Material}}=nothing
)::IterationResult
    aslbl(lbl::Label) = lbl
    aslbl(lbl) = label(lbl)
    coating = isnothing(coating) ? nothing : (first(coating) => convert(Material{Float64,Float64}, last(coating)))
    lbl = aslbl(name)
    # Compute the C = k*C_std estimate
    firstEstimate(meas::Vector{KRatio}) =
        Dict(kr.element => value(nonnegk(kr)) * value(kr.standard[kr.element]) for kr in meas)
    # Compute the estimated k-ratios
    computeKs(comp, zafs, stdComps) =
        Dict(elm => comp[elm] * zafs[elm] / stdComps[elm] for (elm, zaf) in zafs)
    # Compute uncertainties due to the k-ratio
    function computefinal(comp::Material, meas::Vector{KRatio})
        final = Dict{Element,UncertainValue}(elm => convert(UncertainValue, comp[elm]) for elm in keys(comp))
        for kr in meas
            elm = element(kr)
            final[elm] = if value(final[elm]) > 0.0 && value(kr.kratio) > 0.0
                uv(value(final[elm]), value(final[elm]) * fractional(kr.kratio))
            else
                uv(0.0, σ(kr.kratio))
            end
        end
        return material(NeXLCore.name(comp), final)
    end
    @assert isnothing(coating) || (get(last(coating), :Density, -1.0) > 0.0) "You must provide a positive density for the coating material."
    # Is this k-ratio due to the coating?
    iscoating(k, coatmat) = (!isnothing(coatmat)) && (first(coatmat) in k.xrays) && (element(k) in keys(last(coatmat)))
    # k-ratios from measured elements in the unknown - Remove k-ratios for unmeasured and coating elements
    kunk = filter(measured) do kr
        !(isunmeasured(iteration.unmeasured, element(kr)) || iscoating(kr, coating))
    end
    # k-ratios associated with the coating
    kcoat = filter(kr -> iscoating(kr, coating), measured)
    # Compute the k-ratio difference metric
    eval(computed) = sum((value(nonnegk(kr)) - computed[kr.element])^2 for kr in kunk)
    # Compute the standard matrix correction factors
    stdZafs = Dict(kr => _ZAF(iteration, kr.standard, kr.stdProps, kr.xrays) for kr in kunk)
    stdComps = Dict(kr.element => value(kr.standard[kr.element]) for kr in kunk)
    # First estimate c_unk = k*c_std
    estcomp = convert(Material{Float64,Float64}, something(estComp, material(repr(lbl), compute(iteration.unmeasured, firstEstimate(kunk)))))
    # Compute the associated matrix corrections
    zafs = computeZAFs(iteration, estcomp, stdZafs)
    bestComp, bestKrs = estcomp, computeKs(estcomp, zafs, stdComps)
    bestEval, bestIter, iter_state = 1.0e300, 0, nothing
    for iters in Base.OneTo(maxIter)
        if length(kcoat) >= 1
            coatings = estimatecoating(estcomp, last(coating), first(kcoat), iteration.mctype)
            # Previous coatings are replaced on all the unknown's k-ratios
            foreach(k -> k.unkProps[:Coating] = coatings, kunk)
        end
        # How close are the calculated k-ratios to the measured version of the k-ratios?
        estkrs = computeKs(estcomp, zafs, stdComps)
        if eval(estkrs) < bestEval
            # If no convergence report it but return closest result...
            bestComp, bestKrs, bestEval, bestIter = estcomp, estkrs, eval(estkrs), iters
            if converged(iteration.converged, kunk, bestKrs)
                fc = computefinal(estcomp, kunk)
                return IterationResult(lbl, fc, measured, bestKrs, true, bestIter, iteration)
            end
        end
        # Compute the next estimated mass fractions
        upd, iter_state = update(iteration.updater, estcomp, kunk, zafs, iter_state)
        # Apply unmeasured element rules
        estcomp = material(repr(lbl), compute(iteration.unmeasured, upd))
        # calculated matrix correction for estcomp
        zafs = computeZAFs(iteration, estcomp, stdZafs)
    end
    @warn "$lbl did not converge in $(maxIter)."
    @warn "   Using best non-converged result from step $(bestIter)."
    return IterationResult(lbl, bestComp, measured, bestKrs, false, bestIter, iteration)
end

NeXLMatrixCorrection.quantify(
    measured::Vector{KRatios},
    iteration::Iteration=Iteration(fc=NullFluorescence, cc=NullCoating);
    kro::KRatioOptimizer=SimpleKRatioOptimizer(1.5),
    maxIter::Int=100,
    coating::Union{Nothing,Pair{CharXRay,<:Material}}=nothing,
    name::AbstractString="Map",
    ty::Union{Type{UncertainValue},Type{Float64},Type{Float32}}=Float32,
    maxErrors::Int=5
) = quantify(measured, iteration, kro, maxIter, coating, name, ty, maxErrors)

function NeXLMatrixCorrection.quantify(
    measured::Vector{KRatios},
    iteration::Iteration,
    kro::KRatioOptimizer,
    maxIter::Int,
    coating::Union{Nothing,Pair{CharXRay,<:Material}},
    name::AbstractString,
    ty::Union{Type{UncertainValue},Type{Float64},Type{Float32}},
    maxErrors::Int
)
    @assert all(size(measured[1]) == size(krsi) for krsi in measured[2:end]) "All the KRatios need to be the same dimensions."
    # Compute the C = k*C_std estimate
    firstEstimate(meas::Vector{KRatio}) =
        Dict(kr.element => value(nonnegk(kr)) * value(kr.standard[kr.element]) for kr in meas)
    # Compute the estimated k-ratios
    computeKs(comp, zafs, stdComps) =
        Dict(elm => comp[elm] * zafs[elm] / stdComps[elm] for (elm, zaf) in zafs)
    @assert isnothing(coating) || (get(last(coating), :Density, -1.0) > 0.0) "You must provide a positive density for the coating material."
    # Is this k-ratio due to the coating?
    iscoating(k, coatmat) = (!isnothing(coatmat)) && (first(coatmat) in k.xrays) && (element(k) in keys(last(coatmat)))
    # Compute the k-ratio difference metric
    eval(computed, kunk) = sum((value(nonnegk(kr)) - computed[kr.element])^2 for kr in kunk)
    # Pick the best sub-selection of `measured` to quantify
    optmeasured = brightest.(optimizeks(kro, measured))
    # Compute the standard matrix correction factors
    stdZafs = Dict(kr => _ZAF(iteration, convert(Material{Float64,Float64}, kr.standard), kr.stdProps, kr.xrays) for kr in optmeasured)
    stdComps = Dict(kr.element => value(kr.standard[kr.element]) for kr in optmeasured)
    mats = Materials(name, [element(kr) for kr in optmeasured], ty, size(measured[1]))
    nerrors, n_not_converged = Threads.Atomic{Int}(0), Threads.Atomic{Int}(0)
    ThreadsX.map!(mats, CartesianIndices(mats)) do ci
        bestComp, convergedp = NeXLCore.NULL_MATERIAL, false
        if nerrors[] < maxErrors
            try
                measured = KRatio[kr[ci] for kr in optmeasured]
                # k-ratios from measured elements in the unknown - Remove k-ratios for unmeasured and coating elements
                kunk = filter(measured) do kr
                    !(isunmeasured(iteration.unmeasured, element(kr)) || iscoating(kr, coating))
                end
                # k-ratios associated with the coating
                kcoat = filter(kr -> iscoating(kr, coating), measured)
                # First estimate c_unk = k*c_std
                estimate = material("first", compute(iteration.unmeasured, firstEstimate(kunk)))
                # Compute the associated matrix corrections
                zafs = computeZAFs(iteration, estimate, stdZafs)
                bestComp, bestKrs = estimate, computeKs(estimate, zafs, stdComps)
                bestEval, bestIter, iter_state = 1.0e300, 0, nothing
                for iters in Base.OneTo(maxIter)
                    if length(kcoat) >= 1
                        coatings = estimatecoating(estimate, last(coating), first(kcoat), iteration.mctype)
                        # Previous coatings are replaced on all the unknown's k-ratios
                        foreach(k -> k.unkProps[:Coating] = coatings, kunk)
                    end
                    # How close are the calculated k-ratios to the measured version of the k-ratios?
                    estKrs = computeKs(estimate, zafs, stdComps)
                    if (ev = eval(estKrs, kunk)) < bestEval
                        # If no convergence report it but return closest result...
                        bestComp, bestKrs, bestEval, bestIter = estimate, estKrs, ev, iters
                        if converged(iteration.converged, kunk, bestKrs)
                            convergedp = true
                            break
                        end
                    end
                    # Compute the next estimated mass fractions
                    upd, iter_state = update(iteration.updater, estimate, kunk, zafs, iter_state)
                    # Apply unmeasured element rules
                    estimate = material("bogus", compute(iteration.unmeasured, upd))
                    # calculated matrix correction for estimate
                    zafs = computeZAFs(iteration, estimate, stdZafs)
                end
            catch ex
                Threads.atomic_add!(nerrors, 1)
                @error ex
            end
            if !convergedp
                Threads.atomic_add!(n_not_converged, 1)
            end
        end
        return bestComp
    end
    if n_not_converged[] > 0
        @warn "$n_not_converged matrix correction operations did not converge."
    end
    if nerrors[] >= maxErrors
        @error "Exceeded $maxErrors errors - terminating early."
    end
    return mats
end