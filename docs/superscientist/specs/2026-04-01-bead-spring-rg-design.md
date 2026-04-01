# Bead-Spring Single Chain R_g Experiment Design

**Objective:** Compute the radius of gyration (R_g) of a single N=50 Kremer-Grest bead-spring chain in a large periodic box using LAMMPS.
**System:** Single linear bead-spring polymer chain, N=50 beads, LJ reduced units.
**Method:** NVT molecular dynamics with Langevin thermostat; Kremer-Grest force field (FENE bonds + WCA non-bonded); single chain in a large periodic box (good solvent regime).
**Software:** LAMMPS (lmp, omnischolar environment); AutoPoly `BeadSpringPolymer.kremer_grest()` for structure generation.

## Method Validation

The Kremer-Grest model is the canonical bead-spring model for polymer simulations and has been extensively validated for chain conformational properties. The seminal reference is Kremer & Grest, *J. Chem. Phys.* 92, 5057 (1990). AutoPoly's `BeadSpringPolymer.kremer_grest()` implements this model directly. No additional validation stage is required.

The WCA potential (LJ truncated and shifted at r_cut = 2^(1/6)sigma) provides purely repulsive interactions, corresponding to the good solvent regime. Expected R_g for N=50: approximately sigma * 50^0.588 / sqrt(6) ~ 3.6 sigma.

## Computational Stages

### Stage 1: Structure Generation (AutoPoly)
- **Purpose:** Generate a LAMMPS data file for a single N=50 Kremer-Grest chain in a large periodic box.
- **Inputs:** None.
- **Parameters:**
  - AutoPoly `BeadSpringPolymer.kremer_grest()`: n_chains=1, n_beads=50, topology="linear"
  - SAW placement (`saw_generate()`) to avoid initial overlaps
  - Box size L = 18 sigma (= max(10 sigma, 5 * R_g_expected), ensuring no periodic image self-interaction)
- **Success criteria:** Data file written; max bond length < 1.35 sigma (= 0.9 * R_0); box length >= 18 sigma.
- **Expected walltime:** < 1 min.
- **Known pitfalls:**
  - Box too small: chain interacts with its own periodic image, artificially compressing R_g. Safeguard: enforce L >= 5 * R_g_expected.
  - Poor SAW causing overlapping beads: leads to FENE blowup in minimization. Safeguard: verify max bond length < 1.35 sigma after generation.

### Stage 2: Minimization + Equilibration
- **Purpose:** Relax residual overlaps from SAW placement; equilibrate chain conformation to thermal equilibrium.
- **Inputs:** LAMMPS data file from Stage 1.
- **Parameters:**
  - Minimization: conjugate gradient, etol=1e-6, ftol=1e-8, maxiter=10000
  - NVT Langevin thermostat: T=1.0 epsilon/k_B, damping gamma=1.0 tau^-1
  - Timestep: dt=0.005 tau
  - Equilibration length: 1x10^4 tau (= 2x10^6 steps)
  - Equilibration time rationale: Rouse time tau_R ~ N^(1+2*nu) = 50^2.18 ~ 4000 tau; 1x10^4 tau gives ~2.5 relaxation times.
- **Success criteria:** No LOST ATOMS error in LAMMPS log; temperature stable at T=1.0 +/- 0.05; R_g time series shows no monotonic drift over the last 50% of equilibration.
- **Expected walltime:** ~5 min.
- **Known pitfalls:**
  - FENE bond blowup if minimization fails to resolve overlaps. Safeguard: check LAMMPS log for errors after minimization.
  - Insufficient equilibration if Rouse time estimate is low. Safeguard: inspect R_g(t) trace before starting production; extend if drift persists.

### Stage 3: Production + R_g Measurement
- **Purpose:** Collect equilibrium R_g samples for statistical averaging.
- **Inputs:** Restart file from end of Stage 2 equilibration.
- **Parameters:**
  - NVT Langevin: T=1.0, gamma=1.0 tau^-1, dt=0.005 tau
  - Production length: 1x10^4 tau (= 2x10^6 steps)
  - R_g measurement: LAMMPS `compute gyration` + `fix ave/time` every 100 tau (= 20000 steps) -> ~100 R_g samples
  - Output: R_g time series to file
- **Success criteria:** >= 50 approximately uncorrelated R_g samples; standard error of mean R_g < 5% of mean.
- **Expected walltime:** ~5 min.
- **Known pitfalls:**
  - Sampling interval shorter than autocorrelation time -> correlated samples, underestimated error. Safeguard: verify autocorrelation time < 50 tau.
  - Thermostat over-damping suppressing chain dynamics. Safeguard: gamma=1.0 tau^-1 is the standard Kremer-Grest value; do not increase.

## Convergence Strategy

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Timestep dt | 0.005 tau | Standard for FENE+WCA; below the 0.01 tau stability limit for stiff FENE bonds |
| Box size L | 18 sigma | 5x expected R_g; prevents periodic image self-interaction |
| Equilibration length | 1x10^4 tau | ~2.5x Rouse time for N=50 (tau_R ~ 4000 tau) |
| Production length | 1x10^4 tau | Gives ~100 R_g samples at 100 tau intervals |
| Sampling interval | 100 tau | Approximately decorrelated for N=50 chain dynamics |
| Thermostat damping gamma | 1.0 tau^-1 | Standard Kremer-Grest value (Kremer & Grest 1990) |
| WCA cutoff | 2^(1/6) sigma | Fixed by definition; no convergence testing needed |

## Expected Outputs

- 1 LAMMPS data file from AutoPoly
- 1 R_g time series file from `fix ave/time`
- Mean R_g +/- standard error (expected ~3.6 sigma)

## Resource Estimate

- Total walltime: ~10-15 min
- Storage: negligible (< 10 MB)
- Memory: negligible
- No stages exceed 1 hour
