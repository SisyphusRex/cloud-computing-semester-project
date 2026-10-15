# Local development

How to run all of Lecture Indexer on your own machine: Postgres, the Ingest and Search APIs, and the React frontend. Supported setups are **Linux (Ubuntu/Debian)** and **Windows through WSL2** (Ubuntu). Nothing here touches the cloud or costs money.

## What runs where

| Piece | Runs in | Address |
|---|---|---|
| Postgres 16 | Docker container (`db`) | `localhost:55432` (container port 5432; 55432 avoids clashing with a system Postgres) |
| Migrations | Docker container (`migrate`), runs once and exits | — |
| Ingest API (Flask) | Docker container (`ingest`) | http://localhost:8081 |
| Search API (Flask) | Docker container (`search`) | http://localhost:8082 |
| Frontend (React + Vite) | Node on your machine | http://localhost:5173 |

The frontend's dev server forwards `/ingest/*` to `:8081` and `/search/*` to `:8082`, so the browser only ever talks to `localhost:5173`. Locally the APIs accept **dev sign-in** (`Authorization: Bearer dev:<email>`) instead of Google; `prof@example.edu` is a professor and any other email is a student.

## Prerequisites

| Tool | Version | Needed for |
|---|---|---|
| git, make, bash, curl, python3 | any recent | everything (`make`, `scripts/smoke-test.sh`) |
| Docker Engine with the Compose plugin | Compose v2.20 or newer | `make dev-up`: Postgres and both APIs |
| Node.js with npm | 22.22 or newer (`frontend/.nvmrc`) | the frontend |
| [uv](https://docs.astral.sh/uv/) | latest; it installs Python 3.12 itself | only `make install`, `lint`, `test`, `test-db` |

You don't need Python packages, Postgres, Terraform, kubectl, or any cloud CLI to run the app. `make k8s-check` (kustomize, kubeconform) and Terraform are optional locally, because CI checks them on every push.

## Install prerequisites: Linux

Ubuntu 22.04/24.04 or Debian 12. Also use this inside WSL2.

```sh
# Basics (usually already present)
sudo apt update
sudo apt install -y git make curl python3
```

**Docker Engine + Compose plugin.** Follow Docker's official guide for your distro, which installs `docker-ce` and `docker-compose-plugin` from Docker's apt repository: <https://docs.docker.com/engine/install/ubuntu/> (Debian: <https://docs.docker.com/engine/install/debian/>). Then check:

```sh
docker --version
docker compose version     # must say v2.20 or newer
```

Then decide how you'll access Docker; see [Docker permissions](#docker-permissions).

**Node.js 22 with nvm.** Distro packages are usually too old.

```sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
# open a new terminal, then from the repo root:
cd frontend && nvm install && nvm use && cd ..   # reads .nvmrc (22)
node --version                                    # v22.22.0 or newer
```

**uv** (only for running the Python tests and lint):

```sh
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Install prerequisites: Windows (WSL2)

The Makefile and scripts need a Linux shell, so on Windows everything runs inside WSL2.

1. In PowerShell as Administrator: `wsl --install -d Ubuntu`. Restart if asked, then open **Ubuntu** from the Start menu and create your Linux user.
2. Install **Docker Desktop for Windows**, then in Docker Desktop → **Settings → Resources → WSL integration**, turn on integration for **Ubuntu**. (Installing Docker Engine inside WSL with the Linux steps also works; don't do both.)
3. Inside Ubuntu, follow [Install prerequisites: Linux](#install-prerequisites-linux), skipping the Docker Engine install if you use Docker Desktop.
4. **Clone the repo inside the WSL filesystem**, e.g. `~/src/cloud-computing-semester-project`, **not** under `/mnt/c/...`. Builds there are very slow, and the frontend's file watching doesn't work.
5. Open http://localhost:5173 in your normal Windows browser; WSL2 forwards `localhost`.

With Docker Desktop's WSL integration, `docker` works without `sudo`, so you can skip the next section.

## Docker permissions

On Linux, Docker's socket belongs to root, so plain `docker` fails with `permission denied … docker.sock`. Pick one option:

- **Join the `docker` group** (convenient):
  ```sh
  sudo usermod -aG docker $USER
  # log out and back in (or run: newgrp docker), then:
  docker info
  ```
- **Use `sudo` for Docker only:** tell the Makefile to prefix its Docker commands, once per terminal:
  ```sh
  export COMPOSE="sudo docker compose"
  ```
  Every `make` target that uses Docker (`dev-up`, `dev-down`, `dev-reset`, `dev-logs`, `test-db`) then asks for your password as needed.

**Never run `sudo make …`.** It would run `uv` and `npm` as root, leaving root-owned `services/.venv` and `frontend/node_modules` that break later commands.

Both options give root-equivalent power over the machine (Docker can mount any file); the difference is only convenience.

## Check your setup

```sh
make doctor
```

It lists each tool as `ok`, `missing`, or `too old` with an install hint, reports `uv` as optional, and checks Docker access (including the `sudo` option above). It exits with an error only if something needed to run the app is missing.

## Run the app

From the repo root:

```sh
make dev-up      # builds the images; starts Postgres, runs migrations, starts both APIs
make smoke       # checks sign-in, roles, course creation, and search against the running APIs

cp frontend/.env.example frontend/.env.local   # first time only; dev sign-in is on by default
make frontend-install                          # first time, and after package.json changes
make frontend-dev                              # leave running; Ctrl-C to stop
```

Open **http://localhost:5173**:
- **`prof@example.edu`** sees the **Manage** page: create courses, register and remove lectures.
- **`student@example.edu`** (or any other email): browse courses and search them.

**Registering a lecture fails in dev mode**, with a YouTube token error. The Ingest API really calls YouTube with your Google token, so it needs real Google sign-in with your own captioned video. That's described in the implementation plan, [Next: real Google/YouTube test](implementation-plan.md#next-real-googleyoutube-test-free-before-deploying).

## Day to day

| Task | Command |
|---|---|
| See API logs | `make dev-logs` |
| Pick up backend code changes | `make dev-up` again; it rebuilds changed images |
| Frontend code changes | nothing; the dev server reloads the page |
| Stop the APIs, keep the data | `make dev-down` |
| Stop and wipe the database | `make dev-reset` |
| List every target | `make help` |

## Tests and checks

These are the same checks CI runs on every push (`.github/workflows/ci.yml`):

```sh
make install         # needs uv: creates services/.venv
make lint            # ruff
make test-db         # all Python tests, against the compose Postgres
make frontend-test   # ESLint, vitest, production build
```

Optional, if you have the tools: `make k8s-check` (needs `kustomize` and `kubeconform` on `PATH`), and `terraform -chdir=infra/terraform/envs/prod test` (Terraform 1.16.4; [tfenv](https://github.com/tfutils/tfenv) picks it from `infra/terraform/.terraform-version`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `permission denied while trying to connect to the docker API` | See [Docker permissions](#docker-permissions). |
| `Cannot connect to the Docker daemon` | Start it: `sudo systemctl start docker` (Linux) or open Docker Desktop (WSL2). |
| `port is already allocated` / `address already in use` | Something else uses 55432, 8081, 8082, or 5173. Find it with `sudo ss -ltnp \| grep -E ':(55432\|8081\|8082\|5173)'` and stop it. A leftover stack goes away with `make dev-down`. |
| `npm ci` fails with an engine or syntax error | Node is too old: `cd frontend && nvm install && nvm use`. |
| Frontend loads but shows "Could not reach the server" or 502s | The APIs aren't running: `make dev-up`, then `make smoke`. |
| `make dev-up` says the `migrate` service failed | `docker compose logs migrate` (prefix `sudo` if you use the sudo option). `make dev-reset` starts from an empty database. |
| `make smoke` fails on the first `readyz` check | The APIs are still starting or crashed: `make dev-logs`. |
| WSL2: `docker: command not found` | Turn on Docker Desktop's WSL integration for your distro and reopen the terminal. |
| WSL2: very slow builds, or the frontend doesn't reload | The repo is under `/mnt/c`; clone it into `~` instead. |
