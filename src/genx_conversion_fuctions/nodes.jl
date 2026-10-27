"""
    make_nodes_json_demands_and_fuels(inputs, setup, t)

Write the nodes file, the demand profiles and the fuel prices.

Nodes: one electricity node per zone; one node per fuel, grouped by commodity; one CO2 node
per GenX CO2 cap, plus an uncapped CO2 node for emissions outside every cap; a captured-CO2
node when there are CCS plants; and the water node when there is hydro. Returns the nodes,
demand and fuel prices.
"""
function make_nodes_json_demands_and_fuels(inputs::Dict, setup::Dict, t::Target)
    nodes = Any[]

    demand_file = system_file(t, "demand", "csv")
    elec_nodes = Dict(
        "type" => "Electricity",
        "global_data" => Dict(
            "time_interval" => "Electricity",
            "constraints" => Dict(
                "BalanceConstraint" => true,
                "MaxNonServedDemandConstraint" => true,
                "MaxNonServedDemandPerSegmentConstraint" => true),
            "max_nsd" => inputs["pMax_D_Curtail"],
            "price_nsd" => inputs["pC_D_Curtail"]),
        "instance_data" => Vector{Dict{AbstractString, Any}}())
    demand_headers = String[]
    for z in 1:inputs["Z"]
        header = "elec_demand_" * zone_region(inputs, z)
        push!(elec_nodes["instance_data"], Dict(
            "id" => "elec_" * zone_region(inputs, z),
            "demand" => Dict("timeseries" => Dict("path" => demand_file, "header" => header))))
        push!(demand_headers, header)
    end
    push!(nodes, elec_nodes)
    demand = DataFrame(inputs["pD"], demand_headers)
    CSV.write(case_path(t, demand_file), demand)

    # Fuel nodes, priced from the fuel price file. Fuels with no Macro commodity get no node;
    # check_supported rejects a thermal plant that burns one.
    fuel_file = system_file(t, "fuel_prices", "csv")
    fuel_names = setdiff(inputs["fuels"], ["None"])
    for commodity in ("NaturalGas", "Uranium", "Coal")
        fuels = filter(f -> fuel_commodity(f) == commodity, fuel_names)
        isempty(fuels) && continue
        push!(nodes, Dict(
            "type" => commodity,
            "global_data" => Dict("time_interval" => commodity),
            "instance_data" => [Dict(
                "id" => f,
                "supply" => Dict("seg1" => Dict("price" => Dict(
                    "timeseries" => Dict("path" => fuel_file, "header" => f)))))
                                for f in fuels]))
    end
    fuel_prices = DataFrame([inputs["fuel_costs"][f] / conv_mmbtu_to_mwh for f in fuel_names],
        fuel_names)
    CSV.write(case_path(t, fuel_file), fuel_prices)

    # One CO2 node per mass cap (Macro's CO2CapConstraint), with GenX's penalty price for
    # exceeding the cap when the case has one.
    if haskey(inputs, "dfCO2CapZones")
        caps = map(1:inputs["NCO2Cap"]) do cap
            zones = findall(==(1), inputs["dfCO2CapZones"][:, cap])
            node = Dict{String, Any}("id" => "co2_sink_$cap",
                "rhs_policy" => Dict("CO2CapConstraint" =>
                    sum(inputs["dfMaxCO2"][z, cap] for z in zones)))
            if haskey(inputs, "dfCO2Cap_slack")
                node["price_unmet_policy"] = Dict("CO2CapConstraint" =>
                    inputs["dfCO2Cap_slack"][cap, :PriceCap])
            end
            node
        end
        push!(nodes, Dict(
            "type" => "CO2",
            "global_data" => Dict(
                "time_interval" => "CO2",
                "constraints" => Dict("CO2CapConstraint" => true, "BalanceConstraint" => false)),
            "instance_data" => caps))
    end
    gen = inputs["RESOURCES"]
    if any(co2_sink(inputs, gen[y].zone) == UNCAPPED_CO2_SINK for y in inputs["THERM_ALL"])
        push!(nodes, Dict(
            "type" => "CO2",
            "global_data" => Dict(
                "time_interval" => "CO2",
                "constraints" => Dict("BalanceConstraint" => false)),
            "instance_data" => [Dict("id" => UNCAPPED_CO2_SINK)]))
    end
    if !isempty(ccs_thermal(inputs))
        push!(nodes, Dict(
            "type" => "CO2Captured",
            "global_data" => Dict(
                "time_interval" => "CO2Captured",
                "constraints" => Dict("BalanceConstraint" => false)),
            "instance_data" => [Dict("id" => CO2_CAPTURED_SINK)]))
    end

    if !isempty(inputs["HYDRO_RES"])
        push!(nodes, Dict(
            "type" => "Electricity",
            "global_data" => Dict(
                "time_interval" => "Electricity",
                "constraints" => Dict("BalanceConstraint" => false)),
            "instance_data" => [Dict("id" => "water_node")]))
    end

    write_json(case_path(t, system_file(t, "nodes", "json")), Dict("nodes" => nodes))
    return nodes, demand, fuel_prices
end
