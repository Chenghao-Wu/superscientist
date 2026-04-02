#!/bin/bash
set -e

# Direct conda env path (conda activate unreliable in non-interactive shells)
CONDA_ENV="/Users/zhenghaowu/miniconda3/envs/omnischolar"
PYTHON="$CONDA_ENV/bin/python3"

# Check Python
$PYTHON --version || { echo "FAIL: python3 not found at $PYTHON"; exit 1; }

# Check AutoPoly (used in Stage 1, local)
$PYTHON -c "import AutoPoly" || { echo "FAIL: AutoPoly not importable in $CONDA_ENV"; exit 1; }

# Note: LAMMPS binary is on HPC (remote). It is marked [UNVERIFIED] in the design doc.
# Pre-flight validation is performed via prepend_script in Stage 2's SLURM job.
# See workflow-state.json stage-2 parameters: lammps_binary, lammps_flags.

# Compute backend prerequisites
command -v uvx >/dev/null 2>&1 || { echo "FAIL: uvx not found"; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "FAIL: tmux not found"; exit 1; }
uvx --from dpdispatcher dpdisp --help > /dev/null 2>&1 || { echo "FAIL: dpdispatcher not accessible via uvx"; exit 1; }

# SSH connectivity check to HPC
ssh -o BatchMode=yes -o ConnectTimeout=5 XJTLU_XEC "echo ok" > /dev/null 2>&1 || { echo "FAIL: SSH to XJTLU_XEC (zhenghaowu@10.7.91.101) not available"; exit 1; }

echo "Environment ready."
