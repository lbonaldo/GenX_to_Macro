# This file is a multistage version of the Convert.jl file. It should be placed in the respective case folder under the folder genx_cases (e.g. genx_cases/case_name/).

using GenX_to_Macro

# Get all stage folders
genx_case = "name_of_case"
output_case = genx_case
path_to_all_cases = string("genx_cases/",genx_case,"/inputs")

stage_folders = filter(f -> isdir(joinpath(pwd(), path_to_all_cases, f)), readdir(path_to_all_cases))

genx_case_path = string("./genx_cases/",genx_case)
macro_case_path = joinpath(genx_case_path,output_case)
make_macro_dir(macro_case_path, stage_folders)

# Depending on case, may need to add/remove commodities
commodities_vec = ["Electricity", "NaturalGas", "CO2", "Uranium", "Coal"]

for case_folder in stage_folders

    stage_number = get_stage_number(case_folder)
    @info(string("Converting stage ", stage_number))
    
    genx_stage_path = joinpath(string("./genx_cases/",genx_case,"/Inputs"), case_folder)

    setup, inputs = load_genx_case(genx_case_path, genx_stage_path)

    # Same across stages usually/always. May want to keep out of loop
    commodities = make_commodities_json(commodities_vec, macro_case_path)
    time_data = make_timedata_json(inputs, setup,commodities_vec, genx_case_path, macro_case_path, genx_stage_path)

    nodes, demand, fuel_prices = make_nodes_json_demands_and_fuels(inputs, macro_case_path, genx_stage_path)

    asset_path = joinpath(macro_case_path,string("assets/assets_",stage_number))
    if !isdir(asset_path)
        mkdir(asset_path)
    end

    thermal = make_thermal_json(inputs, macro_case_path, genx_stage_path)
    thermal_ccs = make_thermal_ccs_json(inputs, macro_case_path, genx_stage_path)
    vre = make_vre_json(inputs, macro_case_path, genx_stage_path)
    storage = make_storage_json(inputs, setup, macro_case_path, genx_stage_path)
    transmission = make_transmission_json(inputs, macro_case_path, genx_stage_path)
    mustrun = make_mustrun_json(inputs,macro_case_path, genx_stage_path)
    hydro = make_hydro_json(inputs, setup, macro_case_path, genx_stage_path)

end