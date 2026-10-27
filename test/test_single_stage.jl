# Single-stage conversions of GenX example systems. Expected values are taken from the GenX
# inputs, so the tests check the mapping rather than restating numbers.

const MWH_PER_MMBTU = G2M.conv_mmbtu_to_mwh

@testset "Example 1: no CO2 cap, line losses" begin
    case = example_case("1_three_zones")
    out = @test_logs (:warn, r"MinCapReq") match_mode = :any convert_case(case)
    setup, inputs = load_quietly(case)

    system_data = read_json(out, "system_data.json")
    @test system_data[:assets][:path] == "assets"
    @test haskey(system_data, :locations)  # Macro requires the entry, not the file
    @test !isfile(joinpath(out, "settings", "case_settings.json"))
    @test read_json(out, "system/commodities.json")[:commodities] == ["Electricity", "NaturalGas", "CO2"]
    @test !isfile(joinpath(out, "assets", "hydro.json"))  # no hydro in the case
    time_data = read_json(out, "system/time_data.json")
    @test time_data[:TotalHoursModeled] == round(Int, sum(inputs["Weights"]))  # also without TDR
    @test !haskey(time_data, :SubPeriodMap)

    # Without a cap, every plant emits to the one uncapped CO2 node.
    co2 = only(g for g in node_groups(out) if g[:type] == "CO2")
    @test [n[:id] for n in co2[:instance_data]] == [G2M.UNCAPPED_CO2_SINK]
    @test !haskey(co2[:global_data][:constraints], :CO2CapConstraint)
    thermal = instances(out, "assets/thermal.json", :ThermalPower)
    @test all(p[:edges][:co2_edge][:end_vertex] == G2M.UNCAPPED_CO2_SINK for p in thermal)
    for p in thermal
        r = inputs["RESOURCES"][findfirst(g -> g.resource == p[:id], inputs["RESOURCES"])]
        @test p[:transforms][:emission_rate] ≈
              (1 - GenX.biomass(r)) * inputs["fuel_CO2"][r.fuel] / MWH_PER_MMBTU
        @test !haskey(p[:edges][:elec_edge], :capital_recovery_period)  # multi-stage only
    end

    # Line losses use Macro's loss_fraction field.
    lines = instances(out, "assets/transmission.json", :transmission)
    @test [l[:edges][:transmission_edge][:loss_fraction] for l in lines] ≈ inputs["pPercent_Loss"]
    @test all(l[:edges][:transmission_edge][:max_capacity] ≈
              inputs["pTrans_Max"][i] + inputs["pMax_Line_Reinforcement"][i]
              for (i, l) in enumerate(lines))

    # Every battery's charging is limited by its free energy capacity, as in GenX.
    storage = instances(out, "assets/storage.json", :elec_stor)
    @test all(haskey(s[:edges][:charge_edge][:constraints], :StorageChargeLimitConstraint)
              for s in storage)
end

@testset "Example 1: mass CO2 cap" begin
    case = example_case("1_three_zones"; CO2Cap = 1)
    out = convert_case(case)
    setup, inputs = load_quietly(case)

    co2 = only(g for g in node_groups(out) if g[:type] == "CO2")
    @test co2[:global_data][:constraints][:CO2CapConstraint]
    for (cap, node) in enumerate(co2[:instance_data])
        zones = findall(==(1), inputs["dfCO2CapZones"][:, cap])
        @test node[:id] == "co2_sink_$cap"
        @test node[:rhs_policy][:CO2CapConstraint] ≈ sum(inputs["dfMaxCO2"][z, cap] for z in zones)
        @test !haskey(node, :price_unmet_policy)
    end
    for p in instances(out, "assets/thermal.json", :ThermalPower)
        r = inputs["RESOURCES"][findfirst(g -> g.resource == p[:id], inputs["RESOURCES"])]
        @test p[:edges][:co2_edge][:end_vertex] == G2M.co2_sink(inputs, r.zone)
    end
end

@testset "Example 3: carbon capture and a CO2 cap penalty" begin
    case = example_case("3_three_zones_w_co2_capture")
    cp(joinpath(EXAMPLES, "4_three_zones_w_policies_slack", "policies", "CO2_cap_slack.csv"),
        joinpath(case, "policies", "CO2_cap_slack.csv"); force = true)
    out = @test_logs (:warn, r"CO2_Capture_Fraction_Startup") match_mode = :any convert_case(case)
    setup, inputs = load_quietly(case)

    @test "CO2Captured" in read_json(out, "system/commodities.json")[:commodities]
    @test !isfile(joinpath(out, "assets", "thermal.json"))  # every thermal plant has CCS
    captured = only(g for g in node_groups(out) if g[:type] == "CO2Captured")
    @test [n[:id] for n in captured[:instance_data]] == [G2M.CO2_CAPTURED_SINK]

    for p in instances(out, "assets/thermal_ccs.json", :ThermalPowerCCS)
        r = inputs["RESOURCES"][findfirst(g -> g.resource == p[:id], inputs["RESOURCES"])]
        fuel_co2 = inputs["fuel_CO2"][r.fuel] / MWH_PER_MMBTU
        capture = GenX.co2_capture_fraction(r)
        @test p[:transforms][:capture_rate] ≈ capture * fuel_co2
        @test p[:transforms][:emission_rate] ≈ (1 - GenX.biomass(r) - capture) * fuel_co2
        @test p[:edges][:co2_edge][:end_vertex] == G2M.co2_sink(inputs, r.zone)
        @test p[:edges][:co2_captured_edge][:end_vertex] == G2M.CO2_CAPTURED_SINK
        @test p[:edges][:co2_captured_edge][:variable_om_cost] ≈
              GenX.ccs_disposal_cost_per_metric_ton(r)
        constraints = keys(p[:edges][:elec_edge][:constraints])
        @test !(:MaxCapacityGrowthConstraint in constraints)
        @test !(:DevelopmentConstraint in constraints)
    end

    # GenX's penalty for exceeding the cap becomes Macro's price_unmet_policy.
    slack = read_csv(joinpath(case, "policies", "CO2_cap_slack.csv"))
    co2 = only(g for g in node_groups(out) if g[:type] == "CO2")
    @test [n[:price_unmet_policy][:CO2CapConstraint] for n in co2[:instance_data]] ≈ slack.PriceCap
end

@testset "Asymmetric storage" begin
    case = example_case("1_three_zones")
    path = joinpath(case, "resources", "Storage.csv")
    storage_csv = read_csv(path)
    storage_csv.Model[1] = 2
    storage_csv.Existing_Charge_Cap_MW = fill(0.0, nrow(storage_csv))
    storage_csv.Min_Charge_Cap_MW = fill(10.0, nrow(storage_csv))
    storage_csv.Max_Charge_Cap_MW = fill(5000.0, nrow(storage_csv))
    storage_csv.Inv_Cost_Charge_per_MWyr = fill(5000.0, nrow(storage_csv))
    storage_csv.Fixed_OM_Cost_Charge_per_MWyr = fill(1000.0, nrow(storage_csv))
    CSV.write(path, storage_csv)
    out = convert_case(case)

    storage = Dict(s[:id] => s for s in instances(out, "assets/storage.json", :elec_stor))
    charge = storage[storage_csv.Resource[1]][:edges][:charge_edge]
    @test charge[:has_capacity]
    @test all(haskey(charge[:constraints], c)
              for c in (:CapacityConstraint, :MinCapacityConstraint, :MaxCapacityConstraint))
    @test (charge[:min_capacity], charge[:max_capacity]) == (10, 5000)
    @test charge[:annualized_investment_cost] == 5000
    symmetric = storage[storage_csv.Resource[2]]
    @test !symmetric[:edges][:charge_edge][:has_capacity]
    @test haskey(symmetric[:storage][:constraints], :StorageSymmetricCapacityConstraint)
end

@testset "No network expansion" begin
    out = convert_case(example_case("1_three_zones"; NetworkExpansion = 0))
    for line in instances(out, "assets/transmission.json", :transmission)
        edge = line[:edges][:transmission_edge]
        @test !edge[:can_expand]
        @test edge[:max_capacity] == edge[:existing_capacity]
        @test !haskey(edge, :annualized_investment_cost)
    end
end

@testset "Time domain reduction" begin
    # GenX ships no clustered data, so build a one-period "clustered" folder from the full
    # data; the converter only needs the period map to exist.
    case = example_case("1_three_zones"; TimeDomainReduction = 1)
    tdr = joinpath(case, "TDR_results")
    mkpath(tdr)
    for f in ("Demand_data.csv", "Generators_variability.csv", "Fuels_data.csv")
        cp(joinpath(case, "system", f), joinpath(tdr, f))
    end
    write(joinpath(tdr, "Period_map.csv"), "Period_Index,Rep_Period,Rep_Period_Index\n1,1,1\n")
    out = convert_case(case)

    time_data = read_json(out, "system/time_data.json")
    @test time_data[:SubPeriodMap][:path] == "system/Period_map.csv"
    @test time_data[:TotalHoursModeled] isa Integer
    @test read(joinpath(out, "system", "Period_map.csv"), String) ==
          read(joinpath(tdr, "Period_map.csv"), String)

    rm(joinpath(tdr, "Period_map.csv"))
    @test_throws r"TimeDomainReduction is on" convert_case(case)
end
