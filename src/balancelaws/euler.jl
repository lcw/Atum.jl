module Euler
  export EulerLaw, γ

  import ..Atum
  using ..Atum: avg, logavg, roe_avg
  using StaticArrays
  using LinearAlgebra: I

  struct EulerLaw{γ, FT, D, S} <: Atum.AbstractBalanceLaw{FT, D, S}
    function EulerLaw{FT, D}(; γ = 7 // 5) where {FT, D}
      S = 2 + D
      new{FT(γ), FT, D, S}()
    end
  end

  γ(::EulerLaw{_γ}) where {_γ} = _γ

  function varsindices(law::EulerLaw)
    S = Atum.numberofstates(law)
    ix_ρ = 1
    ix_ρu⃗ = StaticArrays.SUnitRange(2, S - 1)
    ix_ρe = S
    return ix_ρ, ix_ρu⃗, ix_ρe
  end

  function unpackstate(law::EulerLaw, q)
    ix_ρ, ix_ρu⃗, ix_ρe = varsindices(law)
    @inbounds q[ix_ρ], q[ix_ρu⃗], q[ix_ρe]
  end

  function pressure(law::EulerLaw, ρ, ρu⃗, ρe)
    (γ(law) - 1) * (ρe - ρu⃗' * ρu⃗ / 2ρ)
  end
  function energy(law::EulerLaw, ρ, ρu⃗, p)
    p / (γ(law) - 1) + ρu⃗' * ρu⃗ / 2ρ
  end
  function soundspeed(law::EulerLaw, ρ, p)
    sqrt(γ(law) * p / ρ)
  end
  function soundspeed(law::EulerLaw, ρ, ρu⃗, ρe)
    soundspeed(law, ρ, pressure(law, ρ, ρu⃗, ρe))
  end

  function Atum.flux(law::EulerLaw, q, _)
    ρ, ρu⃗, ρe = unpackstate(law, q)

    u⃗ = ρu⃗ / ρ
    p = pressure(law, ρ, ρu⃗, ρe)

    fρ = ρu⃗
    fρu⃗ = ρu⃗ * u⃗' + p * I
    fρe = u⃗ * (ρe + p)

    hcat(fρ, fρu⃗, fρe)
  end

  function Atum.wavespeed(law::EulerLaw, n⃗, q, x⃗)
    ρ, ρu⃗, ρe = unpackstate(law, q)

    u⃗ = ρu⃗ / ρ
    abs(n⃗' * u⃗) + soundspeed(law, ρ, ρu⃗, ρe)
  end

  function Atum.surfaceflux(::Atum.RoeFlux, law::EulerLaw, n⃗, x⃗, q⁻, q⁺)
    f⁻ = Atum.flux(law, q⁻, x⃗)
    f⁺ = Atum.flux(law, q⁺, x⃗)

    ρ⁻, ρu⃗⁻, ρe⁻ = unpackstate(law, q⁻)
    u⃗⁻ = ρu⃗⁻ / ρ⁻
    e⁻ = ρe⁻ / ρ⁻
    p⁻ = pressure(law, ρ⁻, ρu⃗⁻, ρe⁻)
    h⁻ = e⁻ + p⁻ / ρ⁻
    c⁻ = soundspeed(law, ρ⁻, p⁻)

    ρ⁺, ρu⃗⁺, ρe⁺ = unpackstate(law, q⁺)
    u⃗⁺ = ρu⃗⁺ / ρ⁺
    e⁺ = ρe⁺ / ρ⁺
    p⁺ = pressure(law, ρ⁺, ρu⃗⁺, ρe⁺)
    h⁺ = e⁺ + p⁺ / ρ⁺
    c⁺ = soundspeed(law, ρ⁺, p⁺)

    ρ = sqrt(ρ⁻ * ρ⁺)
    u⃗ = roe_avg(ρ⁻, ρ⁺, u⃗⁻, u⃗⁺)
    h = roe_avg(ρ⁻, ρ⁺, h⁻, h⁺)
    c = roe_avg(ρ⁻, ρ⁺, c⁻, c⁺)

    uₙ = u⃗' * n⃗

    Δρ = ρ⁺ - ρ⁻
    Δp = p⁺ - p⁻
    Δu⃗ = u⃗⁺ - u⃗⁻
    Δuₙ = Δu⃗' * n⃗

    c⁻² = 1 / c^2
    w1 = abs(uₙ - c) * (Δp - ρ * c * Δuₙ) * c⁻² / 2
    w2 = abs(uₙ + c) * (Δp + ρ * c * Δuₙ) * c⁻² / 2
    w3 = abs(uₙ) * (Δρ - Δp * c⁻²)
    w4 = abs(uₙ) * ρ

    fp_ρ = (w1 + w2 + w3) / 2
    fp_ρu⃗ = (w1 * (u⃗ - c * n⃗) +
             w2 * (u⃗ + c * n⃗) +
             w3 * u⃗ +
             w4 * (Δu⃗ - Δuₙ * n⃗)) / 2
    fp_ρe = (w1 * (h - c * uₙ) +
             w2 * (h + c * uₙ) +
             w3 * u⃗' * u⃗ / 2 +
             w4 * (u⃗' * Δu⃗ - uₙ * Δuₙ)) / 2

    (f⁻ + f⁺)' * n⃗ / 2 - SVector(fp_ρ, fp_ρu⃗..., fp_ρe)
  end

  function Atum.twopointflux(::Atum.EntropyConservativeFlux,
                             law::EulerLaw,
                             q₁, _, q₂, _)
      FT = eltype(law)
      ρ₁, ρu⃗₁, ρe₁ = unpackstate(law, q₁)
      ρ₂, ρu⃗₂, ρe₂ = unpackstate(law, q₂)

      u⃗₁ = ρu⃗₁ / ρ₁
      p₁ = pressure(law, ρ₁, ρu⃗₁, ρe₁)
      b₁ = ρ₁ / 2p₁

      u⃗₂ = ρu⃗₂ / ρ₂
      p₂ = pressure(law, ρ₂, ρu⃗₂, ρe₂)
      b₂ = ρ₂ / 2p₂

      ρ_avg = avg(ρ₁, ρ₂)
      u⃗_avg = avg(u⃗₁, u⃗₂)
      b_avg = avg(b₁, b₂)

      u²_avg = avg(u⃗₁' * u⃗₁, u⃗₂' * u⃗₂)
      ρ_log = logavg(ρ₁, ρ₂)
      b_log = logavg(b₁, b₂)

      fρ = u⃗_avg * ρ_log
      fρu⃗ = u⃗_avg * fρ' + ρ_avg / 2b_avg * I
      fρe = (1 / (2 * (γ(law) - 1) * b_log) - u²_avg / 2) * fρ + fρu⃗ * u⃗_avg

      hcat(fρ, fρu⃗, fρe)
  end
end
