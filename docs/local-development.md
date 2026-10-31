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

The frontend's dev server forwards `/ingest/*` to `:8081` and `/search/*` to `:8082`, so the browser only ever talks to `localhost:5173`. Locally the APIs accept **dev sign-in** (`Authorization: Bearer dev:<email>`) instead of Google. Sign-in is invite-only ([ADR 0002](architecture_decision_records/0002-invite-only-users-and-admin-roles.md)): docker compose invites `prof@example.edu` (professor and admin) and `student@example.edu`; any other email gets "not invited" until someone invites it.

## Prerequisites

| Tool | Version | Needed for |
|---|---|---|
| git, make, bash, curl, python3 | any recent | everything (`make`, `scripts/smoke-test.sh`) |
| Docker Engine with the Compose plugin | Compose v2.20 or newer | `make dev-up`: Postgres and both APIs |
| Node.js with npm | 22.22 or newer (`frontend/.nvmrc`) | the frontend |
| [uv](https://docs.astral.sh/uv/) | latest; it installs Python 3.12 itself | only `make install`, `lint`, `test`, `test-db` |

You don't need Python packages, Postgres, Terraform, kubectl, or any cloud CLI to run the app. `make k8s-check` (kustomize, kubeconform) and Terraform are optional locally, because CI checks them on every push. The cloud CLIs are needed only to operate the deployed environment ([Install cloud tools](#install-cloud-tools-optional)).

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

## Install cloud tools (optional)

Only for the `make cloud-*` targets, which operate the deployed environment, for example pausing and resuming it between test sessions ([runbook §7](runbooks/bootstrap.md#7-control-cost)). Running the app locally doesn't need them.

| Target | Needs |
|---|---|
| `cloud-status`, `cloud-pause`, `cloud-resume`, `cloud-backup` | `gcloud`, `kubectl`, `gke-gcloud-auth-plugin` |
| `cloud-admin`, `cloud-create-admin` | the same, plus `jq` |
| `cloud-backup-sas` | `gcloud`, `az` |
| `cloud-restore` | the first row, plus `az`, `jq`, `age`, and `psql` and `pg_restore` 16 or newer |

`make doctor` checks only the first row. `jq` and `age` come from `sudo apt install jq age`; for `az`, see the [Azure CLI install guide](https://learn.microsoft.com/cli/azure/install-azure-cli).

On Ubuntu, Debian or WSL2, the first row's three tools come from Google's apt repository:

```sh
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update
sudo apt-get install -y google-cloud-cli kubectl google-cloud-cli-gke-gcloud-auth-plugin

gcloud auth login
gcloud config set project <project-id>
```

`gke-gcloud-auth-plugin` is how `kubectl` signs in to GKE; without it, every `kubectl` call to the cluster fails. The scripts use `kubectl kustomize`, so a separate `kustomize` isn't needed.

Your Google account also needs permission to stop and start Cloud SQL and to change workloads in the cluster: Owner covers both; otherwise Cloud SQL Admin and Kubernetes Engine Developer.

**Without installing anything:** [Cloud Shell](https://shell.cloud.google.com) has all three tools and is already signed in. Clone the repository there and run the `make cloud-*` targets.

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
- **`prof@example.edu`** sees the **Manage** page (create courses, register and remove lectures) and the **Admin** page (invite users, change roles, grant admin).
- **`student@example.edu`**: browse courses and search them.
- **Any other email** is refused until `prof@example.edu` invites it on the Admin page, or you run `docker compose run --rm --entrypoint li-admin seed add-user EMAIL --role professor`.

**Registering a lecture fails in dev mode**, with a YouTube token error. The Ingest API really calls YouTube with your Google token, so it needs real Google sign-in and your own video with YouTube auto-generated captions. That's described in the implementation plan, [Next: real Google/YouTube test](implementation-plan.md#next-real-googleyoutube-test-free-before-deploying).

## Day to day

| Task | Command |
|---|---|
| See API logs | `make dev-logs` |
| Pick up backend code changes | `make dev-up` again; it rebuilds changed images |
| Frontend code changes | nothing; the dev server reloads the page |
| Stop the APIs, keep the data | `make dev-down` |
| Stop and wipe the database | `make dev-reset` |
| Rebuild the Milestone 2 report PDF | `make report` (needs `pdflatex`, `latexmk` and IEEEtran) |
| List every target | `make help` |

## Tests and checks

These are the same checks CI runs on every push (`.github/workflows/ci.yml`):

```sh
make install         # needs uv: creates services/.venv
make lint            # ruff
make test-db         # all Python tests, against the compose Postgres
make frontend-test   # ESLint, vitest, production build
make frontend-image  # the production nginx image (Docker; DOCKER="sudo docker" if needed)
make docs-check      # document links and repository paths (needs only python3 and git)
```

`make format` applies the fixes and formatting that `make lint` checks.

**Use `make test-db`, not `make test`.** Tests marked `db` need a Postgres at `DATABASE_URL`. Plain `make test` doesn't set it, so it **skips** them and still passes. Those skipped tests include every API route test and every auth test. `make test-db` starts the compose Postgres and sets `DATABASE_URL` for you. Each test creates and drops its own schema, so your dev data is untouched.

### Run one test file or one test

While working on one area, run just its tests. The compose Postgres must be up: `make test-db` starts it, or run `docker compose up -d --wait db` (with `sudo` if needed).

```sh
cd services
export DATABASE_URL=postgresql://li:li@localhost:55432/li   # once per terminal

uv run pytest ingest/tests/test_admin_routes.py                 # one file
uv run pytest ingest/tests/test_admin_routes.py::test_admin_grants_and_revokes_admin   # one test
uv run pytest -k invite                                          # tests whose name contains "invite"
uv run pytest -x --lf                                            # rerun only last run's failures, stop at the first
```

Paths are relative to `services/`. Add `-v` to list every test, or `-s` to see `print` output.

Frontend tests don't need a database:

```sh
cd frontend
npx vitest run src/pages/AdminPage.test.tsx     # one file
npx vitest run -t "own row"                     # tests whose name matches
npx vitest                                      # watch mode: reruns on save
```

### Check sign-in and roles by hand

The automated tests cover the rules. Before merging a change to sign-in, roles or the Admin page, also click through it once ([ADR 0002](architecture_decision_records/0002-invite-only-users-and-admin-roles.md) and [ADR 0003](architecture_decision_records/0003-merge-superuser-into-admin.md) describe the model). Start the stack and the frontend ([Run the app](#run-the-app)), open http://localhost:5173, and sign in as each account in turn. To switch accounts, use **Sign out**.

| Sign in as | Do | Expect |
|---|---|---|
| `x@example.edu` (under "Other email") | Just sign in | "You haven't been invited yet" |
| `prof@example.edu` | Look at the nav | **Courses**, **Manage** and **Admin** |
| `prof@example.edu` | On **Admin**, invite `new@example.edu` as Professor | "Invited 1."; the row shows `invited` |
| `new@example.edu` | Sign in, open **Manage** | You can create a course |
| `prof@example.edu` | On **Admin**, set `new@example.edu` to Student, and tick its *Admin* box | Its row now shows `active` (the invitation was claimed); both changes save |
| `new@example.edu` | Open **Manage**, then **Admin** | "Only professors can manage courses"; **Admin** works, but on your own row only the role can be changed |
| `new@example.edu` | Set **Your role** in the top bar to professor, then back to student | **Manage** appears and disappears; **Admin** stays |
| `prof@example.edu` | **Disable** `student@example.edu` | The row shows `disabled` |
| `student@example.edu` | Sign in | "Account disabled". Afterwards, sign back in as `prof@example.edu` and **Enable** it again |

Role changes apply on the next request, so you don't need to wait for anything. To undo everything, run `make dev-reset`. That also deletes your local courses. Afterwards, `make dev-up` invites the two default accounts again.

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
