# Convert a GenX case in genx_cases/ into a Macro case, then optionally run both models.
# Works for single-stage and multi-stage GenX cases. Run from the repository root:
#     julia --project=. Multistage_convert.jl
#
# Both models run with HiGHS, which comes with GenX and Macro. To use Gurobi instead, add it to
# your global environment once (julia -e 'using Pkg; Pkg.add("Gurobi")') and set use_gurobi.

using GenX_to_Macro
using GenX, MacroEnergy

genx_case = "6_three_zones_w_multistage_genx"
output_case = "6_three_zones_w_multistage_macro"
run_genx = true
run_macro = true
use_gurobi = false

genx_case_path = joinpath("genx_cases", genx_case)
macro_case_path = joinpath("genx_cases", output_case)

convert_genx_case(genx_case_path, macro_case_path)

if use_gurobi
    using Gurobi
end
if use_gurobi
    run_genx && GenX.run_genx_case!(genx_case_path, Gurobi.Optimizer)
    # Macro's default solver options are HiGHS options, so Gurobi needs its own.
    run_macro && MacroEnergy.run_case(macro_case_path;
        optimizer = Gurobi.Optimizer,
        optimizer_attributes = ("Method" => 2, "Crossover" => -1, "BarConvTol" => 1e-4))
else
    run_genx && GenX.run_genx_case!(genx_case_path)
    run_macro && MacroEnergy.run_case(macro_case_path)
end
