module GenX_to_Macro

using JSON3
using DataFrames
using CSV
using GenX
using Revise

export load_genx_case
export make_macro_dir
export make_commodities_json
export make_timedata_json
export make_nodes_json_demands_and_fuels
export make_thermal_json
export make_thermal_ccs_json
export make_vre_json
export make_mustrun_json
export make_storage_json
export make_hydro_json
export make_transmission_json
export get_stage_number
export get_wacc_and_crp

const conv_mmbtu_to_mwh = 0.29307107
const conv_h2ton_to_mwh = 33.3

include("utilities.jl")
include("genx_conversion_fuctions/commodities.jl")
include("genx_conversion_fuctions/timedata.jl")
include("genx_conversion_fuctions/nodes.jl")
include("genx_conversion_fuctions/thermal.jl")
include("genx_conversion_fuctions/vre.jl")
include("genx_conversion_fuctions/storage.jl")
include("genx_conversion_fuctions/transmission.jl")
include("genx_conversion_fuctions/mustrun.jl")
include("genx_conversion_fuctions/hydro.jl")

end # module GenX_to_Macro
