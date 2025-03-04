module Advection
  export AdvectionLaw

  import ..Atum
  using StaticArrays: SVector

  @Base.kwdef struct AdvectionLaw{FT, D} <: Atum.AbstractBalanceLaw{FT, D, 1}
    u⃗::SVector{D, FT} = ones(SVector{D, FT})
  end

  Atum.flux(law::AdvectionLaw, q, x⃗) = law.u⃗ * q'
  Atum.wavespeed(law::AdvectionLaw, n⃗, q, x⃗) = abs(n⃗' * law.u⃗)
end
