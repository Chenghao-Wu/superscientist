# Bead-Spring R_g HPC Workflow Plan

**Experiment Design:** docs/superscientist/specs/2026-04-01-bead-spring-rg-hpc-design.md
**Workflow ID:** bead-spring-rg-hpc-2026-04-01
**Workflow Root:** bead-spring-rg-hpc/
**Stages:** 3 total

## Stage Execution Order

1. Stage 1: Structure Generation — generate N50.data locally via AutoPoly
2. Stage 2: Minimization and Equilibration (depends on: stage-1) — LAMMPS minimize + NVT on XJTLU_XEC GPU
3. Stage 3: Production and R_g Measurement (depends on: stage-2) — LAMMPS NVT + R_g sampling on XJTLU_XEC GPU

## Per-Stage Details

### Stage 1: Structure Generation
- **Dependencies:** none
- **Backend:** local (omnischolar conda env)
- **Dispatch mode:** sync (< 1 min)
- **Inputs:** none
- **Outputs:** `stage-1/N50.data`
- **Commands:**
  ```bash
  cd bead-spring-rg-hpc
  mkdir -p stage-1
  # Write stage-1/generate_structure.py (copy from bead-spring-rg/stage-1/generate_structure.py,
  # update out= to "stage-1" and shutil.copy target to "stage-1/N50.data")
  /Users/zhenghaowu/miniconda3/envs/omnischolar/bin/python3 stage-1/generate_structure.py
  ```
  The script uses `AutoPoly.BeadSpringPolymer` with `box_size=18.0`, `generation_method="saw"`, writes
  `N50/polymer.data`, then copies to `stage-1/N50.data`.
- **Success criteria:** Data file written; max bond length < 1.35σ; box length ≥ 18σ
- **Estimated walltime:** < 1 min

### Stage 2: Minimization and Equilibration
- **Dependencies:** stage-1
- **Backend:** hpc-xjtlu (XJTLU_XEC via DPDispatcher SSHContext + Slurm)
- **Dispatch mode:** async via tmux (2–5 min on GPU)
- **Inputs:** `stage-1/N50.data`
- **Outputs:** `stage-2/equil.restart`, `stage-2/log.lammps`, `stage-2/equil_rg.dat`
- **Commands:**
  ```bash
  cd bead-spring-rg-hpc

  # 1. Write stage-2/in.equil (LAMMPS input script):
  #    - read_data N50.data
  #    - pair_style lj/cut 1.12246204830937; pair_coeff 1 1 1.0 1.0 1.12246204830937; pair_modify shift yes
  #    - bond_style fene; bond_coeff 1 30.0 1.5 1.0 1.0; special_bonds fene
  #    - minimize 1.0e-6 1.0e-8 10000 100000
  #    - reset_timestep 0; timestep 0.005
  #    - fix 1 all langevin 1.0 1.0 1.0 12345; fix 2 all nve
  #    - compute gyr all gyration
  #    - fix rg_ave all ave/time 20000 1 20000 c_gyr file equil_rg.dat
  #    - thermo 10000; thermo_style custom step temp pe ke etotal c_gyr
  #    - run 2000000; write_restart equil.restart

  # 2. Write stage-2/submission.json for DPDispatcher:
  #    {
  #      "work_base": ".",
  #      "machine": {"$ref": "../../dpdisp-submit/XJTLU_XEC.json"},
  #      "resources": {
  #        "queue_name": "gpu4090", "number_node": 1, "cpu_per_node": 1, "gpu_per_node": 1,
  #        "custom_flags": ["--gres=gpu:1", "--qos=4gpus", "--mem-per-gpu=10G"], "group_size": 1
  #      },
  #      "task_list": [{
  #        "command": "/gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -sf gpu -in in.equil > log 2> err",
  #        "task_work_path": ".",
  #        "forward_files": ["in.equil", "N50.data"],
  #        "backward_files": ["equil.restart", "log.lammps", "equil_rg.dat", "log", "err"]
  #      }]
  #    }

  # 3. Validate and submit via tmux:
  cd stage-2
  uvx --with dpdispatcher dargs check --allow-ref -f dpdispatcher.entrypoints.submit.submission_args submission.json
  tmux new-session -d -s dpdisp_stage-2 \
    "uvx --from dpdispatcher dpdisp submit --allow-ref submission.json; echo \$? > DPDISP_EXIT_CODE; touch DPDISP_DONE"
  tmux ls

  # 4. Recovery (on session resume or after waiting):
  #    Re-run: uvx --from dpdispatcher dpdisp submit --allow-ref submission.json
  #    (DPDispatcher is idempotent — safe to re-run; downloads outputs on completion)
  ```
- **Success criteria:** No LOST ATOMS error in log; temperature stable at T=1.0 ± 0.05; R_g trace shows no monotonic drift over last 50% of equilibration
- **Estimated walltime:** 2–5 min on GPU

### Stage 3: Production and R_g Measurement
- **Dependencies:** stage-2
- **Backend:** hpc-xjtlu (XJTLU_XEC via DPDispatcher SSHContext + Slurm)
- **Dispatch mode:** async via tmux (2–5 min on GPU)
- **Inputs:** `stage-2/equil.restart`
- **Outputs:** `stage-3/rg_timeseries.dat`, `stage-3/log.lammps`
- **Commands:**
  ```bash
  cd bead-spring-rg-hpc

  # 1. Write stage-3/in.production (LAMMPS input script):
  #    - read_restart equil.restart
  #    - pair_style lj/cut 1.12246204830937; pair_coeff 1 1 1.0 1.0 1.12246204830937; pair_modify shift yes
  #    - bond_style fene; bond_coeff 1 30.0 1.5 1.0 1.0; special_bonds fene
  #    - reset_timestep 0; timestep 0.005
  #    - fix 1 all langevin 1.0 1.0 1.0 67890; fix 2 all nve
  #    - compute gyr all gyration
  #    - fix rg_ave all ave/time 20000 1 20000 c_gyr file rg_timeseries.dat
  #    - thermo 10000; thermo_style custom step temp pe ke etotal c_gyr
  #    - run 2000000

  # 2. Copy equil.restart from stage-2:
  cp stage-2/equil.restart stage-3/equil.restart

  # 3. Write stage-3/submission.json for DPDispatcher:
  #    {
  #      "work_base": ".",
  #      "machine": {"$ref": "../../dpdisp-submit/XJTLU_XEC.json"},
  #      "resources": {
  #        "queue_name": "gpu4090", "number_node": 1, "cpu_per_node": 1, "gpu_per_node": 1,
  #        "custom_flags": ["--gres=gpu:1", "--qos=4gpus", "--mem-per-gpu=10G"], "group_size": 1
  #      },
  #      "task_list": [{
  #        "command": "/gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -sf gpu -in in.production > log 2> err",
  #        "task_work_path": ".",
  #        "forward_files": ["in.production", "equil.restart"],
  #        "backward_files": ["rg_timeseries.dat", "log.lammps", "log", "err"]
  #      }]
  #    }

  # 4. Validate and submit via tmux:
  cd stage-3
  uvx --with dpdispatcher dargs check --allow-ref -f dpdispatcher.entrypoints.submit.submission_args submission.json
  tmux new-session -d -s dpdisp_stage-3 \
    "uvx --from dpdispatcher dpdisp submit --allow-ref submission.json; echo \$? > DPDISP_EXIT_CODE; touch DPDISP_DONE"
  tmux ls

  # 5. Recovery (on session resume or after waiting):
  #    Re-run: uvx --from dpdispatcher dpdisp submit --allow-ref submission.json
  ```
- **Success criteria:** ≥ 50 approximately uncorrelated R_g samples; standard error of mean R_g < 5% of mean; mean R_g within 10% of reference 4.847σ
- **Estimated walltime:** 2–5 min on GPU

## HPC Backend Reference

| Parameter | Value |
|-----------|-------|
| SSH alias | XJTLU_XEC |
| Hostname | 10.7.91.101 |
| Username | zhenghaowu |
| Remote root | /gpfs/home/che/zhenghaowu/bead-spring-rg |
| Scheduler | Slurm |
| Partition | gpu4090 |
| Resources | ntasks=1, gres=gpu:1, qos=4gpus, mem-per-gpu=10G |
| LAMMPS binary | /gpfs/home/che/zhenghaowu/lammps-install/bin/lmp -sf gpu |
| Machine config | dpdisp-submit/XJTLU_XEC.json |

## Reference Result

Local run (bead-spring-rg-2026-04-01): R_g = 4.847 ± 0.092σ
Expected HPC result: within 10% of reference (same physics, GPU offloads pair computation only).
