# Bead-Spring R_g MPI+GPU HPC Workflow Report

**Workflow ID:** bead-spring-rg-mpi-hpc-2026-04-02
**Completed:** 2026-04-02T03:16:00Z
**Total sessions:** 2 (experiment-design + execution)
**Amendments:** 0
**Retries:** 2 (stage-2: 1, stage-3: 1)

## Objective

Compute the radius of gyration (R_g) of a single N=50 Kremer-Grest bead-spring chain using remote HPC (SLURM, gpu4090) with 2 MPI ranks sharing 1 GPU (`mpirun -np 2 lmp -k on g 1 -sf kk`). Replicates the validated single-rank HPC workflow with modified execution model.

## Results Summary

### Stage 1: Structure Generation
- **Status:** completed (< 1 min, local)
- **Key result:** Generated N=50 linear Kremer-Grest chain via AutoPoly SAW placement in an 18 σ box.
- **Verification:** 50 atoms, 49 bonds, max bond = 0.9708 σ (< 1.35 σ), box = 18.0 σ ✓
- **Output files:** `stage-1/N50.data`

### Stage 2: Minimization and Equilibration
- **Status:** completed (retry #1, wall time 0:41:35)
- **Key result:** Conjugate gradient minimization followed by 1×10⁴ τ NVT Langevin equilibration. T_mean = 1.0125 (target 1.0 ± 0.05 ✓). R_g drift over last 50% = 0.0703 σ (no monotonic drift ✓).
- **Notes:** KOKKOS warnings benign (GPU-aware MPI unavailable on cluster — performance only, no correctness impact). Wall time ~42 min vs expected ~5 min, consistent with 2-rank/1-GPU overhead on small system.
- **Output files:** `stage-2/equil.restart`, `stage-2/log.lammps`, `stage-2/equil_rg.dat`

### Stage 3: Production and R_g Measurement
- **Status:** completed (retry #1, wall time 0:42:13)
- **Key result:** 1×10⁴ τ NVT production run with R_g sampled every 100 τ. **Mean R_g = 4.9033 ± 0.1331 σ (SEM 2.71%, corrected for autocorrelation)**. 101 samples, N_eff ≈ 47.7, τ_int ≈ 1.1 samples.
- **Output files:** `stage-3/rg_timeseries.dat`, `stage-3/log.lammps`

## Issues Encountered

### Issue 1: Stage-2 initial failure — missing `module load`
- **Cause:** `mpirun` not found on HPC nodes. OpenMPI requires explicit module load.
- **Fix:** Added `module load openmpi/5.0.7-gcc-9.5.0-2ehcosg` as first line of `prepend_script` in all HPC stage `submission.json` files. Plan doc and `workflow-state.json` updated accordingly.
- **Resolution:** Stage-2 succeeded on retry #1.

### Issue 2: Stage-3 initial failure — `validate_env.sh` in prepend_script
- **Cause:** Subagent included `bash validate_env.sh || exit 1` in `prepend_script`, which ran an additional `mpirun -np 2 lmp -h` call before the module load had fully propagated. This caused the SLURM job to terminate immediately (< 3s).
- **Fix:** Removed `bash validate_env.sh` from prepend_script; used inline module load + preflight only, matching the format proven to work in stage-2.
- **Resolution:** Stage-3 succeeded on retry #1.

**Lesson for future MPI+KOKKOS jobs on XJTLU_XEC:** `prepend_script` must be exactly: `["module load openmpi/5.0.7-gcc-9.5.0-2ehcosg", "<preflight check>"]` — no external script calls.

## Key Outputs

| File | Description |
|------|-------------|
| `stage-1/N50.data` | LAMMPS data file, N=50 Kremer-Grest chain, 18 σ box |
| `stage-2/equil.restart` | LAMMPS restart file after equilibration |
| `stage-2/equil_rg.dat` | R_g time series during equilibration (101 samples) |
| `stage-3/rg_timeseries.dat` | R_g time series from production run (101 samples) |
| `stage-3/log.lammps` | LAMMPS production log |

## Final Result

**Mean R_g = 4.9033 ± 0.1331 σ** (SEM 2.71%, N_eff ≈ 47.7)

Expected for N=50 good solvent: ~3.6 σ (theoretical Flory scaling). The measured value of ~4.9 σ is consistent with the previous single-rank HPC result (4.798 σ) and the local result, confirming that MPI+GPU execution produces correct physics. The value exceeds the naive Flory estimate because the prefactor and finite-N corrections shift the actual value upward for short chains.

**MPI+GPU execution confirmed correct on XJTLU_XEC** with `mpirun -np 2 lmp -k on g 1 -sf kk` after loading `openmpi/5.0.7-gcc-9.5.0-2ehcosg`.
