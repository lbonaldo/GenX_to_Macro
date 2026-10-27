"""
    make_thermal_json(inputs, setup, t)

Write the ThermalPower assets: thermal plants without carbon capture.
"""
make_thermal_json(inputs::Dict, setup::Dict, t::Target) =
    write_thermal(inputs, t, setdiff(inputs["THERM_ALL"], inputs["CCS"]), false)

"""
    make_thermal_ccs_json(inputs, setup, t)

Write the ThermalPowerCCS assets: thermal plants with carbon capture. As in GenX, the captured
share of the fuel's CO2 leaves the plant on its own edge and costs the plant's disposal cost
per tonne; the rest is emitted like any thermal plant.
"""
make_thermal_ccs_json(inputs::Dict, setup::Dict, t::Target) =
    write_thermal(inputs, t, ccs_thermal(inputs), true)

function write_thermal(inputs::Dict, t::Target, ids, ccs::Bool)
    asset_type = ccs ? "ThermalPowerCCS" : "ThermalPower"
    availability_base = ccs ? "ccs_thermal_availability" : "thermal_availability"

    edges = Dict(
        "elec_edge" => Dict("unidirectional" => true, "has_capacity" => true),
        "fuel_edge" => Dict("unidirectional" => true, "has_capacity" => false),
        "co2_edge" => Dict("unidirectional" => true, "has_capacity" => false))
    if ccs
        edges["co2_captured_edge"] = Dict("unidirectional" => true, "has_capacity" => false)
    end
    thermal = Dict(asset_type => Dict(
        "type" => asset_type,
        "global_data" => Dict(
            "transforms" => Dict("constraints" => Dict("BalanceConstraint" => true)),
            "edges" => edges),
        "instance_data" => Vector{Dict{AbstractString, Any}}()))

    gen = inputs["RESOURCES"]
    availability = DataFrame()
    for y in ids
        r = gen[y]
        fuel_type = fuel_commodity(r.fuel)
        fuel_type === nothing &&
            error("$(r.resource) uses fuel '$(r.fuel)', which has no Macro commodity in the " *
                  "converter; only natural gas, coal and uranium are supported.")

        constraints = Dict("CapacityConstraint" => true, "RampingLimitConstraint" => true)
        if y in inputs["THERM_COMMIT"]
            constraints["MinUpTimeConstraint"] = true
            constraints["MinDownTimeConstraint"] = true
        end
        r.min_power > 0 && (constraints["MinFlowConstraint"] = true)
        capacity_constraints!(constraints, GenX.min_cap_mw(r), GenX.max_cap_mw(r))

        # Rates per MWh of fuel. As in GenX, the biomass share of the fuel's CO2 is not
        # emitted, and a CCS plant captures its capture fraction (also of start-up fuel, where
        # GenX uses CO2_Capture_Fraction_Startup; the converter warns when the two differ).
        fuel_co2 = inputs["fuel_CO2"][r.fuel] / conv_mmbtu_to_mwh
        capture = ccs ? GenX.co2_capture_fraction(r) : 0.0
        transforms = Dict{String, Any}(
            "timedata" => fuel_type,
            "emission_rate" => (1 - GenX.biomass(r) - capture) * fuel_co2,
            "fuel_consumption" => conv_mmbtu_to_mwh * r.heat_rate_mmbtu_per_mwh)
        ccs && (transforms["capture_rate"] = capture * fuel_co2)

        elec_edge = Dict{String, Any}(
            "end_vertex" => "elec_" * r.region,
            "commodity" => "Electricity",
            "uc" => y in inputs["THERM_COMMIT"],
            "constraints" => constraints,
            "availability" => availability!(availability, r, inputs["pP_Max"][y, :], t,
                availability_base),
            "can_retire" => y in inputs["RET_CAP"],
            "can_expand" => y in inputs["NEW_CAP"],
            "capacity_size" => r.cap_size,
            "existing_capacity" => r.existing_cap_mw,
            "fixed_om_cost" => r.fixed_om_cost_per_mwyr,
            "annualized_investment_cost" => r.inv_cost_per_mwyr,
            "max_capacity" => GenX.max_cap_mw(r),
            "min_capacity" => max(0.0, GenX.min_cap_mw(r)),
            "min_flow_fraction" => r.min_power,
            "ramp_down_fraction" => r.ramp_dn_percentage,
            "ramp_up_fraction" => r.ramp_up_percentage,
            "variable_om_cost" => r.var_om_cost_per_mwh,
            "min_down_time" => r.down_time,
            "min_up_time" => r.up_time,
            "startup_cost" => r.start_cost_per_mw,
            "startup_fuel_consumption" => conv_mmbtu_to_mwh * r.start_fuel_mmbtu_per_mw)
        merge!(elec_edge, multistage_fields(r, t; min_retired = GenX.min_retired_cap_mw(r)))

        instance_edges = Dict{String, Any}(
            "elec_edge" => elec_edge,
            "fuel_edge" => Dict("commodity" => fuel_type, "start_vertex" => r.fuel),
            "co2_edge" => Dict("commodity" => "CO2", "end_vertex" => co2_sink(inputs, r.zone)))
        if ccs
            instance_edges["co2_captured_edge"] = Dict(
                "commodity" => "CO2Captured",
                "end_vertex" => CO2_CAPTURED_SINK,
                "variable_om_cost" => GenX.ccs_disposal_cost_per_metric_ton(r))
        end

        push!(thermal[asset_type]["instance_data"], Dict(
            "id" => r.resource,
            "transforms" => transforms,
            "edges" => instance_edges))
    end

    write_asset_json(case_path(t, asset_file(t, ccs ? "thermal_ccs" : "thermal")), thermal)
    write_timeseries_csv(case_path(t, system_file(t, availability_base, "csv")), availability)
    return thermal
end
