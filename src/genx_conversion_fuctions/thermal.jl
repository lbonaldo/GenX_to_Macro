function make_thermal_json(inputs::Dict, macro_case::AbstractString)
    THERM_ALL = inputs["THERM_ALL"];

    thermal = Dict("ThermalPower" => Dict(
        "type"=>"ThermalPower",
        "global_data"=>Dict(
            "transforms" => Dict(
                "constraints" => Dict("BalanceConstraint" => true)
            ),
            "edges" => Dict(
                "elec_edge" => Dict("unidirectional" => true,
                    "has_capacity" => true,),
                "fuel_edge" => Dict("unidirectional" => true,
                    "has_capacity" => false,),
                "co2_edge" => Dict("unidirectional" => true,
                    "has_capacity" => false,),
            ),
        ),
        "instance_data"=>Vector{Dict{AbstractString,Any}}()
    )
    )

    gen(y) = inputs["RESOURCES"][y];
    thermal_availability = DataFrame();
    for y in THERM_ALL
        if occursin("gas", gen(y).fuel) || occursin("_NG", gen(y).fuel)
            fuel_type = "NaturalGas"
        elseif occursin("coal", gen(y).fuel)
            fuel_type = "Coal"
        elseif occursin("uranium", gen(y).fuel)
            fuel_type = "Uranium"
        end

        pmax = inputs["pP_Max"][y, :];

        if length(unique(pmax))==1
            gen_availability = unique(pmax)
        else
            gen_availability = Dict("timeseries" => Dict(
                "path" => "system/therm_availability.csv",
                "header" => gen(y).resource))

            thermal_availability[!, Symbol(gen(y).resource)] = pmax;
        end

        if in(y, inputs["THERM_COMMIT"])
            constraints_dict = Dict(
                "CapacityConstraint" => true,
                "RampingLimitConstraint" => true,
                "MinUpTimeConstraint" => true,
                "MinDownTimeConstraint" => true
            )
        else
            constraints_dict = Dict(
                "CapacityConstraint" => true,
                "RampingLimitConstraint" => true,
            )
        end

        if gen(y).min_power > 0
            constraints_dict["MinFlowConstraint"] = true
        end

        if gen(y).min_cap_mw > 0
            constraints_dict["MinCapacityConstraint"] = true
        end

        if gen(y).max_cap_mw > 0
            constraints_dict["MaxCapacityConstraint"] = true
        end

        co2cap = findfirst(inputs["dfCO2CapZones"][gen(y).zone, :] .== 1)

        push!(thermal["ThermalPower"]["instance_data"],
            Dict(
                "id" => gen(y).resource,
                "transforms" => Dict(
                    "timedata" => fuel_type,
                    "emission_rate" => inputs["fuel_CO2"][gen(y).fuel]/conv_mmbtu_to_mwh,
                    "fuel_consumption" => conv_mmbtu_to_mwh * gen(y).heat_rate_mmbtu_per_mwh
                ),
                "edges" => Dict(
                    "elec_edge" => Dict(
                        "end_vertex" => "elec_" * gen(y).region,
                        "commodity" => "Electricity",
                        "uc" => in(y, inputs["THERM_COMMIT"]),
                        "constraints" => constraints_dict,
                        "availability" => gen_availability,
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "capacity_size" => gen(y).cap_size,
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => gen(y).fixed_om_cost_per_mwyr,
                        "annualized_investment_cost" => gen(y).inv_cost_per_mwyr,
                        "max_capacity" => gen(y).max_cap_mw,
                        "min_capacity" => gen(y).min_cap_mw,
                        "min_flow_fraction" => gen(y).min_power,
                        "ramp_down_fraction" => gen(y).ramp_dn_percentage,
                        "ramp_up_fraction" => gen(y).ramp_up_percentage,
                        "variable_om_cost" => gen(y).var_om_cost_per_mwh,
                        "min_down_time" => gen(y).down_time,
                        "min_up_time" => gen(y).up_time,
                        "startup_cost" => gen(y).start_cost_per_mw,
                        "startup_fuel_consumption" => conv_mmbtu_to_mwh * gen(y).start_fuel_mmbtu_per_mw
                    ),
                    "fuel_edge" => Dict(
                        "commodity" => fuel_type,
                        "start_vertex" => gen(y).fuel
                    ),
                    "co2_edge" => Dict(
                        "commodity" => "CO2",
                        "end_vertex" => "co2_sink_$co2cap"
                    )
                )
            )
        )
    end

    open(joinpath(macro_case, "assets/thermal.json"), "w") do io
        JSON3.pretty(io, thermal)
    end

    if !isempty(thermal_availability)
        CSV.write(joinpath(macro_case, "system/thermal_availability.csv"), thermal_availability)
    end

    return thermal

end

# ~~~
# Multistage
# ~~~

function make_thermal_json(inputs::Dict, macro_case::AbstractString, genx_stage_path::AbstractString)

    stage_number = get_stage_number(genx_stage_path)

    THERM_NOCCS = setdiff(inputs["THERM_ALL"], inputs["CCS"])

    thermal = Dict("ThermalPower" => Dict(
        "type"=>"ThermalPower",
        "global_data"=>Dict(
            "transforms" => Dict(
                "constraints" => Dict("BalanceConstraint" => true)
            ),
            "edges" => Dict(
                "elec_edge" => Dict("unidirectional" => true,
                    "has_capacity" => true,),
                "fuel_edge" => Dict("unidirectional" => true,
                    "has_capacity" => false,),
                "co2_edge" => Dict("unidirectional" => true,
                    "has_capacity" => false,),
            ),
        ),
        "instance_data"=>Vector{Dict{AbstractString,Any}}()
    )
    )

    gen(y) = inputs["RESOURCES"][y];
    thermal_availability = DataFrame();
    for y in THERM_NOCCS
        if occursin("gas", gen(y).fuel) || occursin("_NG", gen(y).fuel)
            fuel_type = "NaturalGas"
        elseif occursin("coal", gen(y).fuel)
            fuel_type = "Coal"
        elseif occursin("uranium", gen(y).fuel)
            fuel_type = "Uranium"
        end

        pmax = inputs["pP_Max"][y, :];

        if length(unique(pmax))==1
            gen_availability = unique(pmax)
        else
            gen_availability = Dict("timeseries" => Dict(
                "path" => string("system/thermal_availability_", stage_number, ".csv"),
                "header" => gen(y).resource))
            thermal_availability[!, Symbol(gen(y).resource)] = pmax;
        end

        if in(y, inputs["THERM_COMMIT"])
            constraints_dict = Dict(
                "CapacityConstraint" => true,
                "RampingLimitConstraint" => true,
                "MinUpTimeConstraint" => true,
                "MinDownTimeConstraint" => true
            )
        else
            constraints_dict = Dict(
                "CapacityConstraint" => true,
                "RampingLimitConstraint" => true,
            )
        end

        if gen(y).min_power > 0
            constraints_dict["MinFlowConstraint"] = true
        end

        if haskey(gen(y), :min_cap_mw) && gen(y).min_cap_mw > 0
            constraints_dict["MinCapacityConstraint"] = true
        end

        if gen(y).max_cap_mw > 0
            constraints_dict["MaxCapacityConstraint"] = true
        end

        # co2cap = findfirst(inputs["dfCO2CapZones"][gen(y).zone,:].==1)
        co2cap = "co2_sink_nothing"

        wacc, crp, lifetime, min_ret_cap = get_wacc_and_crp(gen(y).resource, genx_stage_path)

        push!(thermal["ThermalPower"]["instance_data"],
            Dict(
                "id" => gen(y).resource,
                "transforms" => Dict(
                    "timedata" => fuel_type,
                    "emission_rate" => inputs["fuel_CO2"][gen(y).fuel]/conv_mmbtu_to_mwh,
                    "fuel_consumption" => conv_mmbtu_to_mwh * gen(y).heat_rate_mmbtu_per_mwh
                ),
                "edges" => Dict(
                    "elec_edge" => Dict(
                        "end_vertex" => "elec_" * gen(y).region,
                        "commodity" => "Electricity",
                        "uc" => in(y, inputs["THERM_COMMIT"]),
                        "constraints" => constraints_dict,
                        "availability" => gen_availability,
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "capacity_size" => gen(y).cap_size,
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => gen(y).fixed_om_cost_per_mwyr,
                        "annualized_investment_cost" => gen(y).inv_cost_per_mwyr,
                        "max_capacity" => gen(y).max_cap_mw,
                        "min_capacity" => 0,
                        "min_flow_fraction" => gen(y).min_power,
                        "ramp_down_fraction" => gen(y).ramp_dn_percentage,
                        "ramp_up_fraction" => gen(y).ramp_up_percentage,
                        "variable_om_cost" => gen(y).var_om_cost_per_mwh,
                        "min_down_time" => gen(y).down_time,
                        "min_up_time" => gen(y).up_time,
                        "startup_cost" => gen(y).start_cost_per_mw,
                        "startup_fuel_consumption" => conv_mmbtu_to_mwh * gen(y).start_fuel_mmbtu_per_mw,
                        "wacc" => wacc,
                        "capital_recovery_period" => crp,
                        "lifetime" => lifetime,
                        "min_retired_capacity" => min_ret_cap
                    ),
                    "fuel_edge" => Dict(
                        "commodity" => fuel_type,
                        "start_vertex" => gen(y).fuel
                    ),
                    "co2_edge" => Dict(
                        "commodity" => "CO2",
                        "end_vertex" => co2cap
                    )
                )
            )
        )
    end

    open(joinpath(macro_case, string("assets/assets_", stage_number, "/thermal.json")), "w") do io
        JSON3.pretty(io, thermal)
    end

    if !isempty(thermal_availability)
        CSV.write(joinpath(macro_case, string("system/thermal_availability_", stage_number, ".csv")), thermal_availability)
    end

    return thermal

end

# ~~~
# CCS Thermal
# ~~~

function make_thermal_ccs_json(inputs::Dict, macro_case::AbstractString, genx_stage_path::AbstractString)


    stage_number = get_stage_number(genx_stage_path)

    THERM_CCS = inputs["CCS"]

    co2cap = "co2_sink_nothing"
    co2capture = "co2_sink_injection"

    ccs_availability_filename = string("system/ccs_thermal_availability_", stage_number, ".csv")

    thermal = Dict(
        "ThermalPowerCCS" => Dict(
            "type" => "ThermalPowerCCS",
            "global_data" => Dict(
                "transforms" => Dict(
                    "constraints" => Dict("BalanceConstraint" => true)
                ),
                "edges" => Dict(
                    "elec_edge" => Dict("unidirectional" => true,
                        "has_capacity" => true,),
                    "fuel_edge" => Dict("unidirectional" => true,
                        "has_capacity" => false,),
                    "co2_edge" => Dict("unidirectional" => true,
                        "has_capacity" => false,
                        "commodity" => "CO2",
                        "end_vertex" => co2cap),
                    "co2_captured_edge" => Dict("unidirectional" => true,
                        "has_capacity" => false,
                        "commodity" => "CO2Captured",
                        "end_vertex" => co2capture),
                ),
            ),
            "instance_data" => Vector{Dict{AbstractString,Any}}()
        )
    )

    gen(y) = inputs["RESOURCES"][y]
    thermal_availability = DataFrame()
    for y in THERM_CCS
        if occursin("gas", gen(y).fuel) || occursin("_NG", gen(y).fuel)
            fuel_type = "NaturalGas"
        elseif occursin("coal", gen(y).fuel)
            fuel_type = "Coal"
        elseif occursin("uranium", gen(y).fuel)
            fuel_type = "Uranium"
        end

        pmax = inputs["pP_Max"][y, :]

        if length(unique(pmax)) == 1
            gen_availability = unique(pmax)
        else
            gen_availability = Dict("timeseries" => Dict(
                "path" => ccs_availability_filename,
                "header" => gen(y).resource))

            thermal_availability[!, Symbol(gen(y).resource)] = pmax
        end

        if in(y, inputs["THERM_COMMIT"])
            constraints_dict = Dict(
                "CapacityConstraint" => true,
                "RampingLimitConstraint" => true,
                "MinUpTimeConstraint" => true,
                "MinDownTimeConstraint" => true
            )
        else
            constraints_dict = Dict(
                "CapacityConstraint" => true,
                "RampingLimitConstraint" => true,
            )
        end

        if gen(y).min_power > 0
            constraints_dict["MinFlowConstraint"] = true
        end

        if haskey(gen(y), :min_cap_mw) && gen(y).min_cap_mw > 0
            constraints_dict["MinCapacityConstraint"] = true
        end

        if gen(y).max_cap_mw > 0
            constraints_dict["MaxCapacityConstraint"] = true
        end

        wacc, crp, lifetime, min_ret_cap = get_wacc_and_crp(gen(y).resource, genx_stage_path)

        if in(y, inputs["NEW_CAP"])
            constraints_dict["MaxCapacityGrowthConstraint"] = true
            constraints_dict["DevelopmentConstraint"] = true
        end

        push!(thermal["ThermalPowerCCS"]["instance_data"],
            Dict(
                "id" => gen(y).resource,
                "transforms" => Dict(
                    "timedata" => fuel_type,
                    "emission_rate" => (1 - gen(y).co2_capture_fraction) * inputs["fuel_CO2"][gen(y).fuel] / conv_mmbtu_to_mwh,
                    "fuel_consumption" => conv_mmbtu_to_mwh * gen(y).heat_rate_mmbtu_per_mwh,
                    "capture_rate" => gen(y).co2_capture_fraction * inputs["fuel_CO2"][gen(y).fuel] / conv_mmbtu_to_mwh
                ),
                "edges" => Dict(
                    "elec_edge" => Dict(
                        "end_vertex" => "elec_" * gen(y).region,
                        "commodity" => "Electricity",
                        "uc" => in(y, inputs["THERM_COMMIT"]),
                        "constraints" => constraints_dict,
                        "availability" => gen_availability,
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "capacity_size" => gen(y).cap_size,
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => gen(y).fixed_om_cost_per_mwyr,
                        "annualized_investment_cost" => gen(y).inv_cost_per_mwyr,
                        "max_capacity" => gen(y).max_cap_mw,
                        "min_capacity" => 0,
                        "min_flow_fraction" => gen(y).min_power,
                        "ramp_down_fraction" => gen(y).ramp_dn_percentage,
                        "ramp_up_fraction" => gen(y).ramp_up_percentage,
                        "variable_om_cost" => gen(y).var_om_cost_per_mwh,
                        "min_down_time" => gen(y).down_time,
                        "min_up_time" => gen(y).up_time,
                        "startup_cost" => gen(y).start_cost_per_mw,
                        "startup_fuel_consumption" => conv_mmbtu_to_mwh * gen(y).start_fuel_mmbtu_per_mw,
                        "wacc" => wacc,
                        "capital_recovery_period" => crp,
                        "lifetime" => lifetime,
                        "min_retired_capacity" => min_ret_cap
                    ),
                    "fuel_edge" => Dict(
                        "commodity" => fuel_type,
                        "start_vertex" => gen(y).fuel
                    )
                )
            )
        )
    end

    open(joinpath(macro_case, string("assets/assets_", stage_number, "/thermal_ccs.json")), "w") do io
        JSON3.pretty(io, thermal)
    end

    if !isempty(thermal_availability)
        CSV.write(joinpath(macro_case, ccs_availability_filename), thermal_availability)
    end

    return thermal

end