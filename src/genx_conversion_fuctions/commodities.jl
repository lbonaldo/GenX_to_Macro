"Commodities in the order they are listed in `commodities.json`."
const COMMODITY_ORDER = ["Electricity", "NaturalGas", "Uranium", "Coal", "CO2", "CO2Captured"]

"""
    case_commodities(inputs)

Commodities a converted stage needs: electricity, CO2, the commodity of every fuel with a
Macro node, and captured CO2 when there are CCS plants.
"""
function case_commodities(inputs::Dict)
    present = Set(["Electricity", "CO2"])
    for f in setdiff(inputs["fuels"], ["None"])
        commodity = fuel_commodity(f)
        commodity === nothing || push!(present, commodity)
    end
    isempty(ccs_thermal(inputs)) || push!(present, "CO2Captured")
    return present
end

"Write `commodities.json`, listing `commodities` in a fixed order."
function make_commodities_json(commodities, macro_case::AbstractString)
    ordered = filter(in(commodities), COMMODITY_ORDER)
    write_json(joinpath(macro_case, "system", "commodities.json"), Dict("commodities" => ordered))
    return ordered
end
