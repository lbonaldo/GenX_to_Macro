# How to resolve conversion errors and warnings

The converter stops with an error when a GenX case uses something Macro cannot represent, and
warns when it leaves part of a case out. Find the message below and apply the fix.

The converter checks every stage before writing anything, so a conversion that stops leaves
no partial Macro case behind.

## Errors

| Message starts with | What to do |
|---|---|
| `CO2Cap = 2 is a rate-based CO2 cap` (or `3`) | Macro has only mass caps. Set `CO2Cap: 1` and give each cap as a mass (the `CO_2_Max_Mtons_*` columns of `CO2_cap.csv`, in million tonnes), or `CO2Cap: 0` for no cap. |
| `Trans_Loss_Segments = 2 models quadratic line losses` | Set `Trans_Loss_Segments: 1` (fixed loss percentage) or `0` (lossless lines). |
| `Multi-fuel resources cannot be converted` | Give each listed resource a single fuel. |
| `<plant> uses fuel '<name>', which has no Macro commodity` | Rename the fuel, in `Fuels_data.csv` and the plant's `Fuel` column, so the converter recognises it (case does not matter): natural gas contains `gas`, contains `_NG` or is `NG`; coal contains `coal`; uranium contains `uranium` or `nuclear`. Any other fuel needs a new commodity in the converter: see [Add a GenX resource type](add-a-resource-type.md). |
| `Zone <z> belongs to CO2 caps [...]` | Put each zone in at most one cap in `CO2_cap.csv`. |
| `TimeDomainReduction is on but .../Period_map.csv does not exist` | Run the case in GenX once so it writes its clustered data, or set `TimeDomainReduction: 0`. |
| `No inputs_p<n> stage folders found` | A multi-stage case needs its stages in `inputs/inputs_p1`, `inputs/inputs_p2`, …. |

## Warnings

| Message starts with | What to do |
|---|---|
| `These active GenX settings are not converted` | The listed policies or options (for example `MinCapReq`, `DC_OPF`) are missing from the Macro case. To compare the two models, switch them off in the GenX case. |
| `These GenX resource types are not converted` | The listed resources (co-located VRE and storage, flexible demand, electrolyzers, Allam cycle) are missing from the Macro case. Remove them from the GenX case for a comparison, or add support for them. |
| `<plant>: CO2_Capture_Fraction_Startup differs from CO2_Capture_Fraction` | Macro uses one capture rate, so start-up emissions differ from GenX. Set the two equal in the GenX case for a like-for-like comparison. |
| `Could not find: "locations.json"` (from Macro) | No action needed. Macro requires the entry in `system_data.json`; the converted case has no locations. |
