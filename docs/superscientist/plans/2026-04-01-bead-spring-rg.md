# Bead-Spring Single Chain R_g Workflow Plan

**Experiment Design:** docs/superscientist/specs/2026-04-01-bead-spring-rg-design.md
**Workflow ID:** bead-spring-rg-2026-04-01
**Stages:** 3 total
**Workflow root:** bead-spring-rg/

## Stage Execution Order

1. Stage 1: Structure Generation — Generate N=50 Kremer-Grest chain data file via AutoPoly
2. Stage 2: Minimization and Equilibration (depends on: stage-1) — Minimize overlaps + NVT Langevin equilibration, write restart file
3. Stage 3: Production and R_g Measurement (depends on: stage-2) — Production NVT run collecting R_g time series via compute gyration

---

## Per-Stage Details

### Stage 1: Structure Generation

- **Dependencies:** none
- **Inputs:** none
- **Backend:** local
- **Dispatch mode:** sync (< 1 min)

**Commands:** Write and run the following Python script as `bead-spring-rg/stage-1/generate_structure.py`:

```python
import math
import os
from AutoPoly import BeadSpringPolymer

N = 50
rg_expected = N**0.588 / math.sqrt(6)
box_size = max(10.0, 5.0 * rg_expected)

os.makedirs("stage-1", exist_ok=True)

polymer = BeadSpringPolymer.kremer_grest(
    n_chains=1,
    n_beads=N,
    box_length=box_size,
)
polymer.write_lammps_data("stage-1/N50.data")
```

Run with:
```bash
cd bead-spring-rg
/Users/zhenghaowu/miniconda3/envs/omnischolar/bin/python3 stage-1/generate_structure.py
```

**Outputs:**
- `stage-1/N50.data`

**Success criteria:** Data file exists; max bond length < 1.35 sigma; box length >= 18 sigma.

**Estimated walltime:** < 1 min

---

### Stage 2: Minimization and Equilibration

- **Dependencies:** stage-1
- **Inputs:** `stage-1/N50.data`
- **Backend:** local
- **Dispatch mode:** async via tmux (~5 min)

**Commands:** Write the LAMMPS input script `bead-spring-rg/stage-2/in.equil` and run:

```lammps
# Minimization + Equilibration: Kremer-Grest single chain N=50
units          lj
atom_style     bond
boundary       p p p

read_data      ../stage-1/N50.data

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

Run with:
```bash
cd bead-spring-rg/stage-2
/Users/zhenghaowu/miniconda3/envs/omnischolar/bin/lmp -in in.equil
```

**Outputs:**
- `stage-2/equil.restart`
- `stage-2/log.lammps`
- `stage-2/equil_rg.dat` (for equilibration check)

**Success criteria:** No LOST ATOMS error; temperature stable at T=1.0 +/- 0.05; R_g trace shows no monotonic drift over last 50% of equilibration.

**Estimated walltime:** ~5 min

---

### Stage 3: Production and R_g Measurement

- **Dependencies:** stage-2
- **Inputs:** `stage-2/equil.restart`
- **Backend:** local
- **Dispatch mode:** async via tmux (~5 min)

**Commands:** Write the LAMMPS input script `bead-spring-rg/stage-3/in.production` and run:

```lammps
# Production: Kremer-Grest single chain N=50, R_g sampling
units          lj
atom_style     bond
boundary       p p p

read_restart   ../stage-2/equil.restart

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

Run with:
```bash
cd bead-spring-rg/stage-3
/Users/zhenghaowu/miniconda3/envs/omnischolar/bin/lmp -in in.production
```

**Outputs:**
- `stage-3/rg_timeseries.dat`
- `stage-3/log.lammps`

**Success criteria:** >= 50 approximately uncorrelated R_g samples; standard error of mean R_g < 5% of mean.

**Estimated walltime:** ~5 min
