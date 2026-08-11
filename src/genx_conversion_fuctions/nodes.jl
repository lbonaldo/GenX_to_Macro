function make_nodes_json_demands_and_fuels(inputs::Dict, macro_case::AbstractString)
    gen = inputs["RESOURCES"]
    nodes = Dict("nodes" => [Dict(
        "type" => "Electricity",
        "global_data" => Dict("time_interval" => "Electricity",
            "constraints" => Dict("BalanceConstraint" => true,
                "MaxNonServedDemandConstraint" => true,
                "MaxNonServedDemandPerSegmentConstraint" => true),
            "max_nsd" => inputs["pMax_D_Curtail"],
            "price_nsd" => inputs["pC_D_Curtail"],
        ),
        "instance_data" => Vector{Dict{AbstractString,Any}}()
    ),
    ])

    demand_headers = Vector{AbstractString}()

    for z in 1:inputs["Z"]
        z_name = gen[findfirst(g.zone == z for g in gen)].region
        node_instance = Dict(
            "id" => "elec_" * z_name,
            "demand" => Dict("timeseries" => Dict("path" => "system/demand.csv",
                "header" => "elec_demand_" * z_name))
        )
        push!(nodes["nodes"][1]["instance_data"], node_instance)
        push!(demand_headers, "elec_demand_" * z_name)
    end
    demand = DataFrame(inputs["pD"], demand_headers)
    CSV.write(joinpath(macro_case, "System/demand.csv"), demand)

    fuel_names = setdiff(inputs["fuels"], ["None"])

    #### Here we assume NG is the only fuel but can be extended to other fuels adding more nodes to vector node["nodes"]
    push!(nodes["nodes"], Dict(
        "type" => "NaturalGas",
        "global_data" => Dict("time_interval" => "NaturalGas"),
        "instance_data" => Vector{Dict{AbstractString,Any}}()
    )
    )
    for f in fuel_names
        if occursin("gas", f) || occursin("_NG", f)
            node_instance = Dict(
                "id" => f,
                "supply" => Dict(
                    "seg1" => Dict(
                        "price" => Dict("timeseries" => Dict("path" => "system/fuel_prices.csv",
                            "header" => f)
                        )
                    )
                )
            )
            push!(nodes["nodes"][2]["instance_data"], node_instance)
        end
    end

    push!(nodes["nodes"], Dict(
        "type" => "Uranium",
        "global_data" => Dict("time_interval" => "Uranium"),
        "instance_data" => Vector{Dict{AbstractString,Any}}()
    )
    )
    for f in fuel_names
        if occursin("uranium", f)
            node_instance = Dict(
                "id" => f,
                "supply" => Dict(
                    "seg1" => Dict(
                        "price" => Dict("timeseries" => Dict("path" => "system/fuel_prices.csv",
                            "header" => f)
                        )
                    )
                )
            )
            push!(nodes["nodes"][3]["instance_data"], node_instance)
        end
    end

    push!(nodes["nodes"], Dict(
        "type" => "Coal",
        "global_data" => Dict("time_interval" => "Coal"),
        "instance_data" => Vector{Dict{AbstractString,Any}}()
    )
    )
    for f in fuel_names
        if occursin("coal", f)
            node_instance = Dict(
                "id" => f,
                "supply" => Dict(
                    "seg1" => Dict(
                        "price" => Dict("timeseries" => Dict("path" => "system/fuel_prices.csv",
                            "header" => f))
                    )
                )
            )
            push!(nodes["nodes"][4]["instance_data"], node_instance)
        end
    end

    fuel_prices = DataFrame([inputs["fuel_costs"][f] / conv_mmbtu_to_mwh for f in fuel_names], fuel_names)
    CSV.write(joinpath(macro_case, "System/fuel_prices.csv"), fuel_prices)

    push!(nodes["nodes"], Dict(
        "type" => "CO2",
        "global_data" => Dict(
            "time_interval" => "CO2",
            "constraints" => Dict(
                "CO2CapConstraint" => true,
                "BalanceConstraint" => false
            ),
        ),
        "instance_data" => [
            Dict("id" => "co2_sink_$cap",
                "rhs_policy" => Dict("CO2CapConstraint" => sum(inputs["dfMaxCO2"][z, cap]
                                                               for z in findall(x -> x == 1, inputs["dfCO2CapZones"][:, cap])))
            )
            for cap in 1:inputs["NCO2Cap"]
        ]
    )
    )

    push!(nodes["nodes"], Dict(
        "type" => "Electricity",
        "global_data" => Dict(
            "time_interval" => "Electricity",
            "constraints" => Dict(
                "BalanceConstraint" => false
            ),
        ),
        "instance_data" => [
            Dict(
                "id" => "water_node",
            )
        ]
    )
    )

    open(joinpath(macro_case, "System/nodes.json"), "w") do io
        JSON3.pretty(io, nodes)
    end
    return nodes, demand, fuel_prices
end

# ~~~
# Multistage
# ~~~


function make_nodes_json_demands_and_fuels(inputs::Dict, macro_case::AbstractString, genx_stage_path::AbstractString)

    stage_number = get_stage_number(genx_stage_path)

    gen = inputs["RESOURCES"]
    nodes = Dict("nodes" => [Dict(
        "type" => "Electricity",
        "global_data" => Dict("time_interval" => "Electricity",
            "constraints" => Dict("BalanceConstraint" => true,
                "MaxNonServedDemandConstraint" => true,
                "MaxNonServedDemandPerSegmentConstraint" => true),
            "max_nsd" => inputs["pMax_D_Curtail"],
            "price_nsd" => inputs["pC_D_Curtail"],
        ),
        "instance_data" => Vector{Dict{AbstractString,Any}}()
    ),
    ])

    demand_headers = Vector{AbstractString}()

    for z in 1:inputs["Z"]
        z_name = gen[findfirst(g.zone == z for g in gen)].region
        node_instance = Dict(
            "id" => "elec_" * z_name,
            "demand" => Dict("timeseries" => Dict("path" => string("system/demand_", stage_number, ".csv"),
                "header" => "elec_demand_" * z_name))
        )
        push!(nodes["nodes"][1]["instance_data"], node_instance)
        push!(demand_headers, "elec_demand_" * z_name)
    end

    demand = DataFrame(inputs["pD"], demand_headers)
    CSV.write(joinpath(macro_case, string("System/demand_", stage_number, ".csv")), demand)

    fuel_names = setdiff(inputs["fuels"], ["None"])

    #### Here we assume NG is the only fuel but can be extended to other fuels adding more nodes to vector node["nodes"]
    push!(nodes["nodes"], Dict(
        "type" => "NaturalGas",
        "global_data" => Dict("time_interval" => "NaturalGas"),
        "instance_data" => Vector{Dict{AbstractString,Any}}()
    )
    )
    for f in fuel_names
        if occursin("gas", f) || occursin("_NG", f)
            node_instance = Dict(
                "id" => f,
                "supply" => Dict(
                    "seg1" => Dict(
                        "price" => Dict("timeseries" => Dict("path" => string("system/fuel_prices_", stage_number, ".csv"),
                            "header" => f)
                        )
                    )
                )
            )
            push!(nodes["nodes"][2]["instance_data"], node_instance)
        end
    end

    push!(nodes["nodes"], Dict(
        "type" => "Uranium",
        "global_data" => Dict("time_interval" => "Uranium"),
        "instance_data" => Vector{Dict{AbstractString,Any}}()
    )
    )
    for f in fuel_names
        if occursin("uranium", f)
            node_instance = Dict(
                "id" => f,
                "supply" => Dict(
                    "seg1" => Dict(
                        "price" => Dict("timeseries" => Dict("path" => string("system/fuel_prices_", stage_number, ".csv"),
                            "header" => f)
                        )
                    )
                )
            )
            push!(nodes["nodes"][3]["instance_data"], node_instance)
        end
    end

    push!(nodes["nodes"], Dict(
        "type" => "Coal",
        "global_data" => Dict("time_interval" => "Coal"),
        "instance_data" => Vector{Dict{AbstractString,Any}}()
    )
    )
    for f in fuel_names
        if occursin("coal", f)
            node_instance = Dict(
                "id" => f,
                "supply" => Dict(
                    "seg1" => Dict(
                        "price" => Dict("timeseries" => Dict("path" => string("system/fuel_prices_", stage_number, ".csv"),
                            "header" => f)
                        )
                    )
                )
            )
            push!(nodes["nodes"][4]["instance_data"], node_instance)
        end
    end

    fuel_prices = DataFrame([inputs["fuel_costs"][f] / conv_mmbtu_to_mwh for f in fuel_names], fuel_names)
    CSV.write(joinpath(macro_case, string("System/fuel_prices_", stage_number, ".csv")), fuel_prices)

    push!(nodes["nodes"], Dict(
        "type" => "CO2",
        "global_data" => Dict(
            "time_interval" => "CO2",
            "constraints" => Dict(
                "CO2CapConstraint" => true,
                "BalanceConstraint" => false
            ),
        ),
        "instance_data" => [
            Dict("id" => "co2_sink_$cap",
                "rhs_policy" => Dict("CO2CapConstraint" => sum(inputs["dfMaxCO2"][z, cap]
                                                               for z in findall(x -> x == 1, inputs["dfCO2CapZones"][:, cap])))
            )
            for cap in 1:inputs["NCO2Cap"]
        ]
    )
    )

    push!(nodes["nodes"], Dict(
        "type" => "Electricity",
        "global_data" => Dict(
            "time_interval" => "Electricity",
            "constraints" => Dict(
                "BalanceConstraint" => false
            ),
        ),
        "instance_data" => [    
            Dict(
                "id" => "water_node",
            )
        ]
    )
    )

    open(joinpath(macro_case, string("System/nodes_", stage_number, ".json")), "w") do io
        JSON3.pretty(io, nodes)
    end
    return nodes, demand, fuel_prices
end