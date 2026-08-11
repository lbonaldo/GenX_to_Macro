function make_vre_json(inputs::Dict, macro_case::AbstractString)
    VRE = inputs["VRE"];

    vre = Dict("VRE" => Dict(
        "type"=>"VRE",
        "global_data"=>Dict(
            "transforms" => Dict(
                "timedata" => "Electricity"
            ),
            "edges" => Dict(
                "edge" => Dict(
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
    vre_availability = DataFrame();
    for y in VRE

        pmax = inputs["pP_Max"][y, :];

        if length(unique(pmax))==1
            gen_availability = unique(pmax)
        else
            gen_availability = Dict("timeseries" => Dict(
                "path" => "system/vre_availability.csv",
                "header" => gen(y).resource))

            vre_availability[!, Symbol(gen(y).resource)] = pmax;
        end


        constraints_dict = Dict("CapacityConstraint" => true)

        if haskey(gen(y), :min_cap_mw) && gen(y).min_cap_mw >0
            constraints_dict["MinCapacityConstraint"] = true
        end

        if gen(y).max_cap_mw > 0
            constraints_dict["MaxCapacityConstraint"] = true
        end

        push!(vre["VRE"]["instance_data"],
            Dict(
                "id" => gen(y).resource,
                "edges" => Dict(
                    "edge" => Dict(
                        "end_vertex" => "elec_" * gen(y).region,
                        "commodity" => "Electricity",
                        "constraints" => constraints_dict,
                        "availability" => gen_availability,
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "capacity_size" => 1.0,
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => gen(y).fixed_om_cost_per_mwyr,
                        "annualized_investment_cost" => gen(y).inv_cost_per_mwyr,
                        "max_capacity" => gen(y).max_cap_mw,
                        "min_capacity" => 0,
                        "variable_om_cost" => 0,
                    )
                )
            )
        )
    end

    open(joinpath(macro_case, "assets/vre.json"), "w") do io
        JSON3.pretty(io, vre)
    end

    if !isempty(vre_availability)
        CSV.write(joinpath(macro_case, "system/vre_availability.csv"), vre_availability)
    end

    return vre

end

# ~~~
# Multistage
# ~~~

function make_vre_json(inputs::Dict, macro_case::AbstractString, genx_stage_path::AbstractString)

    stage_number = get_stage_number(genx_stage_path)

    VRE = inputs["VRE"];

    vre = Dict("VRE" => Dict(
        "type"=>"VRE",
        "global_data"=>Dict(
            "transforms" => Dict(
                "timedata" => "Electricity"
            ),
            "edges" => Dict(
                "edge" => Dict(
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
    vre_availability = DataFrame();
    for y in VRE

        pmax = inputs["pP_Max"][y, :];

        if length(unique(pmax))==1
            gen_availability = unique(pmax)
        else
            gen_availability = Dict("timeseries" => Dict(
                "path" => string("system/vre_availability_", stage_number, ".csv"),
                "header" => gen(y).resource))

            vre_availability[!, Symbol(gen(y).resource)] = pmax;
        end


        constraints_dict = Dict("CapacityConstraint" => true)

        if haskey(gen(y), :min_cap_mw) && gen(y).min_cap_mw >0
            constraints_dict["MinCapacityConstraint"] = true
        end

        if gen(y).max_cap_mw > 0
            constraints_dict["MaxCapacityConstraint"] = true
        end

        wacc, crp, lifetime, min_ret_cap = get_wacc_and_crp(gen(y).resource, genx_stage_path)

        push!(vre["VRE"]["instance_data"],
            Dict(
                "id" => gen(y).resource,
                "edges" => Dict(
                    "edge" => Dict(
                        "end_vertex" => "elec_" * gen(y).region,
                        "commodity" => "Electricity",
                        "constraints" => constraints_dict,
                        "availability" => gen_availability,
                        "can_retire" => in(y, inputs["RET_CAP"]),
                        "can_expand" => in(y, inputs["NEW_CAP"]),
                        "capacity_size" => 1.0,
                        "existing_capacity" => gen(y).existing_cap_mw,
                        "fixed_om_cost" => gen(y).fixed_om_cost_per_mwyr,
                        "annualized_investment_cost" => gen(y).inv_cost_per_mwyr,
                        "max_capacity" => gen(y).max_cap_mw,
                        "min_capacity" => 0,
                        "variable_om_cost" => 0,
                        "wacc" => wacc,
                        "capital_recovery_period" => crp,
                        "lifetime" => lifetime,
                        "min_retired_capacity" => min_ret_cap
                    )
                )
            )
        )
    end

    open(joinpath(macro_case, string("assets/assets_", stage_number, "/vre.json")), "w") do io
        JSON3.pretty(io, vre)
    end

    if !isempty(vre_availability)
        CSV.write(joinpath(macro_case, string("system/vre_availability_", stage_number, ".csv")), vre_availability)
    end

    return vre

end