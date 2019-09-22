module NeXLMatrixCorrection

using NeXLCore

include("matrixcorrection.jl")
export summarize # Summarize ZAF corrections
export Z # Atomic number correction
export A # Absorption correction
export F # Fluorescence correction
export coating # Coating correction
export zaf # Build a ZAFCorrection
export ZAFCorrection
export FluorescenceCorrection
export CoatingCorrection
export MatrixCorrection
export ZAFc # Combined correction factor
export transmission # Coating transmission
export carbonCoating # Build a carbon coating
export Fχ # Absorbed intensity function
export takeOffAngle #

include("multizaf.jl")
export MultiZAF # Represents a multiline ZAF correction.
export ionizationCrossSection # Computes the *relative* ionization crosssection.

include("xpp.jl")
export ϕ # ϕ(ρz) function
export ϕabs # ϕ(ρz) function (absorbed)
export xpp # Build an XPP correction
export xppZAF # Build a full ZAF correction based on XPP
export XPPCorrection # XPPCorrection structure
export buildMultiXPP # Build a MultiZAF around the XPP algorithm

end
