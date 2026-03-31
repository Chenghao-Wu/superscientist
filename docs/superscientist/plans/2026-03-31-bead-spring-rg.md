# Bead-Spring R_g Scaling Workflow Plan

**Experiment Design:** docs/superscientist/specs/2026-03-31-bead-spring-rg-design.md
**Workflow ID:** bead-spring-rg-2026-03-31
**Stages:** 4 total
**Workflow root:** bead-spring-rg/

## Stage Execution Order

1. Stage 1: Structure Generation — Generate 15 LAMMPS data files via AutoPoly (N=10,20,50,100,200 × 3 runs)
2. Stage 2: Minimization and Equilibration (depends on: stage-1) — Minimize + NVT Langevin equilibration for all 15 systems, write restart files
3. Stage 3: Production and R_g Sampling (depends on: stage-2) — Production NVT runs collecting R_g time series for all 15 systems
4. Stage 4: Analysis and Scaling Fit (depends on: stage-3) — Average R_g per N, weighted log-log regression, plot and report Flory exponent

---

## Per-Stage Details

### Stage 1: Structure Generation

- **Dependencies:** none
- **Inputs:** none
- **Backend:** local
- **Dispatch mode:** sync (< 2 min total)

**Commands:** Write and run the following Python script as `bead-spring-rg/stage-1/generate_structures.py`:

```python
import math
import os
import sys

sys.path.insert(0, '/Users/zhenghaowu/miniconda3/envs/omnischolar/lib/python3.x/site-packages')
from AutoPoly import BeadSpringPolymer, System

PYTHON = "/Users/zhenghaowu/miniconda3/envs/omnischolar/bin/python3"
OUT_DIR = "stage-1"
os.makedirs(OUT_DIR, exist_ok=True)

N_VALUES = [10, 20, 50, 100, 200]
N_RUNS = 3

for N in N_VALUES:
    rg_expected = N**0.588 / math.sqrt(6)
    box_size = max(10.0, 5.0 * rg_expected)
    for run in range(1, N_RUNS + 1):
        name = f"N{N}_run{run}"
        system = System(out=OUT_DIR)
        polymer = BeadSpringPolymer.kremer_grest(
            name=name,
            system=system,
            n_chains=1,
            n_beads=N,
            topology="linear",
            density=N / box_size**3,
        )
        polymer.saw_generate()
        polymer.generate_data_file()
        # Output: stage-1/{name}/{name}.data — rename to flat structure
        import shutil
        src = os.path.join(OUT_DIR, name, f"{name}.data")
        dst = os.path.join(OUT_DIR, f"{name}.data")
        shutil.move(src, dst)
        print(f"Generated {dst}")
```

Run with:
```bash
cd bead-spring-rg
/Users/zhenghaowu/miniconda3/envs/omnischolar/bin/python3 stage-1/generate_structures.py
```

**Outputs:**
- `stage-1/N10_run1.data` through `stage-1/N200_run3.data` (15 files)

**Success criteria:** All 15 `.data` files exist; max bond length < 1.35σ in each (verify with lammpsio or grep); box length > 5 × R_g_expected for each N.

**Estimated walltime:** < 1 min

---

### Stage 2: Minimization and Equilibration

- **Dependencies:** stage-1
- **Inputs:** 15 data files from `stage-1/`
- **Backend:** local
- **Dispatch mode:** async via tmux (total ~30–60 min)

**Commands:** For each `(N, run)` pair, write a LAMMPS input script `stage-2/in.equil_N{N}_run{run}` with the following template, then run LAMMPS:

```lammps
# Minimization + Equilibration: Kremer-Grest single chain
# N={N}, run={run}
units          lj
atom_style     bond
boundary       p p p

read_data      ../stage-1/N{N}_run{run}.data

pair_style     lj/cut 1.1224
pair_coeff     1 1 1.0 1.0 1.1224
pair_modify    shift yes

bond_style     fene
bond_coeff     1 30.0 1.5 1.0 1.0
special_bonds  fene

neighbor       0.3 bin
neigh_modify   every 1 delay 0 check yes

# Minimize
minimize       1.0e-6 1.0e-8 10000 100000

# Equilibration NVT Langevin
reset_timestep 0
timestep       0.005

compute        rg all gyration

fix            lang all langevin 1.0 1.0 1.0 {SEED}
fix            nve  all nve

fix            rg_out all ave/time 200000 1 200000 c_rg file ../stage-2/rg_equil_N{N}_run{run}.txt

thermo         200000
thermo_style   custom step temp pe ke etotal c_rg

run            4000000

write_restart  ../stage-2/N{N}_run{run}.restart
```

Where `{SEED}` is a unique random integer per run (e.g., `run * 1000 + N`).

Run each with:
```bash
/Users/zhenghaowu/miniconda3/envs/omnischolar/bin/lmp -in stage-2/in.equil_N{N}_run{run} -log stage-2/log.equil_N{N}_run{run}
```

All 15 runs are independent — launch in parallel (e.g., loop with background `&` or a tmux session per chain length).

**Outputs:**
- `stage-2/N{N}_run{run}.restart` (15 restart files)
- `stage-2/rg_equil_N{N}_run{run}.txt` (15 equilibration R_g traces)
- `stage-2/log.equil_N{N}_run{run}` (15 LAMMPS log files)

**Success criteria:** All 15 restart files exist; all 15 R_g trace files exist; no "LOST ATOMS" in any log file; R_g(t) shows no monotonic drift over last 50% of each trace.

**Estimated walltime:** ~1–30 min per run; ~30–60 min total if parallelized across cores.

---

### Stage 3: Production and R_g Sampling

- **Dependencies:** stage-2
- **Inputs:** 15 restart files from `stage-2/`
- **Backend:** local
- **Dispatch mode:** async via tmux (total ~1–2 hr)

**Commands:** For each `(N, run)` pair, write `stage-3/in.prod_N{N}_run{run}`:

```lammps
# Production: Kremer-Grest single chain
# N={N}, run={run}
units          lj
atom_style     bond
boundary       p p p

read_restart   ../stage-2/N{N}_run{run}.restart

pair_style     lj/cut 1.1224
pair_coeff     1 1 1.0 1.0 1.1224
pair_modify    shift yes

bond_style     fene
bond_coeff     1 30.0 1.5 1.0 1.0
special_bonds  fene

neighbor       0.3 bin
neigh_modify   every 1 delay 0 check yes

reset_timestep 0
timestep       0.005

compute        rg all gyration

fix            lang all langevin 1.0 1.0 1.0 {SEED2}
fix            nve  all nve

fix            rg_out all ave/time 20000 1 20000 c_rg file ../stage-3/rg_N{N}_run{run}.txt

thermo         200000
thermo_style   custom step temp pe ke etotal c_rg

run            4000000
```

Where `{SEED2}` is a different seed from equilibration (e.g., `run * 1000 + N + 50000`).

Run each with:
```bash
/Users/zhenghaowu/miniconda3/envs/omnischolar/bin/lmp -in stage-3/in.prod_N{N}_run{run} -log stage-3/log.prod_N{N}_run{run}
```

**Outputs:**
- `stage-3/rg_N{N}_run{run}.txt` (15 R_g time series files, ~200 frames each)

**Success criteria:** All 15 files exist; each has ≥ 200 data rows; block-averaged R_g stderr < 2% of mean for each run.

**Estimated walltime:** ~2–60 min per run; ~1–2 hr total parallelized.

---

### Stage 4: Analysis and Scaling Fit

- **Dependencies:** stage-3
- **Inputs:** 15 R_g time series from `stage-3/`
- **Backend:** local
- **Dispatch mode:** sync (< 1 min)

**Commands:** Write and run `bead-spring-rg/stage-4/analyze_rg.py`:

```python
import numpy as np
import matplotlib.pyplot as plt
import os

N_VALUES = [10, 20, 50, 100, 200]
N_RUNS = 3
IN_DIR = "../stage-3"
OUT_DIR = "."
os.makedirs(OUT_DIR, exist_ok=True)

# Collect R_g mean and stderr for each N
rg_means = []
rg_errs = []

for N in N_VALUES:
    all_rg = []
    for run in range(1, N_RUNS + 1):
        fname = os.path.join(IN_DIR, f"rg_N{N}_run{run}.txt")
        data = np.loadtxt(fname, comments='#')
        # Column 1 = timestep, column 2 = R_g (fix ave/time output)
        rg_vals = data[:, 1] if data.ndim > 1 else data
        all_rg.extend(rg_vals.tolist())
    all_rg = np.array(all_rg)
    rg_means.append(np.mean(all_rg))
    rg_errs.append(np.std(all_rg) / np.sqrt(len(all_rg)))

rg_means = np.array(rg_means)
rg_errs = np.array(rg_errs)
N_arr = np.array(N_VALUES, dtype=float)

# Save summary CSV
header = "N,rg_mean,rg_stderr"
np.savetxt(os.path.join(OUT_DIR, "rg_summary.csv"),
           np.column_stack([N_arr, rg_means, rg_errs]),
           delimiter=",", header=header, comments="")

# Weighted log-log regression
log_N = np.log(N_arr)
log_rg = np.log(rg_means)
weights = 1.0 / rg_errs**2

W = np.sum(weights)
Wx = np.sum(weights * log_N)
Wy = np.sum(weights * log_rg)
Wxx = np.sum(weights * log_N**2)
Wxy = np.sum(weights * log_N * log_rg)

nu = (W * Wxy - Wx * Wy) / (W * Wxx - Wx**2)
log_b = (Wy - nu * Wx) / W
b = np.exp(log_b)

# R^2
rg_fit = b * N_arr**nu
ss_res = np.sum((rg_means - rg_fit)**2)
ss_tot = np.sum((rg_means - np.mean(rg_means))**2)
r2 = 1 - ss_res / ss_tot

# Save fit results
with open(os.path.join(OUT_DIR, "fit_results.txt"), "w") as f:
    f.write(f"Flory exponent nu = {nu:.4f}\n")
    f.write(f"Prefactor b = {b:.4f}\n")
    f.write(f"R^2 = {r2:.6f}\n")
    f.write(f"Expected nu (good solvent) = 0.588\n")
    f.write(f"nu in acceptable range [0.55, 0.62]: {0.55 <= nu <= 0.62}\n")

print(f"nu = {nu:.4f}, b = {b:.4f}, R^2 = {r2:.6f}")

# Plot
fig, ax = plt.subplots(figsize=(5, 4))
N_plot = np.logspace(np.log10(8), np.log10(250), 100)
ax.plot(N_plot, b * N_plot**nu, 'k-', label=f'fit: $R_g = {b:.3f} N^{{{nu:.3f}}}$')
ax.errorbar(N_arr, rg_means, yerr=rg_errs, fmt='o', color='tab:blue', label='simulation')
ax.set_xscale('log')
ax.set_yscale('log')
ax.set_xlabel('Chain length N')
ax.set_ylabel(r'$R_g$ ($\sigma$)')
ax.set_title(r'$R_g$ scaling: Kremer-Grest single chain')
ax.legend()
fig.tight_layout()
fig.savefig(os.path.join(OUT_DIR, "rg_scaling_fit.png"), dpi=150)
print("Plot saved to rg_scaling_fit.png")
```

Run with:
```bash
cd bead-spring-rg/stage-4
/Users/zhenghaowu/miniconda3/envs/omnischolar/bin/python3 analyze_rg.py
```

**Outputs:**
- `stage-4/rg_summary.csv` — R_g mean ± stderr for each N
- `stage-4/rg_scaling_fit.png` — log-log plot with power-law fit
- `stage-4/fit_results.txt` — fitted ν, b, R²

**Success criteria:** All 3 output files exist; fitted ν ∈ [0.55, 0.62]; R² > 0.99.

**Estimated walltime:** < 1 min
