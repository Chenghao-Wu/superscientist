# Bead-Spring Single Chain R_g Workflow Plan (HPC)

**Experiment Design:** docs/superscientist/specs/2026-04-02-bead-spring-rg-hpc-design.md
**Workflow ID:** bead-spring-rg-hpc-2026-04-02
**Workflow root:** bead-spring-rg-hpc/
**Stages:** 3 total

## Stage Execution Order

1. Stage 1: Structure Generation — Generate N=50 Kremer-Grest chain data file via AutoPoly (local)
2. Stage 2: Minimization and Equilibration (depends on: stage-1) — Minimize + NVT Langevin equilibration on HPC GPU, write restart file
3. Stage 3: Production and R_g Measurement (depends on: stage-2) — Production NVT run on HPC GPU, collect R_g time series

---

## Per-Stage Details

### Stage 1: Structure Generation

- **Dependencies:** none
- **Inputs:** none
- **Backend:** local
- **Dispatch mode:** sync (< 1 min)

**Script:** Write and run `bead-spring-rg-hpc/stage-1/generate_structure.py`:

```python
"""
Stage 1: Structure Generation
Generate a single N=50 Kremer-Grest bead-spring chain in an 18-sigma box.
"""
import math
import shutil
from AutoPoly import BeadSpringPolymer, BeadType, System

N = 50
BOX_SIZE = 18.0  # sigma; >= max(10, 5 * R_g_expected)

rg_expected = N ** 0.588 / math.sqrt(6)
print(f"Expected R_g ~ {rg_expected:.2f} sigma")
print(f"Box size: {BOX_SIZE:.1f} sigma (>= {5 * rg_expected:.2f} = 5 * R_g_expected)")

system = System(out=".")
kg_bead = BeadType(name="KG", mass=1.0, epsilon=1.0, sigma=1.0)

polymer = BeadSpringPolymer(
    name="N50",
    system=system,
    n_chains=1,
    bead_types=[kg_bead],
    sequence=[("KG", N)],
    topology="linear",
    bond_length=0.97,
    bond_style="fene",
    k_bond=30.0,
    fene_r0=1.5,
    pair_style="wca",
    box_size=BOX_SIZE,
    generation_method="saw",
)

polymer.saw_generate()
polymer.generate_data_file()
shutil.copy("N50/polymer.data", "N50.data")
print("Output: N50.data")
```

**Command:**
```bash
cd bead-spring-rg-hpc
/Users/zhenghaowu/miniconda3/envs/omnischolar/bin/python3 stage-1/generate_structure.py
```

**Outputs:**
- `stage-1/N50.data`

**Success criteria:** `stage-1/N50.data` exists; max bond length < 1.35 sigma; box length >= 18 sigma.

**Estimated walltime:** < 1 min

---

### Stage 2: Minimization and Equilibration

- **Dependencies:** stage-1
- **Inputs:** `stage-1/N50.data`
- **Backend:** hpc-slurm
- **Dispatch mode:** async via tmux (remote HPC, ~5 min compute + queue wait)

**LAMMPS input script** (`bead-spring-rg-hpc/stage-2/in.equil`):

```lammps
# Minimization + Equilibration: Kremer-Grest single chain N=50
units          lj
atom_style     bond
boundary       p p p

read_data      N50.data

# WCA potential (purely repulsive LJ)
pair_style     lj/cut 1.12246204830937
pair_coeff     1 1 1.0 1.0 1.12246204830937
pair_modify    shift yes

# FENE bonds
bond_style     fene
bond_coeff     1 30.0 1.5 1.0 1.0
special_bonds  fene

# Minimization
minimize       1.0e-6 1.0e-8 10000 100000

# Reset timestep after minimization
reset_timestep 0

# NVT Langevin equilibration
timestep       0.005
fix            1 all langevin 1.0 1.0 1.0 12345
fix            2 all nve

# Monitor R_g during equilibration
compute        gyr all gyration
fix            rg_ave all ave/time 20000 1 20000 c_gyr file equil_rg.dat

thermo         10000
thermo_style   custom step temp pe ke etotal c_gyr

run            2000000

# Write restart for production
write_restart  equil.restart
```

**DPDispatcher submission.json** (`bead-spring-rg-hpc/stage-2/submission.json`):

```json
{
  "work_base": ".",
  "machine": {
    "batch_type": "Slurm",
    "context_type": "SSHContext",
    "local_root": "<abs-path-to>/bead-spring-rg-hpc",
    "remote_root": "/gpfs/home/che/zhenghaowu/bead-spring-rg",
    "remote_profile": {
      "hostname": "10.7.91.101",
      "username": "zhenghaowu",
      "port": 22
    }
  },
  "resources": {
    "number_node": 1,
    "cpu_per_node": 1,
    "gpu_per_node": 1,
    "queue_name": "gpu4090",
    "group_size": 1,
    "custom_flags": ["#SBATCH --qos=4gpus", "#SBATCH --ntasks=1", "#SBATCH --cpus-per-task=1", "#SBATCH --gres=gpu:1"]
  },
  "task_list": [
    {
      "command": "/gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -k on g 1 -sf kk -in in.equil",
      "task_work_path": "stage-2",
      "forward_files": ["in.equil", "N50.data"],
      "backward_files": ["equil.restart", "log.lammps", "equil_rg.dat", "log", "err"],
      "prepend_script": [
        "#!/bin/bash",
        "/gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -k on g 1 -sf kk -h > /dev/null 2>&1 || { echo 'PREFLIGHT FAIL: LAMMPS KOKKOS not available'; exit 1; }",
        "echo 'PREFLIGHT OK: LAMMPS KOKKOS verified'"
      ]
    }
  ]
}
```

**Outputs:**
- `stage-2/equil.restart`
- `stage-2/log.lammps`
- `stage-2/equil_rg.dat`

**Success criteria:** No LOST ATOMS error in `log.lammps`; temperature stable at T=1.0 ± 0.05; R_g trace shows no monotonic drift over last 50% of equilibration.

**Estimated walltime:** ~5 min compute + SLURM queue wait

---

### Stage 3: Production and R_g Measurement

- **Dependencies:** stage-2
- **Inputs:** `stage-2/equil.restart`
- **Backend:** hpc-slurm
- **Dispatch mode:** async via tmux (remote HPC, ~5 min compute + queue wait)

**LAMMPS input script** (`bead-spring-rg-hpc/stage-3/in.production`):

```lammps
# Production: Kremer-Grest single chain N=50, R_g sampling
units          lj
atom_style     bond
boundary       p p p

read_restart   equil.restart

# WCA potential
pair_style     lj/cut 1.12246204830937
pair_coeff     1 1 1.0 1.0 1.12246204830937
pair_modify    shift yes

# FENE bonds
bond_style     fene
bond_coeff     1 30.0 1.5 1.0 1.0
special_bonds  fene

# Reset timestep
reset_timestep 0

# NVT Langevin production
timestep       0.005
fix            1 all langevin 1.0 1.0 1.0 67890
fix            2 all nve

# R_g measurement
compute        gyr all gyration
fix            rg_ave all ave/time 20000 1 20000 c_gyr file rg_timeseries.dat

thermo         10000
thermo_style   custom step temp pe ke etotal c_gyr

run            2000000
```

**DPDispatcher submission.json** (`bead-spring-rg-hpc/stage-3/submission.json`):

```json
{
  "work_base": ".",
  "machine": {
    "batch_type": "Slurm",
    "context_type": "SSHContext",
    "local_root": "<abs-path-to>/bead-spring-rg-hpc",
    "remote_root": "/gpfs/home/che/zhenghaowu/bead-spring-rg",
    "remote_profile": {
      "hostname": "10.7.91.101",
      "username": "zhenghaowu",
      "port": 22
    }
  },
  "resources": {
    "number_node": 1,
    "cpu_per_node": 1,
    "gpu_per_node": 1,
    "queue_name": "gpu4090",
    "group_size": 1,
    "custom_flags": ["#SBATCH --qos=4gpus", "#SBATCH --ntasks=1", "#SBATCH --cpus-per-task=1", "#SBATCH --gres=gpu:1"]
  },
  "task_list": [
    {
      "command": "/gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -k on g 1 -sf kk -in in.production",
      "task_work_path": "stage-3",
      "forward_files": ["in.production", "equil.restart"],
      "backward_files": ["rg_timeseries.dat", "log.lammps", "log", "err"],
      "prepend_script": []
    }
  ]
}
```

**Outputs:**
- `stage-3/rg_timeseries.dat`
- `stage-3/log.lammps`

**Success criteria:** >= 50 approximately uncorrelated R_g samples; standard error of mean R_g < 5% of mean.

**Estimated walltime:** ~5 min compute + SLURM queue wait
