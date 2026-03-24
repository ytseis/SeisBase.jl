printstyled("  syngine request helpers\n", color=:light_green)

# _bulk_line: network/station form
line1 = SeisBase._bulk_line((network="IU", station="ANMO"))
@test line1 == "IU ANMO"

# _bulk_line: latitude/longitude form with optional station codes
line2 = SeisBase._bulk_line((
  latitude=34.95,
  longitude=-106.46,
  networkcode="IU",
  stationcode="ANMO",
  locationcode="00",
))
@test line2 == "34.95 -106.46 NETCODE=IU STACODE=ANMO LOCCODE=00"

# _bulk_line: invalid item must fail
@test_throws ErrorException SeisBase._bulk_line((foo=1, bar=2))

# Parameter filtering should drop `nothing` and stringify tuple/vector values.
params = Dict{String, Any}(
  "model" => "ak135f_2s",
  "origintime" => nothing,
  "components" => ["Z", "R", "T"],
  "sourcemomenttensor" => (1, 2, 3, 4, 5, 6),
)
filtered = SeisBase._syngine_filter_params(params)

@test haskey(filtered, "model")
@test !haskey(filtered, "origintime")
@test filtered["components"] == "Z,R,T"
@test filtered["sourcemomenttensor"] == "1,2,3,4,5,6"

# Ensure the bulk request body starts with model=... and includes station lines.
bulk = [(network="IU", station="ANMO"), (network="IU", station="COR")]
body = SeisBase._syngine_bulk_body(Dict("model" => "ak135f_2s", "format" => "miniseed"), bulk)
@test startswith(body, "model=ak135f_2s")
@test occursin("format=miniseed", body)
@test occursin("IU ANMO", body)
@test occursin("IU COR", body)
