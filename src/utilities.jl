
####### UTILS #######

function load_genx_case(genx_case_path::AbstractString)

    genx_settings = GenX.get_settings_path(genx_case_path, "genx_settings.yml")
    writeoutput_settings = GenX.get_settings_path(genx_case_path, "output_settings.yml")
    setup = GenX.configure_settings(genx_settings, writeoutput_settings)
    setup["ParameterScale"] = 0;
    settings_path = GenX.get_settings_path(genx_case_path)
    inputs = GenX.load_inputs(setup, genx_case_path)
    return setup, inputs

end

function load_genx_case(genx_case_path::AbstractString, genx_stage_path::AbstractString)

    genx_settings = GenX.get_settings_path(genx_case_path, "genx_settings.yml")
    writeoutput_settings = GenX.get_settings_path(genx_case_path, "output_settings.yml")
    setup = GenX.configure_settings(genx_settings, writeoutput_settings)
    setup["ParameterScale"] = 0;
    settings_path = GenX.get_settings_path(genx_case_path)
    inputs = GenX.load_inputs(setup, genx_stage_path)
    return setup, inputs

end

function make_macro_dir(macro_case::AbstractString)
    if !isdir(macro_case)
        mkdir(macro_case)
        mkdir(joinpath(macro_case, "system"))
        mkdir(joinpath(macro_case, "assets"))
        mkdir(joinpath(macro_case, "settings"))
        system_data = Dict("commodities" => Dict("path" => "system/commodities.json"),
            "locations" => Dict("path" => "locations"),
            "settings" => Dict("path" => "settings/macro_settings.json"),
            "assets" => Dict("path" => "assets"),
            "time_data" => Dict("path" => "system/time_data.json"),
            "nodes" => Dict("path" => "system/nodes.json")
        )
        open(joinpath(macro_case, "system_data.json"), "w") do io
            JSON3.pretty(io, system_data)
        end

        open(joinpath(macro_case, "settings/macro_settings.json"), "w") do io
            JSON3.pretty(io, Dict("ConstraintScaling"=>false))
        end
    end
end

# ~~~
# Multistage version
# ~~~

function make_macro_dir(macro_case::AbstractString, stage_folders)
    if !isdir(macro_case)
        mkdir(macro_case)
        mkdir(joinpath(macro_case, "system"))
        mkdir(joinpath(macro_case, "assets"))
        mkdir(joinpath(macro_case, "settings"))

        all_stages = []

        sorted_folders = sort(stage_folders, by=s -> parse(Int, split(s, "p")[end]))

        for stage in sorted_folders

            stage_number = get_stage_number(stage)

            system_data = Dict("commodities" => Dict("path" => "system/commodities.json"),
                "locations" => Dict("path" => "locations.json"),
                "settings" => Dict("path" => "settings/macro_settings.json"),
                "assets" => Dict("path" => string("assets/assets_", stage_number)),
                "time_data" => Dict("path" => string("system/time_data_", stage_number, ".json")),
                "nodes" => Dict("path" => string("system/nodes_", stage_number, ".json"))
            )

            push!(all_stages, system_data)

        end

        all_system_data = d = Dict(
            "case" => all_stages,
            "settings" => Dict(
                "path" => "settings/case_settings.json"
            )
        )

        open(joinpath(macro_case, "system_data.json"), "w") do io
            JSON3.pretty(io, all_system_data)
        end

        open(joinpath(macro_case, "settings/macro_settings.json"), "w") do io
            JSON3.pretty(io, Dict("ConstraintScaling"=>false))
        end

        open(joinpath(macro_case, "settings/case_settings.json"), "w") do io
            JSON3.pretty(io, Dict(["PeriodLengths"=>ones(length(stage_folders)), "DiscountRate" => 0.045,
                "SolutionAlgorithm" => "Monolithic"]))
        end
    end
end


function get_stage_number(stage_folder::AbstractString)

    m = match(r"\d+$", stage_folder)  # match digits at the end
    if m !== nothing
        num_str = m.match  # this is still a String
    end

    return num_str
end

function get_wacc_and_crp(resource::AbstractString, genx_stage_path::AbstractString)

    df_inv_input = CSV.read(string(genx_stage_path, "/resources/Resource_multistage_data.csv"), DataFrame)
    df_inv = select(df_inv_input, [:Resource, :WACC, :Capital_Recovery_Period, :Lifetime])
    wacc = filter(row->row.Resource==resource, df_inv).WACC[1]
    crp = filter(row->row.Resource==resource, df_inv).Capital_Recovery_Period[1]
    lifetime = filter(row->row.Resource==resource, df_inv).Lifetime[1]
    min_ret_cap = filter(row->row.Resource==resource, df_inv_input).Min_Retired_Cap_MW[1]

    return wacc, crp, lifetime, min_ret_cap

end