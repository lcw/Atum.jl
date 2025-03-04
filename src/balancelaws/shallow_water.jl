module ShallowWater
  export ShallowWaterLaw, grav

  import ..Atum
  using ..Atum: avg, roe_avg
  using StaticArrays
  using LinearAlgebra: I

  struct ShallowWaterLaw{grav, FT, D, S} <: Atum.AbstractBalanceLaw{FT, D, S}
    function ShallowWaterLaw{FT, D}(; grav = 10) where {FT, D}
      S = 2 + D
      new{FT(grav), FT, D, S}()
    end
  end

  grav(::ShallowWaterLaw{_grav}) where {_grav} = _grav

  function varsindices(law::ShallowWaterLaw)
    S = Atum.numberofstates(law)
    ix_ρ = 1
    ix_ρu⃗ = StaticArrays.SUnitRange(2, S - 1)
    ix_ρθ = S
    return ix_ρ, ix_ρu⃗, ix_ρθ
  end

  function unpackstate(law::ShallowWaterLaw, q)
    ix_ρ, ix_ρu⃗, ix_ρθ = varsindices(law)
    @inbounds q[ix_ρ], q[ix_ρu⃗], q[ix_ρθ]
  end

  function Atum.flux(law::ShallowWaterLaw, q, x⃗)
    ρ, ρu⃗, ρθ = unpackstate(law, q)

    u⃗ = ρu⃗ / ρ
    p = grav(law) * ρ ^ 2 / 2

    fρ = ρu⃗
    fρu⃗ = ρu⃗ * u⃗' + p * I
    fρθ = u⃗ * ρθ

    hcat(fρ, fρu⃗, fρθ)
  end

  function Atum.wavespeed(law::ShallowWaterLaw, n⃗, q, x⃗)
    ρ, ρu⃗, ρe = unpackstate(law, q)

    u⃗ = ρu⃗ / ρ
    abs(n⃗' * u⃗) + sqrt(grav(law) * ρ)
  end

  function Atum.surfaceflux(::Atum.RoeFlux, law::ShallowWaterLaw, n⃗, x⃗, q⁻, q⁺)
    g = grav(law)
    f⁻ = Atum.flux(law, q⁻, x⃗)
    f⁺ = Atum.flux(law, q⁺, x⃗)

    ρ⁻, ρu⃗⁻, ρθ⁻ = unpackstate(law, q⁻)
    u⃗⁻ = ρu⃗⁻ / ρ⁻
    θ⁻ = ρθ⁻ / ρ⁻
    p⁻ = g * ρ⁻ ^ 2 / 2
    c⁻ = sqrt(g * ρ⁻)

    ρ⁺, ρu⃗⁺, ρθ⁺ = unpackstate(law, q⁺)
    u⃗⁺ = ρu⃗⁺ / ρ⁺
    θ⁺ = ρθ⁺ / ρ⁺
    p⁺ = g * ρ⁺ ^ 2 / 2
    c⁺ = sqrt(g * ρ⁺)

    ρ = sqrt(ρ⁻ * ρ⁺)
    u⃗ = roe_avg(ρ⁻, ρ⁺, u⃗⁻, u⃗⁺)
    θ = roe_avg(ρ⁻, ρ⁺, θ⁻, θ⁺)
    c = roe_avg(ρ⁻, ρ⁺, c⁻, c⁺)

    uₙ = u⃗' * n⃗

    Δρ = ρ⁺ - ρ⁻
    Δp = p⁺ - p⁻
    Δu⃗ = u⃗⁺ - u⃗⁻
    Δρθ = ρθ⁺ - ρθ⁻
    Δuₙ = Δu⃗' * n⃗

    c⁻² = 1 / c^2
    w1 = abs(uₙ - c) * (Δp - ρ * c * Δuₙ) * c⁻² / 2
    w2 = abs(uₙ + c) * (Δp + ρ * c * Δuₙ) * c⁻² / 2
    w3 = abs(uₙ) * (Δρ - Δp * c⁻²)
    w4 = abs(uₙ) * ρ
    w5 = abs(uₙ) * (Δρθ - θ * Δp * c⁻²)

    fp_ρ = (w1 + w2 + w3) / 2
    fp_ρu⃗ = (w1 * (u⃗ - c * n⃗) + w2 * (u⃗ + c * n⃗) + w3 * u⃗ + w4 * (Δu⃗ - Δuₙ * n⃗)) / 2
    fp_ρθ = ((w1 + w2) * θ + w5) / 2

    (f⁻ + f⁺)' * n⃗ / 2 - SVector(fp_ρ, fp_ρu⃗..., fp_ρθ)
  end

  function Atum.twopointflux(::Atum.EntropyConservativeFlux,
                             law::ShallowWaterLaw,
                             q₁, _, q₂, _)
      FT = eltype(law)
      ρ₁, ρu⃗₁, ρθ₁ = unpackstate(law, q₁)
      ρ₂, ρu⃗₂, ρθ₂ = unpackstate(law, q₂)

      u⃗₁ = ρu⃗₁ / ρ₁
      θ₁ = ρθ₁ / ρ₁

      u⃗₂ = ρu⃗₂ / ρ₂
      θ₂ = ρθ₂ / ρ₂

      ρ_avg = avg(ρ₁, ρ₂)
      ρ²_avg = avg(ρ₁ ^ 2, ρ₂ ^ 2)
      u⃗_avg = avg(u⃗₁, u⃗₂)
      ρu⃗_avg = avg(ρu⃗₁, ρu⃗₂)
      θ_avg = avg(θ₁, θ₂)

      fρ = ρu⃗_avg
      fρu⃗ = ρu⃗_avg * u⃗_avg' + grav(law) * (ρ_avg ^ 2 - ρ²_avg / 2) * I
      fρθ = ρu⃗_avg * θ_avg

      hcat(fρ, fρu⃗, fρθ)
  end
end
