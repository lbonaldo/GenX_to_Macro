# Convert a GenX case in genx_cases/ into a Macro case, then optionally run both models.
# Works for single-stage and multi-stage GenX cases. Run from the repository root:
#     julia --project=. Multistage_convert.jl

using GenX_to_Macro
using GenX, MacroEnergy

genx_case = "6_three_zones_w_multistage_genx"
output_case = "6_three_zones_w_multistage_macro"
run_genx = true
run_macro = true

genx_case_path = joinpath("genx_cases", genx_case)
macro_case_path = joinpath("genx_cases", output_case)

convert_genx_case(genx_case_path, macro_case_path)

run_genx && GenX.run_genx_case!(genx_case_path)
run_macro && MacroEnergy.run_case(macro_case_path)
