using Atum
using Atum.Euler

using PGFPlotsX
using StaticArrays: SVector

function sod(law, x⃗)
  FT = eltype(law)
  ρ = x⃗[1] < 1 // 2 ? 1 : 1 // 8
  ρu⃗ = SVector(FT(0))
  p = x⃗[1] < 1 // 2 ? 1 : 1 // 10
  ρe = Euler.energy(law, ρ, ρu⃗, p)
  SVector(ρ, ρu⃗..., ρe)
end

import Atum: boundarystate
boundarystate(law::EulerLaw, n⃗, x⃗, q⁻, _) = sod(law, x⃗)

function run(A, FT, N, K)
  Nq = N + 1

  law = EulerLaw{FT, 1}()

  cell = LobattoCell{FT, A}(Nq)
  v1d = range(FT(0), stop=FT(1), length=K+1)
  grid = brickgrid(cell, (v1d,); periodic=(false,))

  dg = ESDGSEM(; law, cell, grid,
               volume_numericalflux = EntropyConservativeFlux(),
               surface_numericalflux = RusanovFlux())

  cfl = FT(1 // 4)
  dt = cfl * step(v1d) / N / Euler.soundspeed(law, FT(1), FT(1))
  timeend = FT(2 // 10)

  q = sod.(Ref(law), points(grid))

  odesolver = LSRK54(dg, q, dt)
  solve!(q, timeend, odesolver)

  @pgf begin
    ρ, ρu, ρe = components(q)
    p = Euler.pressure.(Ref(law), ρ, ρu, ρe)
    u = ρu ./ ρ
    x = vec(first(components(points(grid))))

    fig = @pgf GroupPlot({group_style= {group_size="2 by 2"}})
    ρ_plot = Plot({no_marks}, Coordinates(x, vec(ρ)))
    u_plot = Plot({no_marks}, Coordinates(x, vec(u)))
    E_plot = Plot({no_marks}, Coordinates(x, vec(ρe)))
    p_plot = Plot({no_marks}, Coordinates(x, vec(p)))

    push!(fig, {}, ρ_plot)
    push!(fig, {}, u_plot)
    push!(fig, {}, E_plot)
    push!(fig, {}, p_plot)

    path = mkpath(joinpath("output", "euler", "sod"))
    pgfsave(joinpath(path, "sod.pdf"), fig)
  end
end

let
  A = Array
  FT = Float64
  N = 4
  K = 32

  errf = run(A, FT, N, K)
end
