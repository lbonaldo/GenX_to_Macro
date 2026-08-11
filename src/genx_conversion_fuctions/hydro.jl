function make_hydro_json(inputs::Dict, setup::Dict, macro_case::AbstractString)
    HYDRO_RES = inputs["HYDRO_RES"]
    hydrores = Dict("hydro_res" => Dict(
        "type" => "HydroRes",
        "global_data" => Dict(
            "storage" => Dict(
                "commodity" => "Electricity",
            ),
            "edges" => Dict(
                "discharge_edge" => Dict(
                    "commodity" => "Electricity",
                    "unidirectional" => true,
                    "has_capacity" => true
                ),
                "spill_edge" => Dict(
                    "commodity" => "Electricity",
                    "unidirectional" => true,
                    "has_capacity" => false
                ),
                "inflow_edge" => Dict(
                    "commodity" => "Electricity",
                    "unidirectional" => true,
                    "has_capacity" => true
                )
            ),
        ),
        "instance_data" => Vector{Dict{AbstractString,Any}}()
    )
    )


    gen(y) = inputs["RESOURCES"][y]
    hydro_availability = DataFrame()
    for y in HYDRO_RES
        discharge_constraints_dict = Dict(
            "CapacityConstraint" => true,
            "StorageDischargeLimitConstraint" => true,
            "RampingLimitConstraint" => true
        )
        storage_constraints_dict = Dict(
            "BalanceConstraint" => true,
            "StorageChargeDischargeRatioConstraint" => true,
            "MinStorageOutflowConstraint" => true
        )

        inflow_constraints_dict = Dict("MustRunConstraint" => true)

        if (!in(y, inputs["RET_CAP"])) && (!in(y, inputs["NEW_CAP"])) && (gen(y).existing_cap_mw == 0)
            continue
        end

        if setup["LDSAdditionalConstraints"] == 1 && gen(y).lds == 1
            storage_constraints_dict["LongDurationStorageImplicitMinMaxConstraint"] = true
        end

        if in(y, inputs["HYDRO_RES_KNOWN_CAP"])
            storage_constraints_dict["StorageMaxDurationConstraint"] = true
            storage_constraints_dict["StorageCapacityConstraint"] = true
        end

        if gen(y).min_cap_mw>0
            discharge_constraints_dict["MinCapacityConstraint"] = true
        end

        if gen(y).max_cap_mw>0
            discharge_constraints_dict["MaxCapacityConstraint"] = true
        end


        pmax = inputs["pP_Max"][y, :]

        if length(unique(pmax)) == 1
            gen_availability = unique(pmax)
        else
            gen_availability = Dict("timeseries" => Dict(
                "path" => "system/hydro_availability.csv",
                "header" => gen(y).resource))

            hydro_availability[!, Symbol(gen(y).resource)] = pmax
        end

        push!(hydrores["hydro_res"]["instance_data"],
            Dict(
                "id" => gen(y).resource,
                "storage" => Dict(
                    "can_expand" => in(y, inputs["NEW_CAP"]) && in(y, inputs["HYDRO_RES_KNOWN_CAP"]),
                    "capacity_size" => 1.0 * in(y, inputs["HYDRO_RES_KNOWN_CAP"]),
                    "can_retire" => in(y, inputs["RET_CAP"]) && in(y, inputs["HYDRO_RES_KNOWN_CAP"]),
                    "charge_discharge_ratio" => 1.0,
                    "constraints" => storage_constraints_dict,
                    "existing_capacity" => gen(y).hydro_energy_to_power_ratio * gen(y).existing_cap_mw * in(y, inputs["HYDRO_RES_KNOWN_CAP"]),
                    "fixed_om_cost" => 0.0,
                    "investment_cost" => 0.0,
                    "long_duration" => gen(y).lds == 1,
                    "loss_fraction" => 0.0,
                    "max_duration" => gen(y).hydro_energy_to_power_ratio * in(y, inputs["HYDRO_RES_KNOWN_CAP"]),
                    "min_outflow_fraction" => gen(y).min_power,
                ),
                "edges" => Dict(
                    "discharge_edge" => Dict(
                        "availability" => [1.0],
                        "end_vertex" => "elec_" * gen(y).region,
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "capacity_size" => 1.0,
                        "constraints" => discharge_constraints_dict,
                        "efficiency" => gen(y).eff_down,
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => gen(y).fixed_om_cost_per_mwyr,
                        "annualized_investment_cost" => gen(y).inv_cost_per_mwyr,
                        "max_capacity" => gen(y).max_cap_mw,
                        "min_capacity" => gen(y).min_cap_mw,
                        "ramp_down_fraction" => gen(y).ramp_dn_percentage,
                        "ramp_up_fraction" => gen(y).ramp_up_percentage,
                        "variable_om_cost" => gen(y).var_om_cost_per_mwh
                    ),
                    "inflow_edge" => Dict(
                        "availability" => gen_availability,
                        "start_vertex" => "water_node",
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "capacity_size" => 1.0,
                        "constraints" => inflow_constraints_dict,
                        "efficiency" => 1.0,
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => 0.0,
                        "annualized_investment_cost" => 0.0,
                        "variable_om_cost" => 0.0
                    ),
                    "spill_edge" => Dict(
                        "commodity" => "Electricity",
                        "end_vertex" => "water_node"
                    )
                )
            )
        )

    end

    open(joinpath(macro_case, "assets/hydro.json"), "w") do io
        JSON3.pretty(io, hydrores)
    end

    if !isempty(hydro_availability)
        CSV.write(joinpath(macro_case, "system/hydro_availability.csv"), hydro_availability)
    end
end

# ~~~ 
# Multistage
# ~~~

function make_hydro_json(inputs::Dict, setup::Dict, macro_case::AbstractString, genx_stage_path)

    stage_number = get_stage_number(genx_stage_path)

    HYDRO_RES = inputs["HYDRO_RES"]
    hydrores = Dict("hydro_res" => Dict(
        "type" => "HydroRes",
        "global_data" => Dict(
            "storage" => Dict(
                "commodity" => "Electricity",
            ),
            "edges" => Dict(
                "discharge_edge" => Dict(
                    "commodity" => "Electricity",
                    "unidirectional" => true,
                    "has_capacity" => true
                ),
                "spill_edge" => Dict(
                    "commodity" => "Electricity",
                    "unidirectional" => true,
                    "has_capacity" => false
                ),
                "inflow_edge" => Dict(
                    "commodity" => "Electricity",
                    "unidirectional" => true,
                    "has_capacity" => true
                )
            ),
        ),
        "instance_data" => Vector{Dict{AbstractString,Any}}()
    )
    )


    gen(y) = inputs["RESOURCES"][y]
    hydro_availability = DataFrame()
    for y in HYDRO_RES
        discharge_constraints_dict = Dict(
            "CapacityConstraint" => true,
            "StorageDischargeLimitConstraint" => true,
            "RampingLimitConstraint" => true
        )
        storage_constraints_dict = Dict(
            "BalanceConstraint" => true,
            "StorageChargeDischargeRatioConstraint" => true,
            "MinStorageOutflowConstraint" => true
        )

        inflow_constraints_dict = Dict("MustRunConstraint" => true)

        if (!in(y, inputs["RET_CAP"])) && (!in(y, inputs["NEW_CAP"])) && (gen(y).existing_cap_mw == 0)
            continue
        end

        if setup["LDSAdditionalConstraints"] == 1 && gen(y).lds == 1
            storage_constraints_dict["LongDurationStorageImplicitMinMaxConstraint"] = true
        end

        if in(y, inputs["HYDRO_RES_KNOWN_CAP"])
            storage_constraints_dict["StorageMaxDurationConstraint"] = true
            storage_constraints_dict["StorageCapacityConstraint"] = true
        end

        if haskey(gen(y), :min_cap_mw) && gen(y).min_cap_mw>0
            discharge_constraints_dict["MinCapacityConstraint"] = true
        end

        if haskey(gen(y), :max_cap_mw) && gen(y).max_cap_mw>0
            discharge_constraints_dict["MaxCapacityConstraint"] = true
        end


        pmax = inputs["pP_Max"][y, :]

        if length(unique(pmax)) == 1
            gen_availability = unique(pmax)
        else
            gen_availability = Dict("timeseries" => Dict(
                "path" => string("system/hydro_availability_", stage_number, ".csv"),
                "header" => gen(y).resource))

            hydro_availability[!, Symbol(gen(y).resource)] = pmax
        end

        wacc, crp, lifetime = get_wacc_and_crp(gen(y).resource, genx_stage_path)

        push!(hydrores["hydro_res"]["instance_data"],
            Dict(
                "id" => gen(y).resource,
                "storage" => Dict(
                    "can_expand" => in(y, inputs["NEW_CAP"]) && in(y, inputs["HYDRO_RES_KNOWN_CAP"]),
                    "capacity_size" => 1.0 * in(y, inputs["HYDRO_RES_KNOWN_CAP"]),
                    "can_retire" => in(y, inputs["RET_CAP"]) && in(y, inputs["HYDRO_RES_KNOWN_CAP"]),
                    "charge_discharge_ratio" => 1.0,
                    "constraints" => storage_constraints_dict,
                    "existing_capacity" => gen(y).hydro_energy_to_power_ratio * gen(y).existing_cap_mw * in(y, inputs["HYDRO_RES_KNOWN_CAP"]),
                    "fixed_om_cost" => 0.0,
                    "annualized_investment_cost" => 0.0,
                    "long_duration" => gen(y).lds == 1,
                    "loss_fraction" => 0.0,
                    "max_duration" => gen(y).hydro_energy_to_power_ratio * in(y, inputs["HYDRO_RES_KNOWN_CAP"]),
                    "min_outflow_fraction" => gen(y).min_power,
                    "wacc" => wacc,
                    "capital_recovery_period" => crp,
                    "lifetime" => lifetime
                ),
                "edges" => Dict(
                    "discharge_edge" => Dict(
                        "availability" => [1.0],
                        "end_vertex" => "elec_" * gen(y).region,
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "capacity_size" => 1.0,
                        "constraints" => discharge_constraints_dict,
                        "efficiency" => gen(y).eff_down,
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => gen(y).fixed_om_cost_per_mwyr,
                        "annualized_investment_cost" => 0,
                        "max_capacity" => 1e6,
                        "min_capacity" => 0,
                        "ramp_down_fraction" => gen(y).ramp_dn_percentage,
                        "ramp_up_fraction" => gen(y).ramp_up_percentage,
                        "variable_om_cost" => 0,
                        "wacc" => wacc,
                        "capital_recovery_period" => crp,
                        "lifetime" => lifetime
                    ),
                    "inflow_edge" => Dict(
                        "availability" => gen_availability,
                        "start_vertex" => "water_node",
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "capacity_size" => 1.0,
                        "constraints" => inflow_constraints_dict,
                        "efficiency" => 1.0,
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => 0.0,
                        "annualized_investment_cost" => 0.0,
                        "variable_om_cost" => 0.0,
                        "wacc" => wacc,
                        "capital_recovery_period" => crp,
                        "lifetime" => lifetime
                    ),
                    "spill_edge" => Dict(
                        "commodity" => "Electricity",
                        "end_vertex" => "water_node"
                    )
                )
            )
        )

    end

    open(joinpath(macro_case, string("assets/assets_", stage_number, "/hydro.json")), "w") do io
        JSON3.pretty(io, hydrores)
    end

    if !isempty(hydro_availability)
        CSV.write(joinpath(macro_case, string("system/hydro_availability_", stage_number, ".csv")), hydro_availability)
    end
end
