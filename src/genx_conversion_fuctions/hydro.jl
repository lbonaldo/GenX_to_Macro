"""
    make_hydro_json(inputs, setup, t)

Write the HydroRes assets: a reservoir fed by an inflow edge, discharging to the grid and
spilling to the water node. Resources that can neither be built nor retired and have no
existing capacity are skipped.
"""
function make_hydro_json(inputs::Dict, setup::Dict, t::Target)
    hydrores = Dict("hydro_res" => Dict(
        "type" => "HydroRes",
        "global_data" => Dict(
            "storage" => Dict("commodity" => "Electricity"),
            "edges" => Dict(
                "discharge_edge" => Dict("commodity" => "Electricity",
                    "unidirectional" => true, "has_capacity" => true),
                "spill_edge" => Dict("commodity" => "Electricity",
                    "unidirectional" => true, "has_capacity" => false),
                "inflow_edge" => Dict("commodity" => "Electricity",
                    "unidirectional" => true, "has_capacity" => true))),
        "instance_data" => Vector{Dict{AbstractString, Any}}()))

    gen = inputs["RESOURCES"]
    availability = DataFrame()
    for y in inputs["HYDRO_RES"]
        r = gen[y]
        if !(y in inputs["RET_CAP"]) && !(y in inputs["NEW_CAP"]) && r.existing_cap_mw == 0
            continue
        end
        known_capacity = y in inputs["HYDRO_RES_KNOWN_CAP"]

        discharge_constraints = capacity_constraints!(Dict(
                "CapacityConstraint" => true,
                "StorageDischargeLimitConstraint" => true,
                "RampingLimitConstraint" => true),
            GenX.min_cap_mw(r), GenX.max_cap_mw(r))
        storage_constraints = Dict(
            "BalanceConstraint" => true,
            "StorageChargeDischargeRatioConstraint" => true,
            "MinStorageOutflowConstraint" => true)
        if setup["LDSAdditionalConstraints"] == 1 && get(r, :lds, 0) == 1
            storage_constraints["LongDurationStorageImplicitMinMaxConstraint"] = true
        end
        if known_capacity
            storage_constraints["StorageMaxDurationConstraint"] = true
            storage_constraints["StorageCapacityConstraint"] = true
        end

        storage_data = Dict{String, Any}(
            "can_expand" => y in inputs["NEW_CAP"] && known_capacity,
            "capacity_size" => 1.0 * known_capacity,
            "can_retire" => y in inputs["RET_CAP"] && known_capacity,
            "charge_discharge_ratio" => 1.0,
            "constraints" => storage_constraints,
            "existing_capacity" => r.hydro_energy_to_power_ratio * r.existing_cap_mw * known_capacity,
            "fixed_om_cost" => 0.0,
            "annualized_investment_cost" => 0.0,
            "long_duration" => get(r, :lds, 0) == 1,
            "loss_fraction" => 0.0,
            "max_duration" => r.hydro_energy_to_power_ratio * known_capacity,
            "min_outflow_fraction" => r.min_power)
        merge!(storage_data, multistage_fields(r, t))

        discharge_edge = Dict{String, Any}(
            "availability" => [1.0],
            "end_vertex" => "elec_" * r.region,
            "can_expand" => y in inputs["NEW_CAP"],
            "can_retire" => y in inputs["RET_CAP"],
            "capacity_size" => 1.0,
            "constraints" => discharge_constraints,
            "efficiency" => r.eff_down,
            "existing_capacity" => r.existing_cap_mw,
            "fixed_om_cost" => r.fixed_om_cost_per_mwyr,
            "annualized_investment_cost" => GenX.inv_cost_per_mwyr(r),
            "max_capacity" => GenX.max_cap_mw(r),
            "min_capacity" => max(0.0, GenX.min_cap_mw(r)),
            "ramp_down_fraction" => r.ramp_dn_percentage,
            "ramp_up_fraction" => r.ramp_up_percentage,
            "variable_om_cost" => GenX.var_om_cost_per_mwh(r))
        merge!(discharge_edge, multistage_fields(r, t; min_retired = GenX.min_retired_cap_mw(r)))

        inflow_edge = Dict{String, Any}(
            "availability" => availability!(availability, r, inputs["pP_Max"][y, :], t,
                "hydro_availability"),
            "start_vertex" => "water_node",
            "can_expand" => y in inputs["NEW_CAP"],
            "can_retire" => y in inputs["RET_CAP"],
            "capacity_size" => 1.0,
            "constraints" => Dict("MustRunConstraint" => true),
            "efficiency" => 1.0,
            "existing_capacity" => r.existing_cap_mw,
            "fixed_om_cost" => 0.0,
            "annualized_investment_cost" => 0.0,
            "variable_om_cost" => 0.0)
        merge!(inflow_edge, multistage_fields(r, t))

        push!(hydrores["hydro_res"]["instance_data"], Dict(
            "id" => r.resource,
            "storage" => storage_data,
            "edges" => Dict(
                "discharge_edge" => discharge_edge,
                "inflow_edge" => inflow_edge,
                "spill_edge" => Dict("commodity" => "Electricity", "end_vertex" => "water_node"))))
    end

    write_asset_json(case_path(t, asset_file(t, "hydro")), hydrores)
    write_timeseries_csv(case_path(t, system_file(t, "hydro_availability", "csv")), availability)
    return hydrores
end
