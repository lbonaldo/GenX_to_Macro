using GenX_to_Macro
using GenX
using CSV, DataFrames, JSON3
using Logging, Test

const G2M = GenX_to_Macro

include("helpers.jl")

@testset "GenX_to_Macro" begin
    include("test_utilities.jl")
    include("test_single_stage.jl")
    include("test_multistage.jl")
    include("test_unsupported.jl")
end
