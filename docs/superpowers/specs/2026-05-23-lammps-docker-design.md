# Reproducible LAMMPS Docker Environment for Superscientist

**Status:** Design approved, awaiting implementation plan
**Date:** 2026-05-23
**Author:** zhenghao.wu95@gmail.com

## Goal

Ship a reproducible LAMMPS execution environment as a Docker image, published to GitHub Container Registry (GHCR), so collaborators can pull a single pinned image and reproduce LAMMPS-based superscientist demonstrations bit-for-bit.

The image is the **compute runtime only**. Claude Code and the superscientist plugin remain on the host. The host invokes LAMMPS inside the container via thin wrapper scripts that superscientist's `compute-backend` skill calls transparently — superscientist never knows about Docker.

## Non-goals

- GPU support (CPU-only build)
- Multi-node MPI (single-container shared-memory MPI only)
- Bundled superscientist demos (deferred to follow-up work)
- Claude Code or the superscientist plugin inside the image
- Sibling images for other engines (CP2K, GROMACS, MACE, PySCF) — separate future specs
- Image signing / SBOM generation
- Repo layout designed for multiple engines (this spec is LAMMPS-only)

## Architecture

```
┌────────────────────────────── host machine ──────────────────────────────┐
│  Claude Code  →  superscientist plugin  →  compute-backend skill         │
│                                                       │                   │
│                                                       ▼                   │
│                                    dpdisp submit submission.json          │
│                                       (command: "lmp -in in.lmp")         │
│                                                       │                   │
│                                                       ▼                   │
│                                              ┌──── bin/lmp ────┐          │
│                                              │ docker run --rm │          │
│                                              │ -v $PWD:/work   │          │
│                                              │ -w /work        │          │
│                                              │ --user UID:GID  │          │
│                                              │ $IMAGE lmp "$@" │          │
│                                              └────────┬────────┘          │
└───────────────────────────────────────────────────────┼───────────────────┘
                                                        ▼
┌─────── ghcr.io/<repo-owner>/superscientist-lammps:<tag> ─────────────────┐
│   micromamba env: lammps + dpdispatcher + ase + lammpsio + freud +       │
│                   numpy + matplotlib + python 3.12 + MPI                 │
│   /work  ← bind-mounted host workdir                                     │
└──────────────────────────────────────────────────────────────────────────┘
```

**Key properties:**

- **Throw-away containers per call.** Each LAMMPS invocation spawns a fresh container. Startup overhead ~1–2 s, negligible for real simulations.
- **Bind-mount, not copy.** `$PWD` mounts to `/work`; LAMMPS reads inputs and writes outputs to the host filesystem directly.
- **Correct file ownership.** `--user $(id -u):$(id -g)` ensures container-created files are owned by the host user (avoids root-owned outputs on Linux).
- **Transparent to superscientist.** The `compute-backend` skill issues `lmp -in in.lmp` exactly as it would for a host-installed LAMMPS. The Docker layer is invisible.

## Image contents

Single conda environment (`base`) in `mambaorg/micromamba:2.0-ubuntu24.04`:

| Package | Role |
|---|---|
| `lammps` | Simulation engine (CPU + MPI build from conda-forge) |
| `dpdispatcher` | Job dispatcher — available inside the container for users who want to `docker exec`/shell in and submit jobs from within. The primary architecture (wrapper script) keeps dpdispatcher running on the host; the in-container copy is a convenience, not a requirement. |
| `ase` | Atomic Simulation Environment — structure I/O |
| `lammpsio` | Python reader/writer for LAMMPS data and dump files |
| `freud` | Trajectory analysis (RDF, MSD, order parameters) |
| `numpy` | Baseline scientific Python |
| `matplotlib` | Plotting |
| `python=3.12.*` | Runtime |

Image size target: **≤ 2 GB** uncompressed (≤ 1 GB compressed on GHCR).

**Host-side requirements (not in image):** `docker` (engine or Desktop), and `uvx` for the host's `compute-backend` skill to invoke `uvx --from dpdispatcher dpdisp submit`. `uvx` lives on the host, not in the container.

## Reproducibility model

**Pinning strategy: `conda-lock`.**

- `docker/environment.yml` — human-edited package list with version floors (e.g., `lammps>=2024.08.29`, `python=3.12.*`).
- `docker/conda-linux-64.lock` and `docker/conda-linux-aarch64.lock` — `conda-lock`-generated lockfiles pinning every transitive dependency down to the build hash. **These are the source of truth installed during the build.**
- Regeneration: `conda-lock --file environment.yml --platform linux-64 --platform linux-aarch64`. Lockfiles are committed.
- Base image pinned by tag (`mambaorg/micromamba:2.0-ubuntu24.04`). Digest-pinning is deferred (maximal-rigor approach).

**Lockfile drift check.** CI verifies that re-running `conda-lock` against the committed `environment.yml` produces no diff against the committed lockfiles. If they drift, the build fails with instructions to regenerate.

## Image tagging

Published to `ghcr.io/<repo-owner>/superscientist-lammps`:

| Tag | Source event | Purpose |
|---|---|---|
| `latest` | push to `main` | Convenience pointer for casual use |
| `vX.Y.Z` | push of git tag `vX.Y.Z` | Stable release — **cite this in shared demos** |
| `sha-<short>` | every CI build on `main` | Debugging / bisecting |

Pull-request builds produce no published tags — they build and smoke-test only.

## Architectures

`linux/amd64` and `linux/arm64`, published as a single multi-arch manifest via `docker buildx`. Arm64 layers built under QEMU emulation on the amd64 GitHub-hosted runner (≈ 5× slower than native, still finishes the smoke test in seconds).

## Repo layout (additions to existing superscientist repo)

```
superscientist/
├── docker/
│   ├── Dockerfile
│   ├── environment.yml           # human-edited package list
│   ├── conda-linux-64.lock       # generated, committed
│   ├── conda-linux-aarch64.lock  # generated, committed
│   ├── smoke-test.lmp            # Lennard-Jones melt, 50 atoms, 100 steps
│   └── README.md                 # how to rebuild, regenerate lockfiles
├── bin/
│   ├── lmp                       # host wrapper → `docker run … lmp "$@"`
│   ├── lmp-python                # host wrapper → `docker run … python "$@"`
│   └── lmp-shell                 # host wrapper → `docker run -it … bash`
├── .github/workflows/
│   └── docker-publish.yml        # build + smoke-test + push (multi-arch)
└── README.md                     # add "Reproducible LAMMPS environment" section
```

## Components

### Dockerfile

```dockerfile
FROM mambaorg/micromamba:2.0-ubuntu24.04
ARG TARGETARCH
COPY docker/conda-linux-64.lock /tmp/lock-amd64
COPY docker/conda-linux-aarch64.lock /tmp/lock-arm64
USER root
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      micromamba install -y -n base --file /tmp/lock-amd64 ; \
    else \
      micromamba install -y -n base --file /tmp/lock-arm64 ; \
    fi && \
    micromamba clean --all --yes && \
    rm /tmp/lock-amd64 /tmp/lock-arm64
USER mambauser
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/_entrypoint.sh"]
CMD ["bash"]
```

### Host wrappers (`bin/lmp`, `bin/lmp-python`, `bin/lmp-shell`)

Each is a ~10-line POSIX shell script. Shared behavior:

- Resolve image from `${SUPERSCIENTIST_LAMMPS_IMAGE:-ghcr.io/<repo-owner>/superscientist-lammps:latest}`.
- `docker run --rm -v "$PWD:/work" -w /work --user "$(id -u):$(id -g)" "$IMAGE" <cmd> "$@"`.
- For `lmp-shell`: add `-it` and run `bash` instead of a fixed entrypoint.
- Pre-flight check: if `docker` is not on PATH, print actionable error and exit 127.
- Forward `docker run`'s exit code unchanged so DPDispatcher sees LAMMPS's real exit code.

Users place `bin/` on `PATH` (documented in README).

### Smoke test (`docker/smoke-test.lmp`)

50-atom Lennard-Jones melt, 100 timesteps, NVE. No external data files. Verifies pair-style, neighbor lists, integrator. Completes in <1 s.

```
units       lj
atom_style  atomic
lattice     fcc 0.8442
region      box block 0 4 0 4 0 4
create_box  1 box
create_atoms 1 box
mass        1 1.0
velocity    all create 1.44 87287 loop geom
pair_style  lj/cut 2.5
pair_coeff  1 1 1.0 1.0 2.5
neighbor    0.3 bin
fix         1 all nve
run         100
```

### CI workflow (`.github/workflows/docker-publish.yml`)

Triggers:
- Push to `main` → build + smoke-test + push `:latest` and `:sha-<short>`
- Push of `v*.*.*` tag → also push `:vX.Y.Z`
- Pull request → build + smoke-test only (no push)

Single job, no matrix — `buildx` produces the multi-arch manifest in one invocation:

1. `actions/checkout@v4`
2. `docker/setup-qemu-action@v3` (arm64 emulation)
3. `docker/setup-buildx-action@v3`
4. Lockfile drift check: install `conda-lock`, re-run against `environment.yml`, `git diff --exit-code docker/conda-*.lock`
5. `docker/login-action@v3` against `ghcr.io` (uses `GITHUB_TOKEN`)
6. `docker/metadata-action@v5` for tag derivation
7. `docker/build-push-action@v6`, platforms `linux/amd64,linux/arm64`, push gated on event type, `cache-from`/`cache-to: type=gha,mode=max`
8. Smoke test: `docker run --rm --platform linux/amd64 $IMAGE lmp -in /work/smoke-test.lmp` (with `docker/` bind-mounted). Repeat for `linux/arm64`. Assert exit 0 and grep `log.lammps` for `Total wall time`.

## Error handling and UX

| Failure | Behavior |
|---|---|
| `docker` not on PATH | Wrapper prints actionable install hint, exits 127 |
| Image not yet pulled | `docker run` auto-pulls on first use; README warns first run takes ~1 min |
| LAMMPS nonzero exit | Wrapper forwards exit code; DPDispatcher handles it like any local failure |
| Lockfile drift | CI fails with a clear regeneration command |
| arm64 build fails on QEMU | Treated as build failure; no fallback to amd64-only push |

## Testing strategy

- **CI smoke test** on every build (PR and main).
- **Manual end-to-end test** once before tagging `v0.1.0`: pull the image on a clean machine, run a real superscientist workflow stage via `bin/lmp`, verify outputs against a reference run.
- **No unit tests on wrappers** — they are ~10 lines and exercised by the CI smoke build.

## Open items

- Confirm the GitHub repo owner / namespace so the GHCR path can be written into the wrappers and CI. Currently `<repo-owner>` in this doc.
- First image release tag (suggested: `v0.1.0` after the manual end-to-end test passes).
