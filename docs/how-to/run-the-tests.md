# How to run the tests

The tests convert GenX's own example systems, taken from the installed GenX package, check
the Macro files against the GenX inputs, and load each converted case in Macro, which builds
every asset from its file. Nothing is solved, so no solver is needed.

## Run the whole suite

From the repository root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

A passing run ends with `Testing GenX_to_Macro tests passed`; the full suite takes under a
minute once the packages are compiled.

## Run one test file

While working on one part, load the helpers and run a single file:

```bash
julia --project=. -e 'using GenX_to_Macro, GenX, MacroEnergy, CSV, DataFrames, JSON3, Logging, Test;
    const G2M = GenX_to_Macro; include("test/helpers.jl");
    @testset "utilities" begin include("test/test_utilities.jl") end'
```

| File | Covers |
|---|---|
| `test/test_utilities.jl` | the shared helpers: paths, fuels, CO2 sinks, availability, checks |
| `test/test_single_stage.jl` | GenX examples 1 and 3: CO2 caps, line losses, CCS, storage, TDR; hydro and must-run, added to example 1 |
| `test/test_multistage.jl` | GenX example 6: per-stage files, line limits, investment data |
| `test/test_unsupported.jl` | errors and warnings (BECCS, fuel on non-thermal resources, piecewise fuel, maintenance, retrofits), and example 12's unusual network |

## If a test fails because an example changed

The tests read the examples from whichever GenX version `Project.toml` installs. If a GenX
update renames or changes an example, update the test's expectations or the setting it
overrides in `example_case`.
