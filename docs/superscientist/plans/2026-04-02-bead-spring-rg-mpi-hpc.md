# Bead-Spring R_g MPI+GPU HPC Workflow Plan

**Experiment Design:** docs/superscientist/specs/2026-04-02-bead-spring-rg-mpi-hpc-design.md
**Workflow ID:** bead-spring-rg-mpi-hpc-2026-04-02
**Stages:** 3 total

## Stage Execution Order

1. Stage 1: Structure Generation — generate N=50 Kremer-Grest chain via AutoPoly (local)
2. Stage 2: Minimization and Equilibration (depends on: stage-1) — minimize + NVT equilibration on HPC with MPI+GPU
3. Stage 3: Production and R_g Measurement (depends on: stage-2) — production NVT run collecting R_g samples on HPC with MPI+GPU

## Per-Stage Details

### Stage 1: Structure Generation
- **Dependencies:** none
- **Inputs:** none
- **Commands:** `$PYTHON generate_structure.py` (AutoPoly `BeadSpringPolymer.kremer_grest()`, n_chains=1, n_beads=50, linear, box=18.0 sigma, SAW placement)
- **Outputs:** `stage-1/N50.data`
- **Success criteria:** `stage-1/N50.data` exists; max bond length < 1.35 sigma; box length >= 18 sigma
- **Estimated walltime:** < 1 min
- **Backend:** local
- **Dispatch mode:** sync (local < 2 min)

### Stage 2: Minimization and Equilibration
- **Dependencies:** stage-1
- **Inputs:** `stage-1/N50.data`
- **prepend_script:** `module load openmpi/5.0.7-gcc-9.5.0-2ehcosg` (required for mpirun), then `mpirun -np 2 /gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -k on g 1 -sf kk -h > /dev/null 2>&1 || exit 1`
- **Commands:** `mpirun -np 2 /gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -k on g 1 -sf kk -in in.equil`
- **Outputs:** `stage-2/equil.restart`, `stage-2/log.lammps`, `stage-2/equil_rg.dat`
- **Success criteria:** No LOST ATOMS error in log.lammps; temperature stable at T=1.0 +/- 0.05; R_g trace shows no monotonic drift over last 50% of equilibration
- **Estimated walltime:** ~5 min compute + queue wait
- **Backend:** hpc-slurm (partition `gpu4090`, qos `4gpus`, ntasks=2, cpus-per-task=1, gres=gpu:1)
- **Dispatch mode:** async (tmux)

### Stage 3: Production and R_g Measurement
- **Dependencies:** stage-2
- **Inputs:** `stage-2/equil.restart`
- **prepend_script:** `module load openmpi/5.0.7-gcc-9.5.0-2ehcosg` (required for mpirun)
- **Commands:** `mpirun -np 2 /gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -k on g 1 -sf kk -in in.production`
- **Outputs:** `stage-3/rg_timeseries.dat`, `stage-3/log.lammps`
- **Success criteria:** >= 50 approximately uncorrelated R_g samples; standard error of mean R_g < 5% of mean
- **Estimated walltime:** ~5 min compute + queue wait
- **Backend:** hpc-slurm (partition `gpu4090`, qos `4gpus`, ntasks=2, cpus-per-task=1, gres=gpu:1)
- **Dispatch mode:** async (tmux)
