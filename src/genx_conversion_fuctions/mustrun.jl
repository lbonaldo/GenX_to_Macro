function make_mustrun_json(inputs::Dict, macro_case::AbstractString)
    MUST_RUN = inputs["MUST_RUN"];
    mustrun = Dict("MustRun" => Dict(
        "type"=>"MustRun",
        "global_data"=>Dict(
            "transforms" => Dict(
                "timedata" => "Electricity"
            ),
            "edges" => Dict(
                "elec_edge" => Dict(
                    "commodity" => "Electricity",
                    "unidirectional" => true,
                    "has_capacity" => true,
                ),
            ),
        ),
        "instance_data"=>Vector{Dict{AbstractString,Any}}()
    )
    )
    gen(y) = inputs["RESOURCES"][y];
    mustrun_availability = DataFrame();
    for y in MUST_RUN

        if (!in(y, inputs["RET_CAP"])) && (!in(y, inputs["NEW_CAP"])) && (gen(y).existing_cap_mw == 0)
            continue
        end

        pmax = inputs["pP_Max"][y, :];

        if length(unique(pmax))==1
            gen_availability = unique(pmax)
        else
            gen_availability = Dict("timeseries" => Dict(
                "path" => "system/mustrun_availability.csv",
                "header" => gen(y).resource))

            mustrun_availability[!, Symbol(gen(y).resource)] = pmax;
        end


        constraints_dict = Dict("MustRunConstraint" => true)

        if gen(y).min_cap_mw > 0
            constraints_dict["MinCapacityConstraint"] = true
        end

        if gen(y).max_cap_mw > 0
            constraints_dict["MaxCapacityConstraint"] = true
        end

        push!(mustrun["MustRun"]["instance_data"],
            Dict(
                "id" => gen(y).resource,
                "edges" => Dict(
                    "elec_edge" => Dict(
                        "end_vertex" => "elec_" * gen(y).region,
                        "commodity" => "Electricity",
                        "constraints" => constraints_dict,
                        "availability" => gen_availability,
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "capacity_size" => 1.0, ### Note: GenX internally assumes capacity_size = 1.0 for must run generators
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => gen(y).fixed_om_cost_per_mwyr,
                        "annualized_investment_cost" => gen(y).inv_cost_per_mwyr,
                        "max_capacity" => gen(y).max_cap_mw,
                        "min_capacity" => gen(y).min_cap_mw,
                        "variable_om_cost" => gen(y).var_om_cost_per_mwh,
                    )
                )
            )
        )
    end

    open(joinpath(macro_case, "assets/mustrun.json"), "w") do io
        JSON3.pretty(io, mustrun)
    end

    if !isempty(mustrun_availability)
        CSV.write(joinpath(macro_case, "system/mustrun_availability.csv"), mustrun_availability)
    end

end

# ~~~~
# Multistage
# ~~~~

function make_mustrun_json(inputs::Dict, macro_case::AbstractString, genx_stage_path::AbstractString)

    stage_number = get_stage_number(genx_stage_path)

    MUST_RUN = inputs["MUST_RUN"];
    mustrun = Dict("MustRun" => Dict(
        "type"=>"MustRun",
        "global_data"=>Dict(
            "transforms" => Dict(
                "timedata" => "Electricity"
            ),
            "edges" => Dict(
                "elec_edge" => Dict(
                    "commodity" => "Electricity",
                    "unidirectional" => true,
                    "has_capacity" => true,
                ),
            ),
        ),
        "instance_data"=>Vector{Dict{AbstractString,Any}}()
    )
    )
    gen(y) = inputs["RESOURCES"][y];
    mustrun_availability = DataFrame();
    for y in MUST_RUN

        if (!in(y, inputs["RET_CAP"])) && (!in(y, inputs["NEW_CAP"])) && (gen(y).existing_cap_mw == 0)
            continue
        end

        pmax = inputs["pP_Max"][y, :];

        if length(unique(pmax))==1
            gen_availability = unique(pmax)
        else
            gen_availability = Dict("timeseries" => Dict(
                "path" => "system/mustrun_availability.csv",
                "header" => gen(y).resource))

            mustrun_availability[!, Symbol(gen(y).resource)] = pmax;
        end


        constraints_dict = Dict("MustRunConstraint" => true)

        if haskey(gen(y), :min_cap_mw) && gen(y).min_cap_mw > 0
            constraints_dict["MinCapacityConstraint"] = true
        end

        if haskey(gen(y), :max_cap_mw) && gen(y).max_cap_mw >0
            constraints_dict["MaxCapacityConstraint"] = true
        end

        wacc, crp, lifetime = get_wacc_and_crp(gen(y).resource, genx_stage_path)

        push!(mustrun["MustRun"]["instance_data"],
            Dict(
                "id" => gen(y).resource,
                "edges" => Dict(
                    "elec_edge" => Dict(
                        "end_vertex" => "elec_" * gen(y).region,
                        "commodity" => "Electricity",
                        "constraints" => constraints_dict,
                        "availability" => gen_availability,
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "capacity_size" => 1.0, ### Note: GenX internally assumes capacity_size = 1.0 for must run generators
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => gen(y).fixed_om_cost_per_mwyr,
                        "annualized_investment_cost" => 0,
                        "max_capacity" => 1e6,
                        "min_capacity" => 0,
                        "variable_om_cost" => 0,
                        "wacc" => wacc,
                        "capital_recovery_period" => crp,
                        "lifetime" => lifetime
                    )
                )
            )
        )
    end

    open(joinpath(macro_case, string("assets/assets_", stage_number, "/mustrun.json")), "w") do io
        JSON3.pretty(io, mustrun)
    end

    if !isempty(mustrun_availability)
        CSV.write(joinpath(macro_case, "system/mustrun_availability.csv"), mustrun_availability)
    end

end