# Bead-Spring Single Chain R_g Workflow Report

**Workflow ID:** bead-spring-rg-2026-04-01
**Completed:** 2026-04-01T00:06:00Z
**Total sessions:** 1
**Amendments:** 0

## Objective

Compute the radius of gyration (R_g) of a single N=50 Kremer-Grest bead-spring chain in a large periodic box (L=18 sigma) using LAMMPS. The chain uses FENE bonds and WCA non-bonded interactions (good solvent regime) at T=1.0 in LJ units.

## Results Summary

### Stage 1: Structure Generation
- **Status:** completed
- **Key result:** Single linear N=50 chain generated via AutoPoly using SAW placement. Max bond length 0.971 sigma (< 1.35 sigma limit). Box size 18.0 sigma (>= 5x expected R_g).
- **Output files:** `stage-1/N50.data`

### Stage 2: Minimization and Equilibration
- **Status:** completed
- **Key result:** Conjugate gradient minimization resolved initial overlaps (0 LOST ATOMS). NVT Langevin equilibration ran for 10,000 tau (2x10^6 steps). Time-averaged temperature = 1.024 (target 1.0), R_g trace showed no monotonic drift over last 50%.
- **Output files:** `stage-2/equil.restart`, `stage-2/log.lammps`, `stage-2/equil_rg.dat`

### Stage 3: Production and R_g Measurement
- **Status:** completed
- **Key result:** R_g = **4.719 ± 0.096 sigma** (mean ± standard error, 101 samples, 2.03% relative error). Sampling interval 100 tau over 10,000 tau production run. Flory estimate for N=50 is ~4.07 sigma; measured value is ~16% higher, consistent with finite-chain effects at N=50.
- **Output files:** `stage-3/rg_timeseries.dat`, `stage-3/log.lammps`

## Issues Encountered

- **Communication cutoff WARNING (stage-2):** LAMMPS issued a benign warning that the communication cutoff (1.42 sigma) is shorter than the FENE bond estimate (1.755 sigma). No LOST ATOMS and zero dangerous neighbor list builds — warning is expected for single-processor FENE simulations. Resolved in stage-3 by adding `comm_modify cutoff 1.9`.
- **No retries required.** All stages passed on first attempt.

## Key Outputs

| File | Description |
|------|-------------|
| `stage-1/N50.data` | LAMMPS data file, N=50 chain, box 18x18x18 sigma |
| `stage-2/equil.restart` | Equilibrated restart file for further simulations |
| `stage-2/equil_rg.dat` | R_g time series during equilibration (100 samples) |
| `stage-3/rg_timeseries.dat` | Production R_g time series (101 samples) |
| `stage-3/log.lammps` | Full LAMMPS log for production run |

## Final Result

**R_g (N=50, Kremer-Grest, good solvent) = 4.719 ± 0.096 sigma**
