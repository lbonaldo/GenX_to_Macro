"""
    make_vre_json(inputs, setup, t)

Write the VRE assets and their availability profiles.
"""
function make_vre_json(inputs::Dict, setup::Dict, t::Target)
    vre = Dict("VRE" => Dict(
        "type" => "VRE",
        "global_data" => Dict(
            "transforms" => Dict("timedata" => "Electricity"),
            "edges" => Dict("edge" => Dict(
                "commodity" => "Electricity",
                "unidirectional" => true,
                "has_capacity" => true))),
        "instance_data" => Vector{Dict{AbstractString, Any}}()))

    gen = inputs["RESOURCES"]
    availability = DataFrame()
    for y in inputs["VRE"]
        r = gen[y]
        constraints = capacity_constraints!(Dict("CapacityConstraint" => true),
            GenX.min_cap_mw(r), GenX.max_cap_mw(r))

        edge = Dict{String, Any}(
            "end_vertex" => "elec_" * r.region,
            "commodity" => "Electricity",
            "constraints" => constraints,
            "availability" => availability!(availability, r, inputs["pP_Max"][y, :], t,
                "vre_availability"),
            "can_retire" => y in inputs["RET_CAP"],
            "can_expand" => y in inputs["NEW_CAP"],
            "capacity_size" => 1.0,
            "existing_capacity" => r.existing_cap_mw,
            "fixed_om_cost" => r.fixed_om_cost_per_mwyr,
            "annualized_investment_cost" => r.inv_cost_per_mwyr,
            "max_capacity" => GenX.max_cap_mw(r),
            "min_capacity" => max(0.0, GenX.min_cap_mw(r)),
            "variable_om_cost" => GenX.var_om_cost_per_mwh(r))
        merge!(edge, multistage_fields(r, t; min_retired = GenX.min_retired_cap_mw(r)))

        push!(vre["VRE"]["instance_data"], Dict("id" => r.resource, "edges" => Dict("edge" => edge)))
    end

    write_asset_json(case_path(t, asset_file(t, "vre")), vre)
    write_timeseries_csv(case_path(t, system_file(t, "vre_availability", "csv")), availability)
    return vre
end
