# Bead-Spring Polymer Rg Experiment Design

**Objective:** Validate that the radius of gyration of a single Kremer-Grest bead-spring chain (N=30) agrees with the expected Flory scaling in the good-solvent limit (ν ≈ 0.588).
**System:** Single flexible polymer chain, N=30 identical beads, in a dilute (single-chain) periodic box of 50σ × 50σ × 50σ.
**Method:** NVT molecular dynamics, Kremer-Grest WCA+FENE model, T=1.0 (LJ units).
**Software:** AutoPoly (structure generation), LAMMPS (MD), Python/numpy/matplotlib (analysis).

## Method Validation

The Kremer-Grest (KG) model is the standard coarse-grained model for flexible polymer chains. The WCA variant (purely repulsive non-bonded interactions, LJ truncated at $r_c = 2^{1/6}\sigma$) places the chain in the good-solvent (athermal) limit, where the Flory exponent is $\nu \approx 0.588$ (3D self-avoiding walk). This model and its Rg scaling are extensively validated:

- Kremer K. & Grest G.S., *JCP* 92, 5057 (1990) — original model and chain statistics
- Expected $\langle R_g \rangle \approx 2.8$–$3.2\,\sigma$ for N=30 at T=1.0 from the literature

No additional validation stage is required; this is one of the most-cited CG polymer models.

## Computational Stages

### Stage 1: Structure Generation
- **Purpose:** Create a LAMMPS data file for a single bead-spring chain (N=30) in a 50σ cubic box.
- **Inputs:** AutoPoly bead-spring CG configuration (chain_num=1, N=30).
- **Parameters:** Box size 50σ (≥14× expected Rg of ~3σ, prevents periodic image interactions); bead mass=1, σ=1, ε=1.
- **Success criteria:** Data file contains exactly 30 atoms and 29 bonds; no atom pair separated by more than R₀=1.5σ.
- **Expected walltime:** <1 s.
- **Known pitfalls:** Random-walk initial placement may occasionally produce bond lengths near R₀, causing FENE divergence in Stage 2. Safeguard: Stage 2 minimization will catch this; if minimization fails, regenerate with a different random seed.

### Stage 2: Energy Minimization
- **Purpose:** Remove steric clashes from the initial configuration before dynamics.
- **Inputs:** Data file from Stage 1; WCA pair style (`lj/cut` with cutoff 1.122σ, shift to zero at cutoff) + FENE bond style (K=30 ε/σ², R₀=1.5σ).
- **Parameters:** Conjugate-gradient minimizer; energy tolerance 1×10⁻⁶; force tolerance 1×10⁻⁶; max 10,000 steps.
- **Success criteria:** Maximum force on any atom < 10 ε/σ after minimization completes.
- **Expected walltime:** <1 s.
- **Known pitfalls:** FENE bonds blow up if bead separation exceeds R₀. Safeguard: verify all bond lengths < 1.4σ after minimization before proceeding.

### Stage 3: NVT Equilibration
- **Purpose:** Relax the chain from its initial geometry to a thermally equilibrated conformation; discard transient memory of the starting structure.
- **Inputs:** Minimized structure; WCA+FENE force field; T=1.0 (LJ units).
- **Parameters:**
  - Timestep: dt=0.005τ (standard KG value, within LAMMPS LJ stability limit)
  - Thermostat: Nosé-Hoover NVT, τ_damp=0.5τ
  - Duration: 1,000,000 steps (5,000τ ≈ 4 Rouse relaxation times for N=30)
  - Output: Rg every 1,000 steps via `compute gyration`
- **Success criteria:** Potential energy stable (drift < 1%) over the last 20% of the run; Rg time series shows no systematic trend (visually flat with fluctuations).
- **Expected walltime:** <1 min.
- **Known pitfalls:** Insufficient equilibration leaves Rg biased toward the initial (often extended) configuration. Safeguard: inspect the Rg vs. time plot from the equilibration log; the chain must have lost memory of the initial structure before production begins.

### Stage 4: NVT Production
- **Purpose:** Collect equilibrium Rg samples for statistical averaging.
- **Inputs:** Equilibrated restart file from Stage 3; same force field and thermostat.
- **Parameters:**
  - Timestep: dt=0.005τ
  - Thermostat: Nosé-Hoover NVT, T=1.0, τ_damp=0.5τ
  - Duration: 5,000,000 steps (25,000τ ≈ 19 Rouse relaxation times)
  - Key commands: `compute gyration all gyration`; log Rg every 1,000 steps (5,000 total samples)
- **Success criteria:** Block-averaged ⟨Rg⟩ converges across 5 equal time blocks (block-to-block variation < 5% of mean); standard error of mean < 0.1σ.
- **Expected walltime:** <5 min.
- **Known pitfalls:** Thermostat damping too tight (τ_damp ≪ 0.5τ) suppresses conformational fluctuations; too loose (τ_damp ≫ 10τ) gives poor temperature control. Nosé-Hoover at τ_damp=0.5τ is the validated choice for KG chains.

### Stage 5: Analysis
- **Purpose:** Compute time-averaged ⟨Rg⟩, block-error estimate, and compare to the Flory scaling prediction.
- **Inputs:** Production thermo log (Rg column).
- **Parameters:** Discard first 20% of samples as additional burn-in; block average over 5 blocks.
- **Success criteria:** ⟨Rg⟩ ∈ [2.8, 3.2]σ; standard error < 0.1σ; block averages mutually consistent within 1 standard error.
- **Expected walltime:** <1 s.
- **Known pitfalls:** Autocorrelation inflates apparent sample count. Safeguard: use block averaging (not raw std/√N) for error estimation.

## Convergence Strategy

| Parameter | Value | Rationale |
|---|---|---|
| Timestep | 0.005τ | Standard KG value; validated in Kremer & Grest (1990) for FENE bonds |
| Box size | 50σ | ≥14× Rg_expected (~3σ); eliminates periodic image interactions |
| Equilibration | 5,000τ | ~4 Rouse relaxation times for N=30 (τ_R ≈ 1,300τ) |
| Production | 25,000τ | ~19 independent Rg samples; block-average convergence verified |
| Thermostat damping | 0.5τ | Standard for KG model; balances coupling strength vs. artifact |
| Rg sampling interval | 1,000 steps (5τ) | Well below τ_R; provides dense time series for block averaging |

## Expected Outputs

- `data.polymer` — LAMMPS data file (N=30 bead-spring chain, 50σ box)
- `in.minimize` — LAMMPS minimization input script
- `in.equil` — LAMMPS equilibration input script
- `in.production` — LAMMPS production input script
- `log.equil`, `log.production` — thermo logs with per-step Rg
- `analyze_rg.py` — Python analysis script
- `rg_result.png` — Rg time-series plot with mean and ±1σ band
- **Final result:** ⟨Rg⟩ ± std. error in LJ units, compared to expected 2.8–3.2σ

## Resource Estimate

| Item | Estimate |
|---|---|
| Total walltime | <10 min (local CPU, serial) |
| Storage | <1 MB (thermo logs; no dump files) |
| Memory | Negligible (30 atoms) |

All stages run well under 1 hour on a laptop CPU. No HPC resources required.
