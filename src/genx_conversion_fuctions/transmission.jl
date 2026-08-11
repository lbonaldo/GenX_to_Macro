function make_transmission_json(inputs::Dict, macro_case::AbstractString)

    transmission = Dict(
        "transmission" => Dict(
            "type" => "TransmissionLink",
            "global_data" => Dict(
                "edges" => Dict(
                    "transmission_edge" => Dict(
                        "commodity"=>"Electricity",
                        "has_capacity" => true,
                        "unidirectional" => false,
                    )
                ),
                "transforms" => Dict()
            ),
            "instance_data" => Vector{Dict{AbstractString,Any}}()
        )
    )

    for l in 1:inputs["L"]
        z_start = findfirst(inputs["pNet_Map"][l, :] .== 1);
        z_end = findfirst(inputs["pNet_Map"][l, :] .== -1);

        start_region = inputs["RESOURCES"][findfirst(g.zone==z_start for g in inputs["RESOURCES"])].region;
        end_region = inputs["RESOURCES"][findfirst(g.zone==z_end for g in inputs["RESOURCES"])].region;

        push!(transmission["transmission"]["instance_data"],
            Dict(
                "id" => start_region*"_to_"*end_region,
                "edges" => Dict(
                    "transmission_edge" => Dict(
                        "start_vertex" => "elec_"*start_region,
                        "end_vertex" => "elec_"*end_region,
                        "can_expand" => in(l, inputs["EXPANSION_LINES"]),
                        "can_retire" => false,
                        "constraints" => Dict(
                            "CapacityConstraint" => true,
                            "MaxCapacityConstraint" => true
                        ),
                        "existing_capacity" => inputs["pTrans_Max"][l],
                        "max_capacity" => inputs["pTrans_Max"][l] + inputs["pMax_Line_Reinforcement"][l],
                        "investment_cost" => inputs["pC_Line_Reinforcement"][l],
                        "line_loss_percentage" => inputs["pPercent_Loss"][l]
                    )
                ))
        )

        open(joinpath(macro_case, "assets/transmission.json"), "w") do io
            JSON3.pretty(io, transmission)
        end
    end



end

# ~~~
# Multistage
# ~~~

function make_transmission_json(inputs::Dict, macro_case::AbstractString, genx_stage_path::AbstractString)

    stage_number = get_stage_number(genx_stage_path)

    transmission = Dict(
        "transmission" => Dict(
            "type" => "TransmissionLink",
            "global_data" => Dict(
                "edges" => Dict(
                    "transmission_edge" => Dict(
                        "commodity"=>"Electricity",
                        "has_capacity" => true,
                        "unidirectional" => false,
                    )
                ),
                "transforms" => Dict()
            ),
            "instance_data" => Vector{Dict{AbstractString,Any}}()
        )
    )

    for l in 1:inputs["L"]
        z_start = findfirst(inputs["pNet_Map"][l, :] .== 1);
        z_end = findfirst(inputs["pNet_Map"][l, :] .== -1);

        start_region = inputs["RESOURCES"][findfirst(g.zone==z_start for g in inputs["RESOURCES"])].region;
        end_region = inputs["RESOURCES"][findfirst(g.zone==z_end for g in inputs["RESOURCES"])].region;

        push!(transmission["transmission"]["instance_data"],
            Dict(
                "id" => start_region*"_to_"*end_region,
                "edges" => Dict(
                    "transmission_edge" => Dict(
                        "start_vertex" => "elec_"*start_region,
                        "end_vertex" => "elec_"*end_region,
                        "can_expand" => in(l, inputs["EXPANSION_LINES"]),
                        "can_retire" => false,
                        "constraints" => Dict(
                            "CapacityConstraint" => true,
                            "MaxCapacityConstraint" => true
                        ),
                        "existing_capacity" => inputs["pTrans_Max"][l],
                        "max_capacity" => inputs["pTrans_Max"][l] + inputs["pMax_Line_Reinforcement"][l],
                        "annualized_investment_cost" => inputs["pC_Line_Reinforcement"][l],
                        "line_loss_percentage" => inputs["pPercent_Loss"][l]
                    )
                ))
        )

        open(joinpath(macro_case, string("assets/assets_", stage_number, "/transmission.json")), "w") do io
            JSON3.pretty(io, transmission)
        end
    end



end