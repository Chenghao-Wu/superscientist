# Bead-Spring Polymer R_g Scaling Experiment Design

**Objective:** Compute radius of gyration R_g as a function of chain length N for a single Kremer-Grest bead-spring chain in a large box, then fit R_g ~ N^ν to confirm the Flory exponent (ν ≈ 0.588, good solvent).
**System:** Single linear bead-spring polymer chain; N = 10, 20, 50, 100, 200 beads; 3 independent runs per N (15 total simulations); LJ reduced units.
**Method:** NVT molecular dynamics with Langevin thermostat; Kremer-Grest force field (FENE bonds + WCA non-bonded); single chain in vacuum in a large periodic box.
**Software:** LAMMPS (lmp, omnischolar environment); AutoPoly BeadSpringPolymer.kremer_grest() for structure generation; Python (numpy, matplotlib) for analysis.

## Method Validation

The Kremer-Grest model is the canonical bead-spring model for polymer scaling studies and has been validated extensively for exactly this application. The seminal reference is Kremer & Grest, *J. Chem. Phys.* 92, 5057 (1990), which confirms ν ≈ 0.588 for single-chain NVT simulations in good solvent conditions using FENE+WCA. AutoPoly's `BeadSpringPolymer.kremer_grest()` implements this model directly. No additional validation stage is required.

The WCA potential (LJ truncated and shifted at r_cut = 2^(1/6)σ) provides purely repulsive interactions → good solvent regime. Flory exponent expected: ν ≈ 0.588 (3D SAW universality class).

## Computational Stages

### Stage 1: Structure Generation (AutoPoly)
- **Purpose:** Generate LAMMPS data file for a single chain of length N in a large periodic box.
- **Inputs:** Chain length N; box size L = max(10σ, 5 × R_g_expected), where R_g_expected ≈ σ × N^0.588 / √6.
- **Parameters:**
  - AutoPoly `BeadSpringPolymer.kremer_grest()`: n_chains=1, n_beads=N, topology="linear"
  - SAW placement (`saw_generate()`) to avoid initial overlaps
  - Box size calculated per chain length to guarantee no periodic image contact
- **Success criteria:** Data file written with no initial bond length > 1.35σ (= 0.9 × R₀); assert L > 5 × R_g_expected before proceeding to dynamics.
- **Expected walltime:** < 1 min per chain.
- **Known pitfalls:**
  - Box too small → chain interacts with its own periodic image, artificially compressing R_g. Safeguard: enforce L > 5 × R_g_expected when setting box size.
  - Poor SAW: overlapping initial config causes FENE blowup in minimization. Safeguard: verify max bond length < 1.35σ after generation.

### Stage 2: Minimization + Equilibration
- **Purpose:** Relax residual overlaps from SAW placement; equilibrate chain conformation to thermal equilibrium.
- **Inputs:** LAMMPS data file from Stage 1.
- **Parameters:**
  - Minimization: conjugate gradient, etol=1e-6, ftol=1e-8, maxiter=10000
  - NVT Langevin thermostat: T=1.0 ε/k_B, damping γ=1.0τ⁻¹
  - Timestep: dt=0.005τ
  - Equilibration length: 2×10⁴τ (= 4×10⁶ steps)
  - Equilibration time rationale: Rouse time τ_R ~ N^(1+2ν) ≈ N^2.18; for N=200, τ_R ≈ ~10⁴τ → 2×10⁴τ gives ≥ 2 relaxation times.
- **Success criteria:** R_g time series visually flat (no monotonic drift) over the last 50% of equilibration trajectory; temperature fluctuating around T=1.0 ± 0.05.
- **Expected walltime:** ~1–30 min depending on N.
- **Known pitfalls:**
  - N=200 may require longer equilibration if τ_R estimate is underestimated. Safeguard: inspect R_g(t) trace before starting production; extend equilibration if drift persists.
  - FENE bond blowup if minimization fails to resolve overlaps. Safeguard: check for LOST ATOMS warning in LAMMPS log after minimization.

### Stage 3: Production + R_g Sampling
- **Purpose:** Collect equilibrium R_g samples for statistical averaging.
- **Inputs:** Restart file from end of Stage 2 equilibration.
- **Parameters:**
  - NVT Langevin: T=1.0, γ=1.0τ⁻¹, dt=0.005τ
  - Production length: 2×10⁴τ (= 4×10⁶ steps)
  - R_g sampling: LAMMPS `compute gyration` + `fix ave/time` every 100τ (= 2×10⁴ steps) → ~200 frames per run
  - Output: R_g time series to file (one file per run)
- **Success criteria:** ≥ 100 approximately uncorrelated R_g samples per run (verify sampling interval > 2× measured autocorrelation time); block-averaged R_g standard error < 2% of mean.
- **Expected walltime:** ~2–60 min per run; ~5 hr total for all 15 runs sequentially; ~1–2 hr if parallelized across cores.
- **Known pitfalls:**
  - Sampling interval too short → correlated samples, underestimated statistical error. Safeguard: compute R_g autocorrelation time in analysis; flag if τ_autocorr > 50τ.
  - Thermostat over-damping suppressing chain dynamics. Safeguard: γ=1.0τ⁻¹ is standard Kremer-Grest value; do not increase.

### Stage 4: Analysis and Scaling Fit
- **Purpose:** Compute R_g mean ± stderr per N, fit power law R_g = b × N^ν, extract Flory exponent ν.
- **Inputs:** R_g time series files from Stage 3 (15 files: 5 N values × 3 runs each).
- **Parameters:**
  - Average R_g across all frames and all 3 runs for each N; compute standard error of the mean
  - Weighted log-log linear regression: log(R_g) = ν × log(N) + log(b), weighted by 1/stderr²
  - Python: numpy.polyfit or scipy.stats.linregress on log-transformed data
- **Success criteria:** Fitted ν in range 0.55–0.62 (literature: 0.588 ± ~0.01 for large N); R² > 0.99 on log-log plot; residuals show no systematic trend.
- **Expected walltime:** < 1 min.
- **Known pitfalls:**
  - Small-N deviations: N=10 has large finite-N corrections to scaling, which may bias the fit. Safeguard: check fit residuals; optionally report fit with and without N=10.
  - Unweighted regression over-weights noisy small-N points. Safeguard: always use weighted regression.

## Convergence Strategy

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Timestep dt | 0.005τ | Standard for FENE+WCA; below the 0.01τ stability limit for stiff FENE bonds |
| Box size L | max(10σ, 5×R_g_expected) | Prevents periodic image interaction; 5× margin is conservative |
| Equilibration length | 2×10⁴τ | ≥ 2× Rouse time τ_R ~ N^2.18 for largest N=200 (τ_R ≈ ~10⁴τ) |
| Production length | 2×10⁴τ | Matches equilibration; gives ~200 samples at 100τ/sample |
| Sampling interval | 100τ | Approximately decorrelated; verified against measured autocorrelation time |
| Runs per N | 3 | Provides independent R_g estimates for error bars and regression weighting |
| Thermostat damping γ | 1.0τ⁻¹ | Standard Kremer-Grest value (Kremer & Grest 1990); balances coupling vs. dynamics |
| WCA cutoff | 2^(1/6)σ | Fixed by definition; no convergence testing needed |

## Expected Outputs

- 15 LAMMPS data files (1 per run)
- 15 R_g time series files from `fix ave/time`
- Summary table: R_g mean ± stderr for each N (5 rows)
- Log-log plot of R_g vs N with power-law fit line and error bars
- Fitted Flory exponent ν with uncertainty (expected: 0.57–0.60 for N=10–200, approaching 0.588 at large N)

## Resource Estimate

| Chain length | Time per run (est.) | 3 runs |
|---|---|---|
| N=10 | ~2 min | ~6 min |
| N=20 | ~5 min | ~15 min |
| N=50 | ~10 min | ~30 min |
| N=100 | ~25 min | ~75 min |
| N=200 | ~60 min | ~3 hr |
| **Total (sequential)** | | **~5 hr** |
| **Total (8-core parallel)** | | **~1–2 hr** |

Storage: < 100 MB total. Memory: negligible (single chain, O(N) atoms).
