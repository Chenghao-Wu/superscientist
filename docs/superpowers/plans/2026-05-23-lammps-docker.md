# Reproducible LAMMPS Docker Environment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a reproducible LAMMPS Docker image to GHCR + host-side wrapper scripts in superscientist so collaborators can pull one image and reproduce LAMMPS demonstrations.

**Architecture:** Two repos. `examples-superscientist` (new) holds the Dockerfile, conda lockfiles, smoke test, and GitHub Actions CI that builds + publishes a multi-arch image to `ghcr.io/Chenghao-Wu/examples-superscientist`. `superscientist` (existing) gains `bin/lmp`, `bin/lmp-python`, `bin/lmp-shell` wrapper scripts that invoke the image via `docker run`, transparent to the plugin's `compute-backend` skill.

**Tech Stack:** Docker (`buildx` for multi-arch), `mambaorg/micromamba` base image, `conda-lock` for dependency pinning, GitHub Actions, GHCR, POSIX shell.

**Spec:** `docs/superpowers/specs/2026-05-23-lammps-docker-design.md`

---

## Prerequisites

Before starting, the engineer needs:

- **macOS or Linux** (the plan was written on darwin; commands are POSIX where possible).
- **Docker Desktop or Docker Engine** with `buildx` (default in modern Docker).
- **`gh` CLI** authenticated to GitHub (`gh auth status` should show authenticated).
- **`uvx`** (from `astral-uv`) for running `conda-lock` without installing it globally.
- **`git`** with commit-signing configured if the repos require it.

**GitHub target:** the new repo is hosted at `https://github.com/Chenghao-Wu/examples-superscientist` (already created on GitHub by the user as of 2026-05-23). The commands below reference `Chenghao-Wu` directly; if a future fork lands under a different owner, search-and-replace.

For convenience, you can set:

```bash
export OWNER="Chenghao-Wu"
```

so commands that read `$OWNER` Just Work, but the value baked into the Dockerfile, CI workflow, README, and wrapper scripts is `Chenghao-Wu`.

---

## Phase 1: `examples-superscientist` repo (new)

### Task 1: Initialize the new repo locally and on GitHub

**Files:**
- Create: `~/Documents/examples-superscientist/` (new directory, sibling of `superscientist/`)
- Create: `~/Documents/examples-superscientist/.gitignore`

- [ ] **Step 1: Create the local directory and initialize git**

```bash
mkdir -p ~/Documents/examples-superscientist
cd ~/Documents/examples-superscientist
git init -b main
```

- [ ] **Step 2: Write `.gitignore`**

Create `.gitignore`:

```
# build artifacts
*.log
log.lammps
.DS_Store

# editor scratch
.vscode/
.idea/
```

- [ ] **Step 3: Make an initial empty commit so the repo has a HEAD**

```bash
git commit --allow-empty -m "chore: initialize examples-superscientist"
```

- [ ] **Step 4: Wire up the existing GitHub remote**

The repo already exists on GitHub. Just add the remote and push:

```bash
git remote add origin https://github.com/Chenghao-Wu/examples-superscientist.git
git push -u origin main
```

If the remote repo on GitHub is non-empty (e.g., has a default README), fetch and rebase first:

```bash
git fetch origin
git rebase origin/main || git pull --rebase --allow-unrelated-histories origin main
git push -u origin main
```

Expected: the initial commit is pushed; `git status` shows `Your branch is up to date with 'origin/main'`.

- [ ] **Step 5: Verify the remote**

```bash
gh repo view Chenghao-Wu/examples-superscientist
git remote -v
```

Expected: remote `origin` points to `https://github.com/Chenghao-Wu/examples-superscientist.git`.

---

### Task 2: Write `environment.yml`

**Files:**
- Create: `~/Documents/examples-superscientist/environment.yml`

- [ ] **Step 1: Define the test — `conda-lock` should accept this file**

(We have no formal unit test for a YAML spec. The "test" is that `conda-lock` parses and solves it. We'll run that in Task 3.)

- [ ] **Step 2: Write the file**

```yaml
# environment.yml — human-edited package spec.
# Lockfiles (conda-*.lock) are the source of truth installed by the Dockerfile.
# Regenerate lockfiles with:
#   uvx conda-lock --file environment.yml --platform linux-64 --platform linux-aarch64 --kind explicit
name: base
channels:
  - conda-forge
  - nodefaults
dependencies:
  - python=3.12.*
  - lammps>=2024.08.29
  - dpdispatcher>=0.6.7
  - ase>=3.23
  - lammpsio>=0.6
  - freud>=3.0
  - numpy
  - matplotlib-base
```

Note: `matplotlib-base` (instead of `matplotlib`) skips the GUI toolkits we don't need in a headless image. Saves ~150 MB.

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/examples-superscientist
git add environment.yml
git commit -m "feat: add conda environment spec for LAMMPS + analysis libs"
```

---

### Task 3: Generate conda lockfiles

**Files:**
- Create: `~/Documents/examples-superscientist/conda-linux-64.lock`
- Create: `~/Documents/examples-superscientist/conda-linux-aarch64.lock`

- [ ] **Step 1: Write the test — lockfile generation must be reproducible**

The "test" for reproducibility is running `conda-lock` twice and verifying the outputs are byte-identical.

- [ ] **Step 2: Generate the lockfiles**

```bash
cd ~/Documents/examples-superscientist
uvx --from conda-lock conda-lock \
  --file environment.yml \
  --platform linux-64 \
  --platform linux-aarch64 \
  --kind explicit \
  --filename-template 'conda-{platform}.lock'
```

Expected output: `conda-linux-64.lock` and `conda-linux-aarch64.lock` created. Each is a one-package-per-line URL list starting with `# This file may be used to create an environment using:` and containing `@EXPLICIT`.

- [ ] **Step 3: Verify reproducibility**

```bash
cp conda-linux-64.lock /tmp/check-amd64.lock
cp conda-linux-aarch64.lock /tmp/check-arm64.lock
uvx --from conda-lock conda-lock \
  --file environment.yml \
  --platform linux-64 \
  --platform linux-aarch64 \
  --kind explicit \
  --filename-template 'conda-{platform}.lock'
diff /tmp/check-amd64.lock conda-linux-64.lock
diff /tmp/check-arm64.lock conda-linux-aarch64.lock
```

Expected: `diff` produces no output (files identical).

- [ ] **Step 4: Confirm lockfiles include `lammps`**

```bash
grep -E '/lammps-' conda-linux-64.lock
grep -E '/lammps-' conda-linux-aarch64.lock
```

Expected: both grep commands find a `lammps-...` URL line.

- [ ] **Step 5: Commit**

```bash
git add conda-linux-64.lock conda-linux-aarch64.lock
git commit -m "feat: generate conda lockfiles for linux-64 and linux-aarch64"
```

---

### Task 4: Write the smoke test

**Files:**
- Create: `~/Documents/examples-superscientist/smoke-test.lmp`

- [ ] **Step 1: Write the test — `lmp -in smoke-test.lmp` must exit 0 and log "Total wall time"**

We'll run this in Task 6 once the image is built. For now, just write the input.

- [ ] **Step 2: Write the file**

```
# 50-atom Lennard-Jones melt, 100 steps. Smoke test for the LAMMPS Docker image.
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
neigh_modify delay 0 every 20 check no
fix         1 all nve
run         100
```

- [ ] **Step 3: Commit**

```bash
git add smoke-test.lmp
git commit -m "feat: add Lennard-Jones smoke test for image CI"
```

---

### Task 5: Write the Dockerfile

**Files:**
- Create: `~/Documents/examples-superscientist/Dockerfile`

- [ ] **Step 1: Write the test — `docker build` for amd64 must succeed**

We'll verify in Task 6.

- [ ] **Step 2: Write the Dockerfile**

```dockerfile
# syntax=docker/dockerfile:1.7
# Reproducible LAMMPS environment for superscientist demos.
# Lockfiles are the source of truth — regenerate via the README instructions
# if you bump environment.yml.

FROM mambaorg/micromamba:2.0-ubuntu24.04

ARG TARGETARCH
COPY conda-linux-64.lock /tmp/lock-amd64
COPY conda-linux-aarch64.lock /tmp/lock-arm64

USER root
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      micromamba install -y -n base --file /tmp/lock-amd64 ; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
      micromamba install -y -n base --file /tmp/lock-arm64 ; \
    else \
      echo "Unsupported TARGETARCH: $TARGETARCH" >&2 ; exit 1 ; \
    fi && \
    micromamba clean --all --yes && \
    rm /tmp/lock-amd64 /tmp/lock-arm64

USER mambauser
WORKDIR /work

# Inherit /usr/local/bin/_entrypoint.sh from the base image — it activates the
# conda env before exec'ing the CMD. Default CMD is bash so `docker run -it`
# without args drops the user into a shell with the env active.
CMD ["bash"]
```

- [ ] **Step 3: Commit (build verification happens in next task)**

```bash
git add Dockerfile
git commit -m "feat: add multi-arch Dockerfile installing from conda lockfiles"
```

---

### Task 6: Build the image locally and verify the smoke test

**Files:** (no files modified — pure verification task)

- [ ] **Step 1: Enable buildx multi-arch (one-time setup)**

```bash
docker buildx create --use --name superscientist-builder 2>/dev/null || docker buildx use superscientist-builder
docker run --rm --privileged tonistiigi/binfmt --install all
```

Expected: `binfmt` reports supported platforms now include `arm64`.

- [ ] **Step 2: Build the amd64 image locally**

```bash
cd ~/Documents/examples-superscientist
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t examples-superscientist:local-amd64 \
  .
```

Expected: build succeeds in ~5-10 min (conda solve + downloads). Final image loaded into local Docker.

- [ ] **Step 3: Check image size**

```bash
docker images examples-superscientist:local-amd64
```

Expected: size under 2 GB. If significantly larger, investigate before continuing.

- [ ] **Step 4: Run the smoke test**

```bash
docker run --rm \
  -v "$PWD:/work" -w /work \
  --user "$(id -u):$(id -g)" \
  examples-superscientist:local-amd64 \
  lmp -in smoke-test.lmp
```

Expected: LAMMPS runs, prints log to stdout, exits 0. A `log.lammps` file appears in the current directory.

- [ ] **Step 5: Verify the log contains the success marker**

```bash
grep "Total wall time" log.lammps
```

Expected: a line like `Total wall time: 0:00:00`. Non-zero output = success.

- [ ] **Step 6: Verify Python env is usable**

```bash
docker run --rm examples-superscientist:local-amd64 \
  python -c "import lammps, ase, lammpsio, freud, numpy, matplotlib; print('ok')"
```

Expected: prints `ok` and exits 0.

- [ ] **Step 7: Build the arm64 image and verify (slower, uses QEMU)**

```bash
docker buildx build \
  --platform linux/arm64 \
  --load \
  -t examples-superscientist:local-arm64 \
  .

docker run --rm --platform linux/arm64 \
  -v "$PWD:/work" -w /work \
  --user "$(id -u):$(id -g)" \
  examples-superscientist:local-arm64 \
  lmp -in smoke-test.lmp

grep "Total wall time" log.lammps
```

Expected: build and smoke test succeed under QEMU. May take 15-30 min depending on host.

- [ ] **Step 8: Clean up local images (optional, frees disk)**

```bash
docker image rm examples-superscientist:local-amd64 examples-superscientist:local-arm64
rm -f log.lammps
```

- [ ] **Step 9: No commit — this task is verification only**

---

### Task 7: Write the GitHub Actions workflow

**Files:**
- Create: `~/Documents/examples-superscientist/.github/workflows/docker-publish.yml`

- [ ] **Step 1: Write the test — pushing to a branch should produce a green CI run that does NOT push (PR/branch builds are smoke-test only). Pushing to `main` should push `:latest` + `:sha-…`. Tagging `vX.Y.Z` should push that tag.**

We verify by pushing in Task 8.

- [ ] **Step 2: Create the directory**

```bash
mkdir -p ~/Documents/examples-superscientist/.github/workflows
```

- [ ] **Step 3: Write the workflow**

```yaml
name: Build and publish Docker image

on:
  push:
    branches: [main]
    tags: ['v*.*.*']
  pull_request:
    branches: [main]

permissions:
  contents: read
  packages: write

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up uv (for conda-lock drift check)
        uses: astral-sh/setup-uv@v3
        with:
          version: latest

      - name: Verify lockfiles are in sync with environment.yml
        run: |
          cp conda-linux-64.lock /tmp/before-amd64.lock
          cp conda-linux-aarch64.lock /tmp/before-arm64.lock
          uvx --from conda-lock conda-lock \
            --file environment.yml \
            --platform linux-64 \
            --platform linux-aarch64 \
            --kind explicit \
            --filename-template 'conda-{platform}.lock'
          if ! diff -q /tmp/before-amd64.lock conda-linux-64.lock || \
             ! diff -q /tmp/before-arm64.lock conda-linux-aarch64.lock; then
            echo "::error::Lockfiles are out of sync with environment.yml."
            echo "Regenerate locally with:"
            echo "  uvx --from conda-lock conda-lock --file environment.yml --platform linux-64 --platform linux-aarch64 --kind explicit --filename-template 'conda-{platform}.lock'"
            exit 1
          fi

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Derive image tags
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/examples-superscientist
          tags: |
            type=ref,event=branch
            type=raw,value=latest,enable={{is_default_branch}}
            type=sha,format=short,prefix=sha-
            type=semver,pattern={{version}}

      - name: Build (PR — no push) or build+push (main / tag)
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Smoke test (amd64)
        run: |
          # Use the first tag from metadata as the test target. For PR builds the
          # image is in the local buildx cache; we rebuild --load for amd64 only.
          TAG=$(echo "${{ steps.meta.outputs.tags }}" | head -n1)
          docker buildx build --platform linux/amd64 --load -t smoke-amd64 .
          docker run --rm -v "$PWD:/work" -w /work smoke-amd64 lmp -in smoke-test.lmp
          grep "Total wall time" log.lammps
          rm -f log.lammps

      - name: Smoke test (arm64 via QEMU)
        run: |
          docker buildx build --platform linux/arm64 --load -t smoke-arm64 .
          docker run --rm --platform linux/arm64 -v "$PWD:/work" -w /work smoke-arm64 lmp -in smoke-test.lmp
          grep "Total wall time" log.lammps
          rm -f log.lammps
```

- [ ] **Step 4: Commit (CI will run on push in Task 8)**

```bash
git add .github/workflows/docker-publish.yml
git commit -m "ci: build, smoke-test, and publish multi-arch image to GHCR"
```

---

### Task 8: Push and verify CI publishes the image

**Files:** (no files modified — verification task)

- [ ] **Step 1: Push to main**

```bash
cd ~/Documents/examples-superscientist
git push origin main
```

- [ ] **Step 2: Watch the CI run**

```bash
gh run watch
```

Expected: the workflow runs ~15-30 min (mostly arm64 QEMU build time). It should end with all steps green and publish `:latest` and `:sha-<short>` tags.

If the lockfile-drift step fails, the lockfiles committed locally don't match what `conda-lock` regenerates in CI's clean environment. Regenerate locally with the command in the failure message, commit, push, retry.

- [ ] **Step 3: Verify the image is published**

```bash
gh api "/users/$OWNER/packages/container/examples-superscientist/versions" --jq '.[].metadata.container.tags'
```

Expected: a list including `latest` and a `sha-…` tag.

- [ ] **Step 4: Pull and run the published image**

```bash
docker pull "ghcr.io/$OWNER/examples-superscientist:latest"
mkdir -p /tmp/smoke && cp smoke-test.lmp /tmp/smoke/
docker run --rm -v /tmp/smoke:/work -w /work \
  --user "$(id -u):$(id -g)" \
  "ghcr.io/$OWNER/examples-superscientist:latest" \
  lmp -in smoke-test.lmp
grep "Total wall time" /tmp/smoke/log.lammps
rm -rf /tmp/smoke
```

Expected: image pulls (single-digit GB compressed), runs the smoke test, exits 0.

- [ ] **Step 5: No commit — verification only**

---

### Task 9: Write README and LICENSE; tag `v0.1.0`

**Files:**
- Create: `~/Documents/examples-superscientist/README.md`
- Create: `~/Documents/examples-superscientist/LICENSE`

- [ ] **Step 1: Write `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 Zhenghao Wu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Replace `Zhenghao Wu` with your name.

- [ ] **Step 2: Write `README.md`**

Use this content, substituting `Chenghao-Wu` with the actual GitHub owner:

````markdown
# examples-superscientist

Reproducible LAMMPS Docker environment for [superscientist](https://github.com/Chenghao-Wu/superscientist) demonstrations.

## Quickstart (consumer)

```bash
docker pull ghcr.io/Chenghao-Wu/examples-superscientist:latest
mkdir lj-demo && cd lj-demo
curl -O https://raw.githubusercontent.com/Chenghao-Wu/examples-superscientist/main/smoke-test.lmp
docker run --rm -v "$PWD:/work" -w /work \
  --user "$(id -u):$(id -g)" \
  ghcr.io/Chenghao-Wu/examples-superscientist:latest \
  lmp -in smoke-test.lmp
```

You should see `Total wall time: 0:00:00` near the end of `log.lammps`.

For interactive use:

```bash
docker run --rm -it -v "$PWD:/work" -w /work \
  --user "$(id -u):$(id -g)" \
  ghcr.io/Chenghao-Wu/examples-superscientist:latest \
  bash
```

## What's inside

| Tool | Purpose |
|---|---|
| `lmp` | LAMMPS molecular dynamics engine (CPU + MPI, conda-forge build) |
| `python` | Python 3.12 with `dpdispatcher`, `ase`, `lammpsio`, `freud`, `numpy`, `matplotlib` |

Base image: `mambaorg/micromamba:2.0-ubuntu24.04`. Architectures: `linux/amd64`, `linux/arm64`.

## Use with superscientist

The [superscientist](https://github.com/Chenghao-Wu/superscientist) repo ships host wrappers (`bin/lmp`, `bin/lmp-python`, `bin/lmp-shell`) that hide the `docker run` invocation. Add `superscientist/bin/` to your `PATH` and superscientist's `compute-backend` skill will call `lmp` transparently.

To pin a specific image version, set:

```bash
export EXAMPLES_SUPERSCIENTIST_IMAGE="ghcr.io/Chenghao-Wu/examples-superscientist:v0.1.0"
```

## Reproducing a demo bit-for-bit

Always cite a versioned tag (e.g., `v0.1.0`) in shared demos, not `:latest`. The `:latest` tag floats with `main`.

## Rebuilding the image yourself

```bash
git clone https://github.com/Chenghao-Wu/examples-superscientist
cd examples-superscientist
docker buildx build --platform linux/amd64 --load -t examples-superscientist:dev .
```

## Updating dependencies

1. Edit `environment.yml` (e.g., bump `lammps` version floor).
2. Regenerate lockfiles:
   ```bash
   uvx --from conda-lock conda-lock \
     --file environment.yml \
     --platform linux-64 --platform linux-aarch64 \
     --kind explicit \
     --filename-template 'conda-{platform}.lock'
   ```
3. Commit `environment.yml` + both `conda-*.lock` files together. CI's drift check enforces consistency.

## Image tags

| Tag | Source | Use |
|---|---|---|
| `latest` | every push to `main` | Casual / development use |
| `vX.Y.Z` | git tags `vX.Y.Z` | **Cite in shared demos** |
| `sha-<short>` | every CI build on `main` | Bisecting / debugging |

## License

MIT — see [LICENSE](LICENSE).
````

- [ ] **Step 3: Commit**

```bash
git add README.md LICENSE
git commit -m "docs: add README and LICENSE"
git push origin main
```

- [ ] **Step 4: Wait for CI to go green on this push, then tag `v0.1.0`**

```bash
gh run watch
git tag -a v0.1.0 -m "Initial release: LAMMPS + analysis libs on linux/amd64 + linux/arm64"
git push origin v0.1.0
gh run watch
```

Expected: tag-triggered CI build pushes `ghcr.io/$OWNER/examples-superscientist:v0.1.0`.

- [ ] **Step 5: Verify the v0.1.0 tag exists on GHCR**

```bash
docker pull "ghcr.io/$OWNER/examples-superscientist:v0.1.0"
docker images "ghcr.io/$OWNER/examples-superscientist"
```

Expected: pull succeeds; `v0.1.0` appears in the local image list.

---

## Phase 2: `superscientist` repo — host wrappers

### Task 10: Write `bin/lmp` wrapper

**Files:**
- Create: `/Users/bruce/Documents/superscientist/bin/lmp`

- [ ] **Step 1: Write the test — `bin/lmp -in smoke-test.lmp` produces "Total wall time" via the published image**

```bash
cd /Users/bruce/Documents/superscientist
mkdir -p bin
# Test will run in Step 4 after the wrapper exists.
```

- [ ] **Step 2: Write the wrapper**

Create `bin/lmp` with this content (substitute `Chenghao-Wu` with the real owner; the resulting file must have a real owner, not a placeholder):

```sh
#!/bin/sh
# bin/lmp — host wrapper that runs LAMMPS inside the examples-superscientist
# Docker image. The plugin's compute-backend skill invokes this as if it were
# a host-installed `lmp` binary.

set -e

IMAGE="${EXAMPLES_SUPERSCIENTIST_IMAGE:-ghcr.io/Chenghao-Wu/examples-superscientist:latest}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found. Install Docker Desktop or Docker Engine, then retry." >&2
  exit 127
fi

exec docker run --rm \
  -v "$PWD:/work" -w /work \
  --user "$(id -u):$(id -g)" \
  "$IMAGE" lmp "$@"
```

Replace `Chenghao-Wu` literally before saving.

- [ ] **Step 3: Make executable**

```bash
chmod +x /Users/bruce/Documents/superscientist/bin/lmp
```

- [ ] **Step 4: Run the test**

```bash
cd /tmp
mkdir -p lmp-wrapper-test && cd lmp-wrapper-test
curl -O "https://raw.githubusercontent.com/$OWNER/examples-superscientist/main/smoke-test.lmp"
/Users/bruce/Documents/superscientist/bin/lmp -in smoke-test.lmp
grep "Total wall time" log.lammps
cd / && rm -rf /tmp/lmp-wrapper-test
```

Expected: LAMMPS runs through the container, exits 0, log contains the wall-time line.

- [ ] **Step 5: Test the docker-missing error path**

```bash
PATH=/usr/bin:/bin /Users/bruce/Documents/superscientist/bin/lmp -in nothing.lmp 2>&1 | head -1
```

Expected: the line `Error: docker not found. Install Docker Desktop or Docker Engine, then retry.` Exit code 127.

- [ ] **Step 6: Test the env-var override**

```bash
EXAMPLES_SUPERSCIENTIST_IMAGE="ghcr.io/$OWNER/examples-superscientist:v0.1.0" \
  /Users/bruce/Documents/superscientist/bin/lmp -help | head -5
```

Expected: LAMMPS help text from the v0.1.0 image.

- [ ] **Step 7: Commit**

```bash
cd /Users/bruce/Documents/superscientist
git add bin/lmp
git commit -m "feat: add bin/lmp wrapper invoking LAMMPS via Docker image"
```

---

### Task 11: Write `bin/lmp-python` wrapper

**Files:**
- Create: `/Users/bruce/Documents/superscientist/bin/lmp-python`

- [ ] **Step 1: Write the test — `bin/lmp-python -c "import lammps; print('ok')"` exits 0 with output `ok`**

We run this in Step 4.

- [ ] **Step 2: Write the wrapper**

Create `bin/lmp-python` (substitute `Chenghao-Wu`):

```sh
#!/bin/sh
# bin/lmp-python — host wrapper running the Python interpreter from the
# examples-superscientist image. Use for analysis scripts that need the same
# packages as the LAMMPS env (ase, lammpsio, freud, numpy, matplotlib).

set -e

IMAGE="${EXAMPLES_SUPERSCIENTIST_IMAGE:-ghcr.io/Chenghao-Wu/examples-superscientist:latest}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found. Install Docker Desktop or Docker Engine, then retry." >&2
  exit 127
fi

exec docker run --rm \
  -v "$PWD:/work" -w /work \
  --user "$(id -u):$(id -g)" \
  "$IMAGE" python "$@"
```

- [ ] **Step 3: Make executable**

```bash
chmod +x /Users/bruce/Documents/superscientist/bin/lmp-python
```

- [ ] **Step 4: Run the test**

```bash
/Users/bruce/Documents/superscientist/bin/lmp-python -c "import lammps, ase, lammpsio, freud, numpy, matplotlib; print('ok')"
```

Expected output: `ok`. Exit code 0.

- [ ] **Step 5: Commit**

```bash
git add bin/lmp-python
git commit -m "feat: add bin/lmp-python wrapper for analysis scripts"
```

---

### Task 12: Write `bin/lmp-shell` wrapper

**Files:**
- Create: `/Users/bruce/Documents/superscientist/bin/lmp-shell`

- [ ] **Step 1: Write the test — `bin/lmp-shell -c 'lmp -help | head -1'` exits 0 with LAMMPS header**

We run this in Step 4.

- [ ] **Step 2: Write the wrapper**

Create `bin/lmp-shell` (substitute `Chenghao-Wu`):

```sh
#!/bin/sh
# bin/lmp-shell — host wrapper dropping the user into an interactive bash
# session inside the examples-superscientist image. With no args, an
# interactive shell starts. With args, they are passed to bash (e.g., -c).

set -e

IMAGE="${EXAMPLES_SUPERSCIENTIST_IMAGE:-ghcr.io/Chenghao-Wu/examples-superscientist:latest}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found. Install Docker Desktop or Docker Engine, then retry." >&2
  exit 127
fi

exec docker run --rm -it \
  -v "$PWD:/work" -w /work \
  --user "$(id -u):$(id -g)" \
  "$IMAGE" bash "$@"
```

- [ ] **Step 3: Make executable**

```bash
chmod +x /Users/bruce/Documents/superscientist/bin/lmp-shell
```

- [ ] **Step 4: Run the test (non-interactive form)**

```bash
/Users/bruce/Documents/superscientist/bin/lmp-shell -c "lmp -help | head -1"
```

Expected: a line that starts with `Large-scale Atomic/Molecular Massively Parallel Simulator`. Exit code 0.

Note: testing the interactive form (no args) requires a TTY. If the script is being executed without a TTY (e.g., from a non-interactive subagent context), interactive testing is skipped — the `-c` form covers the same docker plumbing.

- [ ] **Step 5: Commit**

```bash
git add bin/lmp-shell
git commit -m "feat: add bin/lmp-shell wrapper for interactive container access"
```

---

### Task 13: Add README section to `superscientist`

**Files:**
- Modify: `/Users/bruce/Documents/superscientist/README.md`

- [ ] **Step 1: Read the current README to find a good insertion point**

```bash
cat /Users/bruce/Documents/superscientist/README.md
```

Identify the section right before `## Project Structure` (where infrastructure-y content fits).

- [ ] **Step 2: Insert a new section before `## Project Structure`**

Edit `README.md` to add this section just before the existing `## Project Structure` heading. Substitute `Chenghao-Wu` with the actual GitHub owner:

````markdown
## Reproducible LAMMPS environment

LAMMPS-based demos run inside a pinned Docker image published from the companion repo [examples-superscientist](https://github.com/Chenghao-Wu/examples-superscientist). The plugin's `compute-backend` skill invokes `lmp` transparently — no special configuration needed beyond putting `bin/` on your `PATH`:

```bash
export PATH="/path/to/superscientist/bin:$PATH"
docker pull ghcr.io/Chenghao-Wu/examples-superscientist:latest   # first time only
```

Wrappers:

| Wrapper | What it runs |
|---|---|
| `lmp` | LAMMPS engine inside the container |
| `lmp-python` | Python interpreter inside the container (for analysis scripts) |
| `lmp-shell` | Interactive bash inside the container (for debugging) |

Pin a specific image release for shared / published demos:

```bash
export EXAMPLES_SUPERSCIENTIST_IMAGE="ghcr.io/Chenghao-Wu/examples-superscientist:v0.1.0"
```

See [examples-superscientist's README](https://github.com/Chenghao-Wu/examples-superscientist) for image internals, rebuild instructions, and how to update dependencies.
````

- [ ] **Step 3: Verify the README still renders cleanly**

```bash
grep -c "^## " /Users/bruce/Documents/superscientist/README.md
```

Expected: the heading count has gone up by 1 from before the edit.

- [ ] **Step 4: Commit**

```bash
cd /Users/bruce/Documents/superscientist
git add README.md
git commit -m "docs: document Docker-based LAMMPS environment and bin/ wrappers"
```

- [ ] **Step 5: Push superscientist changes**

```bash
git push origin main
```

---

### Task 14: End-to-end test with a real superscientist workflow

**Files:** (no files modified — verification task)

- [ ] **Step 1: Start a fresh shell with only PATH adjusted (preserves Docker auth state)**

```bash
env PATH="/Users/bruce/Documents/superscientist/bin:$PATH" /bin/sh
```

Inside the new shell:

```sh
which lmp
which lmp-python
which lmp-shell
```

Expected: all three resolve to `/Users/bruce/Documents/superscientist/bin/...`.

- [ ] **Step 2: Run the smoke test through the wrapper (no other tooling)**

```sh
mkdir -p /tmp/e2e && cd /tmp/e2e
curl -O "https://raw.githubusercontent.com/$OWNER/examples-superscientist/main/smoke-test.lmp"
lmp -in smoke-test.lmp
grep "Total wall time" log.lammps
```

Expected: success with wall-time line.

- [ ] **Step 3: Exit the subshell**

```sh
exit
```

- [ ] **Step 4: (Optional) Run a real superscientist workflow that uses LAMMPS**

If you have an existing superscientist workflow checkpoint that uses LAMMPS, resume it with the wrappers on PATH. The `compute-backend` skill's `submission.json` should specify `command: "lmp -in in.lmp"` (or similar) and dispatch via the local Shell backend. Verify the stage completes successfully.

If no existing workflow is available, this step can be deferred until one is run organically.

- [ ] **Step 5: Tag a release of superscientist (optional)**

If you want a coordinated release marker, after CI is green:

```bash
cd /Users/bruce/Documents/superscientist
git tag -a v0.1.0-docker -m "Adds Docker-based LAMMPS wrappers paired with examples-superscientist v0.1.0"
git push origin v0.1.0-docker
```

- [ ] **Step 6: No commit — verification only**

---

## Self-Review checklist (post-implementation)

After all tasks complete, verify against the spec:

- [ ] **Spec coverage:**
  - [ ] `examples-superscientist` repo exists with Dockerfile, environment.yml, both lockfiles, smoke-test.lmp, CI workflow, README, LICENSE (Tasks 1-9)
  - [ ] Image published to `ghcr.io/Chenghao-Wu/examples-superscientist` with `:latest`, `:sha-<short>`, `:v0.1.0` tags (Tasks 8-9)
  - [ ] Image is multi-arch (linux/amd64 + linux/arm64) — confirmed by Task 6 step 7 + Task 8 step 4 on both runners
  - [ ] CI runs lockfile-drift check (Task 7) — fails if `conda-lock` produces a diff
  - [ ] CI runs smoke test on both arches (Task 7)
  - [ ] Wrappers in `superscientist/bin/` for `lmp`, `lmp-python`, `lmp-shell` (Tasks 10-12)
  - [ ] Each wrapper handles missing docker (Task 10 step 5)
  - [ ] Each wrapper honors `EXAMPLES_SUPERSCIENTIST_IMAGE` (Task 10 step 6)
  - [ ] Each wrapper bind-mounts `$PWD` and sets `--user $UID:$GID` (visible in the scripts)
  - [ ] README in superscientist explains usage (Task 13)
  - [ ] End-to-end check on a clean PATH works (Task 14)

- [ ] **Out-of-scope confirmed absent:**
  - [ ] No GPU / CUDA in image
  - [ ] No multi-node MPI infra
  - [ ] No bundled demos
  - [ ] No Claude Code or superscientist plugin in image
  - [ ] No sibling engine images (CP2K/GROMACS/MACE/PySCF)
  - [ ] No image signing / SBOM
