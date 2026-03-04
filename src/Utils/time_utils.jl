export t_axis

#=
Purpose: time utilities that depend on custom Types go here

Difference from CoreUtils/time.jl functions here require SeisBase Types to work
=#
function mk_t!(C::GphysChannel, nx::Integer, ts_new::Int64)
  T = Array{Int64, 2}(undef, 2, 2)
  setindex!(T, one(Int64), 1)
  setindex!(T, nx, 2)
  setindex!(T, ts_new, 3)
  setindex!(T, zero(Int64), 4)
  setfield!(C, :t, T)
  return nothing
end

function check_for_gap!(S::GphysData, i::Integer, ts_new::Int64, nx::Integer, v::Integer)
  Δ = round(Int64, sμ / getindex(getfield(S, :fs), i))
  T = getindex(getfield(S, :t), i)
  T1 = t_extend(T, ts_new, nx, Δ)
  if T1 != nothing
    if v > 1
      te_old = endtime(T, Δ)
      δt = ts_new - te_old
      (v > 1) && println(stdout, lpad(S.id[i], 15), ": time difference = ", lpad(δt, 16), " μs (old end = ", lpad(te_old, 16), ", new start = ", lpad(ts_new, 16), ", gap = ", lpad(δt-Δ, 16), " μs)")
    end
    S.t[i] = T1
  end
  return nothing
end

# Change by ytseis
"""
    t_axis(n_samples::Int, fs::Float64, t0_micros::Int64, mode::Symbol)

Helper function for internal calculations.
"""
function _generate_time_axis(n_samples::Int, fs::Float64, t0_micros::Int64, mode::Symbol)
    if mode == :relative
        # Elapsed time (seconds) starting from 0 seconds
        return collect(0:n_samples-1) ./ fs
    end

    # Absolute time reference (seconds)
    t_start_sec = t0_micros * 1e-6
    t_unix = t_start_sec .+ (collect(0:n_samples-1) ./ fs)

    if mode == :unix
        # Seconds from Unix epoch
        return t_unix
    elseif mode == :absolute
        # Human-readable DateTime type
        return u2d.(t_unix)
    else
        throw(ArgumentError("mode must be :absolute, :relative, or :unix"))
    end
end

"""
    t_axis(C::GphysChannel; mode=:absolute)

Retrieves the time axis for single-channel data (e.g., SeisChannel).
"""
function t_axis(C::GphysChannel; mode::Symbol=:absolute)
    t_start_micros = starttime(C.t, C.fs)
    return _generate_time_axis(C.t[2,1], C.fs, t_start_micros, mode)
end
