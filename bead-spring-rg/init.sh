#!/bin/bash
set -e

# Direct conda env paths (conda activate unreliable in non-interactive shells)
CONDA_ENV="/Users/zhenghaowu/miniconda3/envs/omnischolar"
PYTHON="$CONDA_ENV/bin/python3"
LMP="$CONDA_ENV/bin/lmp"

# Check Python
$PYTHON --version || { echo "FAIL: python3 not found at $PYTHON"; exit 1; }

# Check LAMMPS
$LMP -h > /dev/null 2>&1 || { echo "FAIL: LAMMPS not found at $LMP"; exit 1; }

# Check AutoPoly
$PYTHON -c "from AutoPoly import BeadSpringPolymer, System" || { echo "FAIL: AutoPoly not importable"; exit 1; }

# Check Python analysis libraries
$PYTHON -c "import numpy; import matplotlib; import scipy" || { echo "FAIL: required Python libraries (numpy, matplotlib, scipy) not available"; exit 1; }

# Check compute backend prerequisites
command -v uvx >/dev/null 2>&1 || { echo "FAIL: uvx not found"; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "FAIL: tmux not found"; exit 1; }
uvx --from dpdispatcher dpdisp --help > /dev/null 2>&1 || { echo "FAIL: dpdispatcher not accessible via uvx"; exit 1; }

echo "Environment ready."
