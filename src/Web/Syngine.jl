export get_synthetics, get_synthetics_bulk

const SYNGINE_URL = "https://service.iris.edu/irisws/syngine/1/query"

# Convert values to syngine-compatible request values.
_syngine_value(x) = x
_syngine_value(x::TimeType) = string(x)
_syngine_value(x::Tuple) = join(string.(x), ",")
_syngine_value(x::AbstractVector) = join(string.(x), ",")

function _syngine_filter_params(params::Dict{String, Any})
  return Dict(k => _syngine_value(v) for (k, v) in params if !isnothing(v))
end

function _syngine_parse_mseed(body::Vector{UInt8}, v::Integer)
  S = SeisData()
  parsemseed!(S, IOBuffer(body), KW.nx_add, KW.nx_add, true, v)
  seed_cleanup!(S, BUF)
  return S
end

function _syngine_require_mseed(format::String)
  fmt = lowercase(format)
  if fmt ∉ ("miniseed", "mseed")
    error(string("Unsupported syngine format \"", format,
                 "\". SeisBase currently parses only miniSEED output."))
  end
  return nothing
end

function _syngine_get(params::Dict{String, String}, to::Int64)
  req = request("GET", SYNGINE_URL, webhdr;
                query=params,
                readtimeout=to,
                status_exception=false)
  if req.status != 200
    error(string("syngine request failed: HTTP ", req.status,
                 " (", statustext(req.status), ")"))
  end
  return req.body
end

function _syngine_post(body::String, to::Int64)
  hdr = vcat(webhdr, ["Content-Type" => "text/plain"])
  req = request("POST", SYNGINE_URL, hdr, body;
                readtimeout=to,
                status_exception=false)
  if req.status != 200
    error(string("syngine bulk request failed: HTTP ", req.status,
                 " (", statustext(req.status), ")"))
  end
  return req.body
end

function _bulk_line(item::NamedTuple)
  if haskey(item, :network) && haskey(item, :station)
    return "$(item.network) $(item.station)"
  elseif haskey(item, :latitude) && haskey(item, :longitude)
    parts = ["$(item.latitude) $(item.longitude)"]
    haskey(item, :networkcode) && push!(parts, "NETCODE=$(item.networkcode)")
    haskey(item, :stationcode) && push!(parts, "STACODE=$(item.stationcode)")
    haskey(item, :locationcode) && push!(parts, "LOCCODE=$(item.locationcode)")
    return join(parts, " ")
  else
    error("bulk item must contain either (network, station) or (latitude, longitude)")
  end
end

function _bulk_item_matches_channel(item::NamedTuple, net::String, sta::String, loc::String)
  if haskey(item, :network) && haskey(item, :station)
    return string(item.network) == net && string(item.station) == sta
  end

  if haskey(item, :networkcode) && !isempty(string(item.networkcode))
    string(item.networkcode) == net || return false
  end
  if haskey(item, :stationcode) && !isempty(string(item.stationcode))
    string(item.stationcode) == sta || return false
  end
  if haskey(item, :locationcode) && !isempty(string(item.locationcode))
    string(item.locationcode) == loc || return false
  end
  return haskey(item, :latitude) && haskey(item, :longitude)
end

function _populate_syngine_locations!(S::SeisData, bulk::AbstractVector{<:NamedTuple})
  if isempty(bulk)
    return nothing
  end

  for i in 1:S.n
    id = split(S.id[i], '.', keepempty=true)
    net = length(id) >= 1 ? id[1] : ""
    sta = length(id) >= 2 ? id[2] : ""
    loc = length(id) >= 3 ? id[3] : ""

    k = findfirst(item -> _bulk_item_matches_channel(item, net, sta, loc), bulk)
    if !isnothing(k)
      S[i].loc.lat = Float64(bulk[k].latitude)
      S[i].loc.lon = Float64(bulk[k].longitude)
    end
  end

  return nothing
end

function _syngine_bulk_body(common::AbstractDict{String, <:Any}, bulk::AbstractVector{<:NamedTuple})
  lns = String[]
  push!(lns, string("model=", common["model"]))
  for k in sort(collect(keys(common)))
    k == "model" && continue
    push!(lns, "$k=$(common[k])")
  end
  for item in bulk
    push!(lns, _bulk_line(item))
  end
  return join(lns, "\n") * "\n"
end

"""
    S = get_synthetics(; kwargs...)

Request synthetic seismograms from the IRIS syngine service and return them as
`SeisData`.

This method sends a `GET` request to the syngine `query` endpoint and expects a
miniSEED response (`format="miniseed"` or `format="mseed"`).

Commonly used keywords include:
- `model` (default: `"ak135f_2s"`)
- receiver specification (`network` + `station`, or `receiverlatitude` + `receiverlongitude`)
- source specification (`eventid`, or source parameters such as `sourcelatitude`, `sourcelongitude`)
- time controls (`origintime`, `starttime`, `endtime`)
- `components`, `units`, `dt`
- `to` (HTTP read timeout in seconds)

See the syngine API docs for the full parameter list and valid combinations.
"""
function get_synthetics(;
    model="ak135f_2s",
    network=nothing,
    station=nothing,
    receiverlatitude=nothing,
    receiverlongitude=nothing,
    networkcode=nothing,
    stationcode=nothing,
    locationcode=nothing,
    eventid=nothing,
    sourcelatitude=nothing,
    sourcelongitude=nothing,
    sourcedepthinmeters=nothing,
    sourcemomenttensor=nothing,
    sourcedoublecouple=nothing,
    sourceforce=nothing,
    origintime=nothing,
    starttime=nothing,
    endtime=nothing,
    label=nothing,
    components=nothing,
    units=nothing,
    scale=nothing,
    dt=nothing,
    kernelwidth=nothing,
    format="miniseed",
    filename=nothing,
    to::Int64=SeisBase.KW.to,
    v::Integer=SeisBase.KW.v,
)
  _syngine_require_mseed(format)

  params = _syngine_filter_params(Dict{String, Any}(
      "model" => model,
      "network" => network,
      "station" => station,
      "receiverlatitude" => receiverlatitude,
      "receiverlongitude" => receiverlongitude,
      "networkcode" => networkcode,
      "stationcode" => stationcode,
      "locationcode" => locationcode,
      "eventid" => eventid,
      "sourcelatitude" => sourcelatitude,
      "sourcelongitude" => sourcelongitude,
      "sourcedepthinmeters" => sourcedepthinmeters,
      "sourcemomenttensor" => sourcemomenttensor,
      "sourcedoublecouple" => sourcedoublecouple,
      "sourceforce" => sourceforce,
      "origintime" => origintime,
      "starttime" => starttime,
      "endtime" => endtime,
      "label" => label,
      "components" => components,
      "units" => units,
      "scale" => scale,
      "dt" => dt,
      "kernelwidth" => kernelwidth,
      "format" => format,
      "filename" => filename,
  ))

  body = _syngine_get(params, to)
  return _syngine_parse_mseed(body, v)
end

"""
    S = get_synthetics_bulk(; bulk, kwargs...)

Request synthetic seismograms from syngine with a bulk `POST` request and
return them as `SeisData`.

`bulk` must be a vector of `NamedTuple`s. Each item must define either:
- `network` and `station`, or
- `latitude` and `longitude` (optionally with `networkcode`, `stationcode`, `locationcode`).

When `latitude`/`longitude` are provided in `bulk`, this function attempts to
populate `S.loc.lat` and `S.loc.lon` for matching channels.
"""
function get_synthetics_bulk(;
    model="ak135f_2s",
    bulk::AbstractVector{<:NamedTuple},
    eventid=nothing,
    sourcelatitude=nothing,
    sourcelongitude=nothing,
    sourcedepthinmeters=nothing,
    sourcemomenttensor=nothing,
    sourcedoublecouple=nothing,
    sourceforce=nothing,
    origintime=nothing,
    starttime=nothing,
    endtime=nothing,
    label=nothing,
    components=nothing,
    units=nothing,
    scale=nothing,
    dt=nothing,
    kernelwidth=nothing,
    format="miniseed",
    filename=nothing,
    to::Int64=KW.to,
    v::Integer=KW.v,
)
  isempty(bulk) && error("`bulk` must contain at least one receiver specification.")
  _syngine_require_mseed(format)

  common = _syngine_filter_params(Dict(
      "model" => model,
      "eventid" => eventid,
      "sourcelatitude" => sourcelatitude,
      "sourcelongitude" => sourcelongitude,
      "sourcedepthinmeters" => sourcedepthinmeters,
      "sourcemomenttensor" => sourcemomenttensor,
      "sourcedoublecouple" => sourcedoublecouple,
      "sourceforce" => sourceforce,
      "origintime" => origintime,
      "starttime" => starttime,
      "endtime" => endtime,
      "label" => label,
      "components" => components,
      "units" => units,
      "scale" => scale,
      "dt" => dt,
      "kernelwidth" => kernelwidth,
      "format" => format,
      "filename" => filename,
  ))

  body = _syngine_bulk_body(common, bulk)
  response_body = _syngine_post(body, to)
  S = _syngine_parse_mseed(response_body, v)
  _populate_syngine_locations!(S, bulk)
  return S
end
