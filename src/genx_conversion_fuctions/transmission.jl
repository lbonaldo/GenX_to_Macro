"""
    make_transmission_json(inputs, setup, t)

Write the TransmissionLink assets, one per GenX line.

Line limits follow GenX. Without network expansion a line keeps its existing capacity. With
it, a single-stage case may add up to `Line_Max_Reinforcement_MW`; a multi-stage case caps the
total at `Line_Max_Flow_Possible_MW` and the addition in each stage at
`Line_Max_Reinforcement_MW`, and passes the capital recovery period, which Macro would
otherwise default to 1 year.
"""
function make_transmission_json(inputs::Dict, setup::Dict, t::Target)
    transmission = Dict("transmission" => Dict(
        "type" => "TransmissionLink",
        "global_data" => Dict(
            "edges" => Dict("transmission_edge" => Dict(
                "commodity" => "Electricity",
                "has_capacity" => true,
                "unidirectional" => false)),
            "transforms" => Dict()),
        "instance_data" => Vector{Dict{AbstractString, Any}}()))

    expansion = setup["NetworkExpansion"] == 1
    # GenX loads a loss fraction only for linear losses (Trans_Loss_Segments = 1); with 0 the
    # lines are lossless. Quadratic losses are rejected by check_supported. Macro takes the
    # loss as `loss_fraction` and removes it at the receiving end, whereas GenX charges half
    # to each end zone: total losses match, line flows differ slightly.
    losses = setup["Trans_Loss_Segments"] == 1 ? inputs["pPercent_Loss"] : zeros(inputs["L"])
    # Asset ids are "<start>_to_<end>"; parallel lines between the same zones also get the
    # line number, since Macro ids must be unique.
    ids = map(1:inputs["L"]) do l
        start_region = zone_region(inputs, findfirst(==(1), inputs["pNet_Map"][l, :]))
        end_region = zone_region(inputs, findfirst(==(-1), inputs["pNet_Map"][l, :]))
        (start_region, end_region, start_region * "_to_" * end_region)
    end
    for l in 1:inputs["L"]
        start_region, end_region, id = ids[l]
        count(x -> x[3] == id, ids) > 1 && (id *= "_line$l")

        constraints = Dict("CapacityConstraint" => true, "MaxCapacityConstraint" => true)
        edge = Dict{String, Any}(
            "start_vertex" => "elec_" * start_region,
            "end_vertex" => "elec_" * end_region,
            "can_expand" => expansion && l in inputs["EXPANSION_LINES"],
            "can_retire" => false,
            "constraints" => constraints,
            "existing_capacity" => inputs["pTrans_Max"][l],
            "loss_fraction" => losses[l])
        if !expansion
            edge["max_capacity"] = inputs["pTrans_Max"][l]
        elseif is_multistage(t)
            constraints["MaxNewCapacityConstraint"] = true
            edge["max_capacity"] = inputs["pLine_Max_Flow_Possible_MW"][l]
            edge["max_new_capacity"] = inputs["pMax_Line_Reinforcement"][l]
            edge["annualized_investment_cost"] = inputs["pC_Line_Reinforcement"][l]
            edge["capital_recovery_period"] = round(Int, inputs["Capital_Recovery_Period_Trans"][l])
        else
            edge["max_capacity"] = inputs["pTrans_Max"][l] + inputs["pMax_Line_Reinforcement"][l]
            edge["annualized_investment_cost"] = inputs["pC_Line_Reinforcement"][l]
        end

        push!(transmission["transmission"]["instance_data"], Dict(
            "id" => id,
            "edges" => Dict("transmission_edge" => edge)))
    end

    write_asset_json(case_path(t, asset_file(t, "transmission")), transmission)
    return transmission
end
