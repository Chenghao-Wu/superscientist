#!/bin/bash
set -e

# Direct conda env paths (conda activate unreliable in non-interactive shells)
CONDA_ENV="/Users/zhenghaowu/miniconda3/envs/omnischolar"
PYTHON="$CONDA_ENV/bin/python3"
LMP="$CONDA_ENV/bin/lmp"
AUTOPOLY="$CONDA_ENV/bin/autopoly"

# Check Python
$PYTHON --version || { echo "FAIL: python3 not found at $PYTHON"; exit 1; }

# Check LAMMPS
$LMP -h > /dev/null 2>&1 || { echo "FAIL: LAMMPS not found at $LMP"; exit 1; }

# Check AutoPoly
$AUTOPOLY info > /dev/null 2>&1 || { echo "FAIL: AutoPoly not found at $AUTOPOLY"; exit 1; }

# Check Python libraries
$PYTHON -c "import numpy; import matplotlib" || { echo "FAIL: required Python libraries (numpy, matplotlib) not available"; exit 1; }

# Compute backend prerequisites
command -v uvx >/dev/null 2>&1 || { echo "FAIL: uvx not found"; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "FAIL: tmux not found"; exit 1; }
uvx --from dpdispatcher dpdisp --help > /dev/null 2>&1 || { echo "FAIL: dpdispatcher not accessible via uvx"; exit 1; }

echo "Environment ready."
