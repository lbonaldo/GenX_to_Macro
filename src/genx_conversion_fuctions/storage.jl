"""
    make_storage_json(inputs, setup, t)

Write the Battery assets: one storage component plus a discharge and a charge edge per GenX
storage resource. Charge capacity is sized separately only for asymmetric storage.
"""
function make_storage_json(inputs::Dict, setup::Dict, t::Target)
    storage = Dict("elec_stor" => Dict(
        "type" => "Battery",
        "global_data" => Dict(
            "storage" => Dict("commodity" => "Electricity"),
            "edges" => Dict(
                "discharge_edge" => Dict("commodity" => "Electricity", "unidirectional" => true),
                "charge_edge" => Dict("commodity" => "Electricity", "unidirectional" => true))),
        "instance_data" => Vector{Dict{AbstractString, Any}}()))

    gen = inputs["RESOURCES"]
    for y in inputs["STOR_ALL"]
        r = gen[y]
        asymmetric = y in inputs["STOR_ASYMMETRIC"]
        long_duration = get(r, :lds, 0) == 1

        discharge_constraints = capacity_constraints!(
            Dict("CapacityConstraint" => true, "StorageDischargeLimitConstraint" => true),
            GenX.min_cap_mw(r), GenX.max_cap_mw(r))
        storage_constraints = capacity_constraints!(
            Dict("BalanceConstraint" => true, "StorageCapacityConstraint" => true),
            GenX.min_cap_mwh(r), GenX.max_cap_mwh(r))
        # GenX limits charging of every storage resource to the free energy capacity
        # (storage_all.jl), which Macro only applies when this constraint is set.
        charge_constraints = Dict{String, Any}("StorageChargeLimitConstraint" => true)

        if setup["LDSAdditionalConstraints"] == 1 && long_duration
            storage_constraints["LongDurationStorageImplicitMinMaxConstraint"] = true
        end
        r.min_duration > 0 && (storage_constraints["StorageMinDurationConstraint"] = true)
        r.max_duration > 0 && (storage_constraints["StorageMaxDurationConstraint"] = true)
        if asymmetric
            charge_constraints["CapacityConstraint"] = true
            capacity_constraints!(charge_constraints,
                GenX.min_charge_cap_mw(r), GenX.max_charge_cap_mw(r))
        else
            storage_constraints["StorageSymmetricCapacityConstraint"] = true
        end

        storage_data = Dict{String, Any}(
            "can_expand" => y in inputs["NEW_CAP_ENERGY"],
            "capacity_size" => 1.0,
            "can_retire" => y in inputs["RET_CAP_ENERGY"],
            "charge_discharge_ratio" => 1.0,
            "constraints" => storage_constraints,
            "existing_capacity" => r.existing_cap_mwh,
            "fixed_om_cost" => r.fixed_om_cost_per_mwhyr,
            "annualized_investment_cost" => r.inv_cost_per_mwhyr,
            "long_duration" => long_duration,
            "loss_fraction" => r.self_disch,
            "max_capacity" => GenX.max_cap_mwh(r),
            "max_duration" => r.max_duration,
            "max_storage_level" => 1.0,
            "min_capacity" => max(0.0, GenX.min_cap_mwh(r)),
            "min_duration" => r.min_duration,
            "min_storage_level" => 0.0)
        merge!(storage_data,
            multistage_fields(r, t; min_retired = GenX.min_retired_energy_cap_mw(r)))

        discharge_edge = Dict{String, Any}(
            "end_vertex" => "elec_" * r.region,
            "can_expand" => y in inputs["NEW_CAP"],
            "can_retire" => y in inputs["RET_CAP"],
            "capacity_size" => 1.0,
            "constraints" => discharge_constraints,
            "efficiency" => r.eff_down,
            "existing_capacity" => r.existing_cap_mw,
            "fixed_om_cost" => r.fixed_om_cost_per_mwyr,
            "has_capacity" => true,
            "annualized_investment_cost" => r.inv_cost_per_mwyr,
            "max_capacity" => GenX.max_cap_mw(r),
            "min_capacity" => max(0.0, GenX.min_cap_mw(r)),
            "variable_om_cost" => r.var_om_cost_per_mwh)
        merge!(discharge_edge, multistage_fields(r, t; min_retired = GenX.min_retired_cap_mw(r)))

        charge_edge = Dict{String, Any}(
            "start_vertex" => "elec_" * r.region,
            "can_expand" => y in inputs["NEW_CAP_CHARGE"],
            "can_retire" => y in inputs["RET_CAP_CHARGE"],
            "capacity_size" => 1.0,
            "constraints" => charge_constraints,
            "efficiency" => r.eff_up,
            "existing_capacity" => GenX.existing_charge_cap_mw(r),
            "fixed_om_cost" => GenX.fixed_om_cost_charge_per_mwyr(r),
            "has_capacity" => asymmetric,
            "annualized_investment_cost" => GenX.inv_cost_charge_per_mwyr(r),
            "max_capacity" => max(0.0, GenX.max_charge_cap_mw(r)),
            "min_capacity" => max(0.0, GenX.min_charge_cap_mw(r)),
            "variable_om_cost" => r.var_om_cost_per_mwh_in)
        merge!(charge_edge,
            multistage_fields(r, t; min_retired = GenX.min_retired_charge_cap_mw(r)))

        push!(storage["elec_stor"]["instance_data"], Dict(
            "id" => r.resource,
            "storage" => storage_data,
            "edges" => Dict("discharge_edge" => discharge_edge, "charge_edge" => charge_edge)))
    end

    write_asset_json(case_path(t, asset_file(t, "storage")), storage)
    return storage
end
