# Bead-Spring Polymer Rg Workflow Plan

**Experiment Design:** `docs/superscientist/specs/2026-03-31-bead-spring-rg-design.md`
**Workflow ID:** `bead-spring-rg-2026-03-31`
**Workflow Root:** `bead-spring-rg/`
**Stages:** 5 total

## Stage Execution Order

1. Stage 1: Structure Generation — generate bead-spring LAMMPS data file via AutoPoly
2. Stage 2: Energy Minimization (depends on: stage-1) — remove initial steric clashes
3. Stage 3: NVT Equilibration (depends on: stage-2) — thermally relax chain conformation
4. Stage 4: NVT Production (depends on: stage-3) — collect equilibrium Rg samples
5. Stage 5: Analysis (depends on: stage-4) — compute ⟨Rg⟩ and compare to Flory prediction

## Per-Stage Details

### Stage 1: Structure Generation
- **Dependencies:** none
- **Inputs:** `docs/superscientist/specs/2026-03-31-bead-spring-rg-design.md`
- **Commands:**
  ```bash
  cd bead-spring-rg/stage-1
  # Write autopoly_config.json (subagent creates this)
  /Users/zhenghaowu/miniconda3/envs/omnischolar/bin/autopoly validate autopoly_config.json
  /Users/zhenghaowu/miniconda3/envs/omnischolar/bin/autopoly generate autopoly_config.json
  ```
  AutoPoly config must specify: bead-spring CG model, chain_num=1, N=30 beads, box_size=50.0σ, mass=1, sigma=1, epsilon=1.
- **Outputs:** `stage-1/autopoly_config.json`, `stage-1/data.polymer`
- **Success criteria:** `data.polymer` contains exactly 30 atoms and 29 bonds; no bond length exceeds R₀=1.5σ
- **Estimated walltime:** <1 s
- **Backend:** local
- **Dispatch mode:** sync

### Stage 2: Energy Minimization
- **Dependencies:** stage-1
- **Inputs:** `stage-1/data.polymer`
- **Commands:**
  ```bash
  cd bead-spring-rg/stage-2
  # Subagent writes in.minimize (see parameters below)
  /Users/zhenghaowu/miniconda3/envs/omnischolar/bin/lmp < in.minimize
  ```
  Key LAMMPS commands in `in.minimize`:
  ```lammps
  units lj
  atom_style bond
  boundary p p p
  read_data ../stage-1/data.polymer
  pair_style lj/cut 1.122
  pair_coeff * * 1.0 1.0
  pair_modify shift yes
  bond_style fene
  bond_coeff 1 30.0 1.5 1.0 1.0
  special_bonds fene
  neighbor 0.3 bin
  minimize 1.0e-6 1.0e-6 10000 100000
  write_restart restart.minimize
  ```
- **Outputs:** `stage-2/in.minimize`, `stage-2/log.minimize`, `stage-2/restart.minimize`
- **Success criteria:** Minimization completes; max force per atom < 10 ε/σ; all bond lengths < 1.4σ
- **Estimated walltime:** <1 s
- **Backend:** local
- **Dispatch mode:** sync

### Stage 3: NVT Equilibration
- **Dependencies:** stage-2
- **Inputs:** `stage-2/restart.minimize`, `stage-1/data.polymer`
- **Commands:**
  ```bash
  cd bead-spring-rg/stage-3
  # Subagent writes in.equil (see parameters below)
  /Users/zhenghaowu/miniconda3/envs/omnischolar/bin/lmp < in.equil
  ```
  Key LAMMPS commands in `in.equil`:
  ```lammps
  units lj
  atom_style bond
  boundary p p p
  read_restart ../stage-2/restart.minimize
  pair_style lj/cut 1.122
  pair_coeff * * 1.0 1.0
  pair_modify shift yes
  bond_style fene
  bond_coeff 1 30.0 1.5 1.0 1.0
  special_bonds fene
  neighbor 0.3 bin
  compute rg all gyration
  thermo 1000
  thermo_style custom step temp pe ke etotal c_rg
  fix 1 all nvt temp 1.0 1.0 0.5
  timestep 0.005
  run 1000000
  write_restart restart.equil
  ```
- **Outputs:** `stage-3/in.equil`, `stage-3/log.equil`, `stage-3/restart.equil`
- **Success criteria:** Potential energy drift < 1% over last 20% of run; Rg time series shows no systematic trend
- **Estimated walltime:** <1 min
- **Backend:** local
- **Dispatch mode:** sync (< 2 min expected)

### Stage 4: NVT Production
- **Dependencies:** stage-3
- **Inputs:** `stage-3/restart.equil`
- **Commands:**
  ```bash
  cd bead-spring-rg/stage-4
  # Subagent writes in.production (see parameters below)
  /Users/zhenghaowu/miniconda3/envs/omnischolar/bin/lmp < in.production
  ```
  Key LAMMPS commands in `in.production`:
  ```lammps
  units lj
  atom_style bond
  boundary p p p
  read_restart ../stage-3/restart.equil
  pair_style lj/cut 1.122
  pair_coeff * * 1.0 1.0
  pair_modify shift yes
  bond_style fene
  bond_coeff 1 30.0 1.5 1.0 1.0
  special_bonds fene
  neighbor 0.3 bin
  compute rg all gyration
  thermo 1000
  thermo_style custom step temp pe ke etotal c_rg
  fix 1 all nvt temp 1.0 1.0 0.5
  timestep 0.005
  run 5000000
  ```
- **Outputs:** `stage-4/in.production`, `stage-4/log.production`
- **Success criteria:** Block-averaged Rg converges across 5 equal blocks (variation < 5% of mean); std error < 0.1σ
- **Estimated walltime:** <5 min
- **Backend:** local
- **Dispatch mode:** async (tmux, > 2 min expected)

### Stage 5: Analysis
- **Dependencies:** stage-4
- **Inputs:** `stage-4/log.production`
- **Commands:**
  ```bash
  cd bead-spring-rg/stage-5
  # Subagent writes analyze_rg.py
  /Users/zhenghaowu/miniconda3/envs/omnischolar/bin/python3 analyze_rg.py
  ```
  `analyze_rg.py` must:
  1. Parse `c_rg` column from `../stage-4/log.production`
  2. Discard first 20% of samples as burn-in
  3. Compute block averages over 5 equal blocks
  4. Report ⟨Rg⟩ ± std error; confirm result in [2.8, 3.2]σ
  5. Save time-series plot to `rg_result.png` and numeric result to `rg_result.txt`
- **Outputs:** `stage-5/analyze_rg.py`, `stage-5/rg_result.png`, `stage-5/rg_result.txt`
- **Success criteria:** mean Rg ∈ [2.8, 3.2]σ; standard error < 0.1σ; block averages mutually consistent within 1 std error
- **Estimated walltime:** <1 s
- **Backend:** local
- **Dispatch mode:** sync
