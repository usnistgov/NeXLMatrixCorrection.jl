module NeXLMatrixCorrection

using NeXLCore

include("matrixcorrection.jl")
export tabulate # tabulate ZAF corrections
export Z # Atomic number correction
export A # Absorption correction
export F # Compute the flurorescence correction
export ZA # Combined ZA (ϕ(ρz)) correction
export coating # Coating correction
export zaf # Build a ZAFCorrection
export ZAFCorrection
export FluorescenceCorrection
export CoatingCorrection
export MatrixCorrection
export ZAFc # Combined correction factor
export transmission # Coating transmission
export carboncoating # Build a carbon coating
export Fχ # Absorbed intensity function
export matrixcorrection

include("multizaf.jl")
export MultiZAF # Represents a multiline ZAF correction.
export detail # Output the details of the matrix correction

include("xpp.jl")
export ϕ # ϕ(ρz) function
export ϕabs # ϕ(ρz) function (absorbed)
export xpp # Build an XPP correction
export ZAF # Build a full ZAF correction based on XPP
export XPPCorrection # XPPCorrection structure

include("reed.jl")
export ReedFluorescence
export reedFluorescence # Construct a structure encapsulating the Reed fluorescence correction model

include("kratio.jl")
export KRatio # k-ratio data struct

include("iterate.jl")
export UnmeasuredElementRule # Calculation elements by difference or stoichiometry or ???
export NullUnmeasuredRule # Don't do anything..
export UpdateRule # A rule implementing update(...)
export NaiveUpdateRule # Simple iteration
export ConvergenceTest # Test for convergence using converged(...)
export RMSBelowTolerance, AllBelowTolerance, IsApproximate # Difference implementations of ConvergenceTest
export Iteration # Defines the iteration procedure
export IterationResult # The output from iterateks(...)
export iterateks # Perform the iteration

end
