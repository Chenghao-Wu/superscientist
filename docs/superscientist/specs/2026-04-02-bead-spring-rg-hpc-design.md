# Bead-Spring Single Chain R_g Experiment Design (HPC)

**Objective:** Compute the radius of gyration (R_g) of a single N=50 Kremer-Grest bead-spring chain using remote HPC (SLURM, GPU), replicating the validated local workflow.
**System:** Single linear bead-spring polymer chain, N=50 beads, LJ reduced units.
**Method:** NVT molecular dynamics with Langevin thermostat; Kremer-Grest force field (FENE bonds + WCA non-bonded); single chain in a large periodic box (good solvent regime).
**Software:** LAMMPS with KOKKOS GPU package on HPC; AutoPoly `BeadSpringPolymer` locally for structure generation.

## Cluster Configuration

- **Cluster:** XJTLU_XEC (`zhenghaowu@10.7.91.101`)
- **Remote root:** `/gpfs/home/che/zhenghaowu/bead-spring-rg`
- **LAMMPS binary:** `/gpfs/home/che/zhenghaowu/lammps-install/bin/lmp` [UNVERIFIED]
- **LAMMPS flags:** `-k on g 1 -sf kk` (KOKKOS, 1 GPU) [UNVERIFIED]
- **Scheduler:** SLURM, partition `gpu4090`
- **File transfer:** DPDispatcher `SlurmContext` (automatic forward/backward)

`[UNVERIFIED]` — KOKKOS binary has not been tested on `gpu4090`. A `prepend_script` validation is mandatory for all HPC stages.

## Method Validation

The Kremer-Grest model is the canonical bead-spring model for polymer simulations, extensively validated for chain conformational properties. Reference: Kremer & Grest, *J. Chem. Phys.* 92, 5057 (1990). The physics, parameters, and LAMMPS scripts are identical to the completed local workflow (`bead-spring-rg/`, workflow ID `bead-spring-rg-2026-04-01`). No additional physics validation is required. The only new risk is KOKKOS GPU execution, covered by the pre-flight check in Stage 2.

Expected R_g for N=50 in good solvent: ~σ × 50^0.588 / √6 ≈ 3.6 σ.

## Computational Stages

### Stage 1: Structure Generation (AutoPoly)
- **Purpose:** Generate a LAMMPS data file for a single N=50 Kremer-Grest chain in an 18 σ box.
- **Backend:** Local (`omnischolar` conda environment)
- **Inputs:** None.
- **Parameters:**
  - AutoPoly `BeadSpringPolymer`: N=50, linear topology, box_size=18.0 σ, SAW placement
  - Same `generate_structure.py` as the validated local run
- **Success criteria:** `stage-1/N50.data` exists; max bond length < 1.35 σ; box length ≥ 18 σ.
- **Expected walltime:** < 1 min.
- **Known pitfalls:**
  - SAW overlap → FENE blowup in Stage 2. Safeguard: verify max bond length after generation.
  - Box too small → periodic image self-interaction. Safeguard: enforce L ≥ 5 × R_g_expected (= 18 σ).

### Stage 2: Minimization + Equilibration
- **Purpose:** Relax residual overlaps; equilibrate chain conformation to thermal equilibrium.
- **Backend:** HPC via DPDispatcher `SlurmContext`, partition `gpu4090`
- **Inputs:** `stage-1/N50.data`
- **Command:** `/gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -k on g 1 -sf kk -in in.equil` [UNVERIFIED]
- **prepend_script:** Run `/gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -k on g 1 -sf kk -h` and verify exit code 0 before job executes. Exit non-zero if verification fails.
- **SLURM resources:** partition `gpu4090`, qos `4gpus`, ntasks=1, cpus-per-task=1, gres=gpu:1
- **Parameters:**
  - Minimization: conjugate gradient, etol=1e-6, ftol=1e-8, maxiter=10000
  - NVT Langevin: T=1.0 ε/k_B, γ=1.0 τ⁻¹, dt=0.005 τ
  - Equilibration: 1×10⁴ τ (2×10⁶ steps)
  - R_g monitoring: `compute gyration` + `fix ave/time` every 100 τ → `equil_rg.dat`
- **Outputs forwarded back:** `equil.restart`, `log.lammps`, `equil_rg.dat`
- **Success criteria:** No LOST ATOMS error in `log.lammps`; temperature stable at T=1.0 ± 0.05; R_g trace shows no monotonic drift over last 50% of equilibration.
- **Expected walltime:** ~5 min (compute) + queue wait.
- **Known pitfalls:**
  - KOKKOS binary not compiled with GPU support → pre-flight `prepend_script` catches this before wasting queue time.
  - FENE blowup if minimization fails to resolve overlaps → check `log.lammps` for errors after minimization section.
  - Insufficient equilibration → inspect `equil_rg.dat` trace before starting Stage 3; extend if drift persists.

### Stage 3: Production + R_g Measurement
- **Purpose:** Collect equilibrium R_g samples for statistical averaging.
- **Backend:** HPC via DPDispatcher `SlurmContext`, partition `gpu4090`
- **Inputs:** `stage-2/equil.restart`
- **Command:** `/gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -k on g 1 -sf kk -in in.production` [UNVERIFIED]
- **SLURM resources:** partition `gpu4090`, qos `4gpus`, ntasks=1, cpus-per-task=1, gres=gpu:1
- **Parameters:**
  - NVT Langevin: T=1.0, γ=1.0 τ⁻¹, dt=0.005 τ
  - Production: 1×10⁴ τ (2×10⁶ steps)
  - R_g: `compute gyration` + `fix ave/time` every 100 τ (20000 steps) → ~100 samples → `rg_timeseries.dat`
- **Outputs forwarded back:** `rg_timeseries.dat`, `log.lammps`
- **Success criteria:** ≥ 50 approximately uncorrelated R_g samples; standard error of mean R_g < 5% of mean.
- **Expected walltime:** ~5 min (compute) + queue wait.
- **Known pitfalls:**
  - Sampling interval shorter than autocorrelation time → correlated samples. Safeguard: verify autocorrelation time < 50 τ during analysis.
  - Thermostat over-damping: γ=1.0 τ⁻¹ is the standard Kremer-Grest value; do not increase.

## Convergence Strategy

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Timestep dt | 0.005 τ | Standard for FENE+WCA; below 0.01 τ stability limit for stiff FENE bonds |
| Box size L | 18 σ | 5× expected R_g; prevents periodic image self-interaction |
| Equilibration length | 1×10⁴ τ | ~2.5× Rouse time for N=50 (τ_R ~ 4000 τ) |
| Production length | 1×10⁴ τ | ~100 R_g samples at 100 τ intervals |
| Sampling interval | 100 τ | Approximately decorrelated for N=50 chain dynamics |
| Thermostat damping γ | 1.0 τ⁻¹ | Standard Kremer-Grest value (Kremer & Grest 1990) |
| WCA cutoff | 2^(1/6) σ | Fixed by definition; no convergence testing needed |

## Expected Outputs

- `stage-1/N50.data` — LAMMPS data file (generated locally)
- `stage-3/rg_timeseries.dat` — R_g time series from production run
- Mean R_g ± standard error (expected ~3.6 σ, consistent with local run result)

## Resource Estimate

- Total walltime: ~15 min compute + SLURM queue wait (varies by cluster load)
- Storage: < 10 MB
- Memory: negligible
- SLURM jobs: 2 × (partition `gpu4090`, qos `4gpus`, ntasks=1, cpus-per-task=1, gres=gpu:1, ~10 min each)
- No individual stage exceeds 1 hour of compute time
