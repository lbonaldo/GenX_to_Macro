"""
    make_mustrun_json(inputs, setup, t)

Write the MustRun assets and their availability profiles. Resources that can neither be
built nor retired and have no existing capacity are skipped.
"""
function make_mustrun_json(inputs::Dict, setup::Dict, t::Target)
    mustrun = Dict("MustRun" => Dict(
        "type" => "MustRun",
        "global_data" => Dict(
            "transforms" => Dict("timedata" => "Electricity"),
            "edges" => Dict("elec_edge" => Dict(
                "commodity" => "Electricity",
                "unidirectional" => true,
                "has_capacity" => true))),
        "instance_data" => Vector{Dict{AbstractString, Any}}()))

    gen = inputs["RESOURCES"]
    availability = DataFrame()
    for y in inputs["MUST_RUN"]
        r = gen[y]
        if !(y in inputs["RET_CAP"]) && !(y in inputs["NEW_CAP"]) && r.existing_cap_mw == 0
            continue
        end
        constraints = capacity_constraints!(Dict("MustRunConstraint" => true),
            GenX.min_cap_mw(r), GenX.max_cap_mw(r))

        edge = Dict{String, Any}(
            "end_vertex" => "elec_" * r.region,
            "commodity" => "Electricity",
            "constraints" => constraints,
            "availability" => availability!(availability, r, inputs["pP_Max"][y, :], t,
                "mustrun_availability"),
            "can_retire" => y in inputs["RET_CAP"],
            "can_expand" => y in inputs["NEW_CAP"],
            "capacity_size" => 1.0, # GenX assumes a capacity size of 1 for must-run resources
            "existing_capacity" => r.existing_cap_mw,
            "fixed_om_cost" => r.fixed_om_cost_per_mwyr,
            "annualized_investment_cost" => GenX.inv_cost_per_mwyr(r),
            "max_capacity" => GenX.max_cap_mw(r),
            "min_capacity" => max(0.0, GenX.min_cap_mw(r)),
            "variable_om_cost" => GenX.var_om_cost_per_mwh(r))
        merge!(edge, multistage_fields(r, t; min_retired = GenX.min_retired_cap_mw(r)))

        push!(mustrun["MustRun"]["instance_data"], Dict("id" => r.resource,
            "edges" => Dict("elec_edge" => edge)))
    end

    write_asset_json(case_path(t, asset_file(t, "mustrun")), mustrun)
    write_timeseries_csv(case_path(t, system_file(t, "mustrun_availability", "csv")), availability)
    return mustrun
end
