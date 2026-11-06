# AI usage log: Claude Code session, 2026-11-06 (final presentation slides)

| | |
|---|---|
| Tool | Claude Code (VS Code extension), model Claude Opus 5.5 |
| User | [redacted] |
| Date | 2026-11-06 |
| Branch | `twp__slides`. No code changed and nothing was committed in the session |
| Outputs | A diagram page (Claude artifact). The Application Layer: Implementation slide in the team's Google Slides deck. Talking points for slides 13 to 23 in the presenter's Google Doc |
| Outcome | The application layer is drawn in the same style as the front-end slide, the Application Layer slides were checked against the code, and every Front End and Application Layer slide from 13 to 23 has talking points that follow the slide |

Each entry gives the prompt, then a summary of what Claude did in response.

---

## 1. A diagram of the application layer

The user asked for a diagram of the application layer. Claude read the Kubernetes manifests, Dockerfiles and route files first, so the numbers and names match what is deployed: pod counts, Gunicorn settings, routes, database roles and the NetworkPolicy. It published the diagram as a private artifact page, with route tables for both APIs.

## 2. The diagram on the slide

The user asked for the diagram in the deck, in the style of the existing front-end diagram. Claude read that slide's shapes and colors, built the application diagram on the target slide from the same elements, and checked a rendered image of it. It shortened the load balancer's route text after the first render, and later nested each Flask app inside a Gunicorn box when the user asked.

## 3. Questions before the talk

The user asked why each part of the application layer is there: the Cloud SQL proxy, sidecars, the load balancer, Flask, Gunicorn, psycopg, GKE, nodes, the HPA and private nodes. Claude answered from the repository and the proposal, and said when the repository records no reason for a choice. Asked whether GKE makes the YouTube API easier to reach, it said not really, and suggested more accurate wording for the slide.

## 4. Talking points and consistency checks

Claude added talking points for slides 16 to 23 to the presenter's Google Doc, in the format the doc already used, and listed issues on the slides. The user changed the slides and asked for a consistency review. Claude found the talking points no longer matched where the HPA had moved, then fixed both. It also added talking points for slides 13 to 15, and removed the slide 12 notes that repeated slide 15.

## 5. What went wrong

- **Concurrent edits.** Someone else was editing the deck while Claude built the diagram, so Google rejected its first two writes. Nothing was applied either time, and the third attempt went through.
- **A wording fix before sending.** Claude's first draft labeled the Search proxy's login "read-only". Search can also claim an invitation at sign-in, so Claude changed it to "read-mostly" before writing it to the slide.
- **A wrong network path.** Claude's first answer, and its diagram page, said Ingest reaches the YouTube API through Cloud NAT. The network module sends Google APIs through Private Google Access instead, and Claude said so correctly when the user asked about private nodes later. The diagram page was not updated.
- **Empty lines left on four slides.** Claude reported that empty last lines might show as empty bullets. On a closer read they had no bullet, and deleting them could have removed the bullet from the line above, so Claude left them.

## 6. Transcript

The user's prompts as typed, each followed by Claude's closing response for that turn, also exact. Short progress notes between tool calls and the tool output are left out. Internal links are rewritten so they resolve from this folder. The last prompt, which asked for this log, is not included.

### Prompt 1

> can you create a diagram of the application layer implementation?

**Claude:**

> I made a diagram of the application tier: [link]
>
> Written for: you and your team. I'm guessing the audience is the final presentation, since you're on the `twp__slides` branch.
>
> I built it from the actual Kubernetes manifests, Dockerfiles and route files, so the numbers and names match what's deployed. It follows a request from top to bottom:
>
> - **Entry:** the web app gets an ID token from Google Sign-In and sends it to the HTTPS load balancer (Ingress `li-api`). The load balancer sends `/ingest/*` to the Ingest API and `/search/*` to the Search API.
> - **Inside GKE Autopilot:** each service has its own scaling rule: Ingest runs 1 to 4 pods and Search 1 to 6, both targeting 70% CPU. Each pod has two containers:
>   - the app: Flask under gunicorn, with timeouts of 120 s for Ingest and 30 s for Search. The diagram lists its routes and shows the shared `li_common` code.
>   - the `cloud-sql-proxy` sidecar, which logs in to the database with the pod's own Google Cloud identity.
> - **Database:** each proxy connects to Cloud SQL with its own database role. Ingest gets `li_ingest_role` (read/write) and Search gets `li_search_role` (read, plus claiming invitations at sign-in).
> - **Outside calls and setup:** only Ingest calls the YouTube Data API, through Cloud NAT. The migrate Job is drawn dashed, off to the side, because it runs before each rollout rather than on every request.
>
> Under the diagram are route tables for both APIs and a short list of what the two services share.
>
> The link is private, so your teammates can't open it until you share it from the page's Share menu. If you want the diagram in the repo instead, I can also do a Mermaid version for `docs/architecture.md`.

### Prompt 2

> can you make the diagram similar to the front end one found here: [link]
> and put the application diagram here:
> [link]

**Claude:**

> I added the application diagram to the Application Layer: Implementation slide. The deck link stays the same. I checked the rendered slide and nothing overflows or overlaps.
>
> It uses the same style as the front-end slide: the same fonts, colors and arrows, light blue for the parts we built and gray for anything outside this layer. It reads left to right:
>
> - **Web app** (gray) sends requests to the **HTTPS load balancer**, which routes `/ingest/*` and `/search/*`.
> - Inside a **GKE Autopilot** box there are two dashed pod boxes: **Ingest pod, 1 to 4 copies** and **Search pod, 1 to 6 copies**.
> - Each pod holds a **Flask app** and a **Cloud SQL proxy** sidecar. Ingest's proxy has a read/write login and Search's has a read-mostly one.
> - Both proxies connect to **Cloud SQL** (gray) on the right.
> - The footer says each pod scales out at 70% CPU and that the proxy logs in with the pod's Google identity, so no database passwords are stored.
>
> The YouTube call is a line of text in the Ingest app box rather than its own box and arrow, to keep the layout as simple as the front-end slide.
>
> I also deleted the empty body text box that was on the slide, since the diagram takes its place, as on the front-end slide.
>
> Someone else was editing the deck while I worked, so Google refused my first two attempts. Nothing was applied either time, and the third attempt went through. If the slide looks unchanged on your screen, reload the deck.

### Prompt 3

> what is the purpose of the cloud sql proxy?

**Claude:**

> The proxy is a small helper container in each pod that connects the Flask app to the database. It does two jobs the app would otherwise have to do itself.
>
> 1. **It logs in without a password.** It uses `--auto-iam-authn`, so it signs in to Cloud SQL as the pod's own Google identity, through Workload Identity. Each service's identity maps to its own database role: `li_ingest_role` for read/write, and `li_search_role` for reads plus claiming invitations at sign-in. No password is stored in the code, the environment or a Kubernetes secret, and each service can only do what its role allows.
> 2. **It handles the secure connection.** The proxy opens an encrypted connection to Cloud SQL's private IP (`--private-ip`). The app just connects to `127.0.0.1:5432` with plain TCP, as if Postgres were running locally. That's why `DATABASE_URL` in [deployment.yaml](../../../deploy/k8s/base/search/deployment.yaml) is `host=127.0.0.1 ... sslmode=disable`. The traffic only leaves the pod after the proxy has encrypted it.
>
> **Why a separate container:** Google's other option, the Cloud SQL Python Connector, doesn't support psycopg, the Postgres driver the services use. That's recorded in the Decisions table in [docs/architecture.md](../../../docs/architecture.md).
>
> **A side benefit:** the app code is the same locally and in production. Locally, `DATABASE_URL` points at a regular Postgres in Docker Compose. In GKE, it points at the proxy, and the app can't tell the difference.
>
> The proxy runs as a native sidecar, which means it starts before the app and stops after it. The app never starts without a database connection available. In the migrate Job, the proxy also exits on its own, so the Job can finish.
>
> For the slide, you could say it in one line: "The proxy gives each pod a passwordless, encrypted connection to the database, using the pod's own identity and permissions."

### Prompt 4

> what does sidecar mean?

**Claude:**

> A sidecar is a helper container that runs next to the main app container in the same pod and supports it. The name comes from a motorcycle sidecar: attached to the main vehicle, going everywhere it goes, but not the thing doing the driving.
>
> In Kubernetes, a pod can hold more than one container. Containers in the same pod:
>
> - **share a network.** They see each other on `localhost`, which is why the Flask app reaches the proxy at `127.0.0.1:5432`.
> - **are scheduled together.** Every copy of the pod gets its own app and its own proxy, so when the autoscaler adds a fourth Ingest pod, that pod comes with its own proxy.
> - **live and die together.** When the pod is removed, both containers go with it.
>
> The point of the pattern is to keep the app simple. The Flask code only knows "there's a Postgres on localhost." Everything about reaching the real database (encryption, Google login, the private IP) lives in the sidecar, which is Google's ready-made container. You could swap or upgrade the proxy without touching the app.
>
> **"Native" sidecar** is a newer Kubernetes feature. Our proxy is declared under `initContainers` with `restartPolicy: Always` (see [deployment.yaml](../../../deploy/k8s/base/search/deployment.yaml)). That tells Kubernetes to start the proxy first, wait until it's ready, then start the app, and to stop the proxy last. Before this feature existed, sidecars started in no particular order, so the app could boot before its database connection was ready. Also, a Job like our migrations would never finish, because the sidecar kept running after the main container exited.
>
> For the slide, one line works: "Sidecar: a helper container in the same pod as the app, handling the database connection so the app doesn't have to."

### Prompt 5

> Could you also show that the flask apps are wrapped in Gunicorn?

**Claude:**

> The Application Layer: Implementation slide now shows each Flask app wrapped in Gunicorn. The deck link stays the same, and I checked the rendered slide: nothing overflows or overlaps.
>
> - **Nesting:** each Flask app now sits inside a blue-outlined box labeled **Gunicorn server**, the same way dist/ and nginx sit inside the Docker container on the front-end slide.
> - **Arrows:** the load balancer's arrows now end at the Gunicorn box, because Gunicorn is what receives the request and hands it to Flask. Gunicorn's arrow then goes on to the proxy.
> - **Box text:** I shortened the Flask subtitles to fit the smaller boxes. Ingest's now reads "courses, lectures, YouTube captions" and Search's reads "full-text search over captions".
> - **Footer:** it now reads "Gunicorn runs each Flask app as 2 processes × 4 threads. Pods scale out at 70% CPU. The proxy logs in as the pod's Google identity." The "no database passwords" wording is gone to make room.
>
> If you're asked why Gunicorn is there: Flask's built-in server is meant for development and handles requests poorly under load. Gunicorn is a production server that runs several copies of the Flask app at once. Here that's 2 worker processes with 4 threads each, so each pod can handle up to 8 requests at a time.

### Prompt 6

> what is the purpose of the load balancer?

**Claude:**

> The load balancer is the one public way into the APIs. It does four jobs:
>
> 1. **Gives the APIs one public address.** The GKE nodes and pods have private IPs only, so nothing on them can be reached from the internet. The load balancer sits on a reserved global IP with the hostname `<ip>.sslip.io`. It's the only thing the web app talks to.
>
> 2. **Handles HTTPS.** It holds a Google-managed certificate for that hostname and decrypts the traffic, so Gunicorn and Flask never deal with certificates. It also redirects plain HTTP to HTTPS (the `FrontendConfig` in [ingress.yaml](../../../deploy/k8s/base/ingress.yaml)).
>
> 3. **Routes by path.** Requests starting with `/ingest` go to the Ingest service and `/search` to the Search service. That's why both APIs share one hostname and one certificate.
>
> 4. **Spreads requests across pods and avoids unhealthy ones.** When the autoscaler adds pods, for example Search going from 1 to 6, the load balancer starts sending traffic to the new pods automatically. It checks each pod's `/readyz` and stops sending requests to any pod that fails, such as one that's starting up or being evicted from a Spot node.
>
> It's also part of the security setup. The NetworkPolicy in [networkpolicy.yaml](../../../deploy/k8s/base/networkpolicy.yaml) only lets traffic into the API pods on port 8080 from Google's load balancer IP ranges (`35.191.0.0/16` and `130.211.0.0/22`). Everything else is blocked, even from inside the cluster.
>
> We don't run it ourselves. It's a Google Cloud HTTPS load balancer that GKE creates from our Kubernetes Ingress object `li-api`. That's also why `make cloud-pause` deletes the Ingress to save money: deleting the Ingress removes the load balancer, which costs money even when idle. The reserved IP is kept, so the hostname survives the pause.
>
> For the slide, in one line: "The load balancer is the single HTTPS entry point: it terminates TLS, routes /ingest and /search to their services, and spreads requests across healthy pods."

### Prompt 7

> why did we choose flask?

**Claude:**

> The repo gives one reason: the team already knew Flask. The Decisions table in [docs/architecture.md](../../../docs/architecture.md) records it as "Team choice", and the presentation summary says "We used Flask because the team knows it." There's no ADR comparing it against other frameworks.
>
> The docs name FastAPI as the alternative. FastAPI's usual selling points are built-in request validation, automatic JSON error responses and async support. Here's how we handled each without it:
>
> - **Validation and JSON errors.** The shared `li_common` package adds both to Flask: pydantic models validate request bodies and query strings, and error handlers return JSON. It also adds the `/healthz` and `/readyz` checks. The docs say it directly: "What FastAPI would have given us lives in `li_common`."
> - **Async.** We don't need it. Each request is short: a database query, or a few YouTube calls during ingest. Gunicorn's 2 workers × 4 threads per pod, plus the autoscaler adding pods, cover the concurrency.
>
> So the trade was familiar code in exchange for writing a small shared library ourselves.
>
> Flask also suits services this small. Each one is just a `create_app()` function plus one or two blueprints (groups of routes), with no project structure or ORM forced on us. That fits the rest of the design: plain `.sql` migrations and no ORM.
>
> For the slide:
>
> - **Team already knew Flask**
> - **Small, simple services:** one app factory and one or two blueprints each
> - **The gaps are filled by our shared `li_common` package:** validation (pydantic), JSON errors and health checks
>
> If someone asks "why not FastAPI?", the honest answer is that it would have worked too. We picked what the team knew and added the few missing pieces ourselves.

### Prompt 8

> why gunicorn?

**Claude:**

> Flask can't serve production traffic by itself, so it needs a separate web server, and Gunicorn is the standard choice for Flask on Linux. The repo doesn't record a comparison with other servers. The Decisions table in [docs/architecture.md](../../../docs/architecture.md) just says "Flask served by gunicorn (`--workers 2 --threads 4`)".
>
> **Why a server is needed at all.** Flask follows WSGI, Python's standard interface between web apps and web servers. Flask ships with a development server (`flask run`), but it's meant for local testing: it isn't built for heavy concurrent load, and Flask's own docs say not to use it in production. A WSGI server such as Gunicorn takes in the HTTP requests, manages the processes and threads, and calls Flask for each request.
>
> **Why Gunicorn in particular:**
>
> - **It's the usual default.** Flask's deployment docs list it first, and it's simple: a single command in the Dockerfile, `gunicorn ... "search:create_app()"`, with no extra config file.
> - **It runs requests in parallel.** Each pod runs 2 worker processes with 4 threads each, so up to 8 requests at once. The threads help because most of the time is spent waiting on the database or the YouTube API, not on the CPU.
> - **It sets a timeout per service.** Search requests are cut off after 30 s and Ingest requests after 120 s, because registering a lecture downloads captions inside the request.
> - **It shuts down gracefully.** On a stop signal it finishes requests that are already running before exiting. That matters on Spot nodes, where GKE gives 25 seconds' notice before evicting a pod.
> - **It restarts crashed workers**, so one bad request doesn't take the pod down.
>
> **One setup detail it needed:** the containers have read-only root filesystems, but Gunicorn writes small temporary files. So each pod mounts an in-memory `/tmp`; the comment in [deployment.yaml](../../../deploy/k8s/base/search/deployment.yaml) says "gunicorn needs a writable temp dir".
>
> The alternatives would have been uWSGI, Waitress, or switching to an async server like Uvicorn. Uvicorn only makes sense with an async framework like FastAPI, and we chose Flask.
>
> For the slide:
>
> - **Flask's built-in server is for development only**
> - **Gunicorn is the standard production server for Flask**
> - **2 processes × 4 threads per pod, so 8 requests at once**
> - **Timeouts per service, and a graceful shutdown before Spot evictions**

### Prompt 9

> is Cloud SQL proxy a package?

**Claude:**

> No, not in the sense of a Python package. It isn't in our `pyproject.toml` or `uv.lock`, and the Flask code never imports it. It's a separate program that Google publishes as a ready-made container image. We run that image next to our app in the same pod:
>
> ```yaml
> image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.26.2
> ```
>
> ([deployment.yaml](../../../deploy/k8s/base/search/deployment.yaml)). It's a small standalone program written in Go, and we only pass it command-line options: `--auto-iam-authn`, `--private-ip`, and the database's connection name.
>
> - **Our code doesn't depend on it.** The app just uses the normal Postgres driver, psycopg, to connect to `127.0.0.1:5432`. As far as Flask knows, it's talking to an ordinary Postgres.
> - **We don't build or install it.** It isn't in our Dockerfiles. Kubernetes pulls Google's image when the pod starts, and upgrading it means changing the version tag in the manifest.
> - **It's only used in GKE.** Locally, Docker Compose runs a plain Postgres container, so no proxy is needed.
>
> Google does make a Python package that does a similar job, the **Cloud SQL Python Connector** (`cloud-sql-python-connector` on pip). That one *would* be imported into the app. We didn't use it because it doesn't support psycopg, which is why the architecture doc chose the proxy instead.
>
> For the slide: "The Cloud SQL Auth Proxy is a separate Google-provided container, not a library in our code. The app just sees a local Postgres."

### Prompt 10

> why do we use cloud sql proxy vs having the flask app talk to database directly?

**Claude:**

> The Flask app could connect directly: Cloud SQL has a private IP inside our network, so the pods can reach it. But then the app, or our setup, would have to handle three things the proxy does for us.
>
> **1. Login without a password.**
> - *Direct:* the usual way is a database username and password. The password has to live somewhere the pod can read it, like Secret Manager or a Kubernetes secret, and then it has to be rotated and kept out of logs.
> - *Proxy:* with `--auto-iam-authn`, it logs in as the pod's own Google identity. No database password exists for the services at all. The only password in the project is the `li_admin` one used by the migration job.
> - You *can* do IAM login directly, but the app would have to fetch a short-lived OAuth token and use it as the password, and refresh it before it expires, roughly every hour. The proxy does all of that.
>
> **2. Encryption and identity checks.**
> - *Direct:* to encrypt the connection properly, the app needs Cloud SQL's server certificate and the right SSL settings, and those have to be kept up to date.
> - *Proxy:* it connects to Cloud SQL using Google's own certificates and checks that it is talking to the right instance. The app uses plain TCP to `127.0.0.1`, which never leaves the pod, so `sslmode=disable` in `DATABASE_URL` is safe.
>
> **3. Permissions per service.**
> - Each pod's Google identity maps to its own database user and role: Ingest gets read/write, and Search gets read plus claiming invitations. A leaked credential or a bug in Search can't write lectures. With a shared password, that separation is easy to lose.
>
> **Why not Google's Python library instead?** Google's Cloud SQL Python Connector does the same work inside the app, but it doesn't support psycopg, the driver we use. The architecture doc records that as the reason for the proxy.
>
> **What the proxy costs us:**
> - an extra container in every pod (50m CPU and 64 MiB of memory requested)
> - one more thing that can fail. It has its own startup and liveness checks.
> - startup order. That's why it runs as a *native* sidecar: it's ready before the app starts and stops after the app.
>
> **Bonus:** the app code is the same everywhere. Locally it points at a plain Postgres in Docker Compose. In GKE it points at the proxy, and Flask can't tell the difference.
>
> For the slide:
>
> - **No database passwords:** each pod logs in with its own Google identity
> - **Encryption handled for us:** the app talks to localhost, and the proxy secures the connection to Cloud SQL
> - **Least privilege:** Ingest can write, and Search can mostly only read
> - **Same app code locally and in the cloud**

### Prompt 11

> why are we using psycopg?

**Claude:**

> Flask can't talk to Postgres by itself. Python needs a database driver, a library that speaks Postgres's network protocol, and psycopg is the standard one. Like Flask and Gunicorn, the repo doesn't record a comparison with alternatives. It's simply the default choice, and it fits how the rest of the data access is written.
>
> **What we use:** psycopg 3 (`psycopg[binary,pool]>=3.2` in [services/common/pyproject.toml](../../../services/common/pyproject.toml)), wrapped in [db.py](../../../services/common/src/li_common/db.py) in `li_common`.
>
> **Why it fits:**
>
> - **We write SQL by hand, with no ORM.** The architecture doc chose plain numbered `.sql` migrations and no ORM. psycopg runs SQL directly with safe parameter binding, which also protects against SQL injection. Even with an ORM like SQLAlchemy, psycopg would usually still be the driver underneath.
> - **Search uses Postgres-only features.** Full-text search relies on `tsvector`, GIN indexes and Postgres's search functions. You write these as raw SQL anyway, and psycopg passes them through unchanged.
> - **Connection pooling.** The `pool` extra gives us `psycopg_pool.ConnectionPool`. Each Gunicorn worker keeps database connections open and reuses them instead of reconnecting on every request. The pool opens lazily, so the app and `/healthz` can start before the database is reachable.
> - **It works with threads.** Gunicorn runs 4 threads per worker, and psycopg's pool is thread-safe. Async drivers like asyncpg would need an async framework, and Flask isn't one.
> - **Results come back as dictionaries.** The pool sets `row_factory=dict_row`, so rows come back as `{"title": ...}` rather than tuples, which converts easily to JSON responses.
> - **Easy to install.** The `binary` extra ships the compiled C library inside the package, so the Docker images don't need Postgres's development libraries.
>
> **The trade-off you've already seen:** Google's Cloud SQL Python Connector doesn't support psycopg; for Postgres it works with pg8000 and asyncpg. We kept psycopg and used the proxy sidecar instead. That also kept [db.py](../../../services/common/src/li_common/db.py) free of anything Cloud SQL-specific: it just takes a connection string.
>
> For the slide:
>
> - **psycopg: the standard Python driver for PostgreSQL**
> - **Plain SQL with safe parameters, needed for Postgres full-text search**
> - **A connection pool reuses connections across Gunicorn's threads**
> - **Works with the proxy, so the app code knows nothing about Cloud SQL**

### Prompt 12

> Why did we pick google gke for the application layer?

**Claude:**

> The course required Kubernetes for this layer, and the proposal explains why we picked Google's version of it.
>
> **The requirement.** [project-requirements.md](../../../docs/milestones/m1_project_proposal/project-requirements.md) says the application tier **must use containers and Docker**, deployed on one of AKS (Azure), EKS (Amazon) or GKE (Google). So the real question was which cloud's Kubernetes to use.
>
> **Why GKE, from Section VI of the proposal:**
>
> 1. **Ecosystem fit.** The app depends on two Google services: the YouTube Data API and Google sign-in. Both are configured in a Google Cloud project, so putting the backend in that same project keeps the OAuth clients, API quotas and logs together.
> 2. **Cost.** GKE's free-tier credit covers the management fee for one Autopilot or zonal cluster, while Amazon EKS charges for every hour a cluster exists. The proposal doesn't compare against AKS directly.
>
> **Why Autopilot mode:** Autopilot adds and removes nodes to fit the pods, so we never manage VMs. Google handles node sizing, patching and upgrades, and we only describe pods. It's also what makes our cost choices easy: Spot pods (around 60 to 90% cheaper) and scaling down to almost nothing when `make cloud-pause` runs.
>
> **What it gave us once we built it** (my reading of the code, not stated in the proposal):
>
> - **Workload Identity:** each pod runs as its own Google service account. That's how the Cloud SQL proxy logs in without a password, and how the backup job reads its credential from Secret Manager.
> - **Cloud SQL nearby:** the cluster and the database share a private network, so the database needs no public IP.
> - **Managed HTTPS:** a Kubernetes Ingress object automatically creates the Google load balancer and its certificate.
> - **One cloud for the whole backend:** Artifact Registry, Secret Manager and Cloud Monitoring are all in the same project, managed by one Terraform setup and one keyless CI identity.
>
> For the slide:
>
> - **Kubernetes was required:** GKE, AKS or EKS
> - **Same project as YouTube and Google sign-in**
> - **Free-tier credit covers the cluster fee; EKS charges hourly**
> - **Autopilot: no VMs to manage, and Spot pods to cut cost**

### Prompt 13

> are nodes copies of the pod?

**Claude:**

> No. A node is a machine, and a pod is something that runs on a machine.
>
> | Term | What it is | In our setup |
> |---|---|---|
> | **Node** | A virtual machine (VM) that provides CPU and memory | Created and removed by GKE Autopilot; we never see or manage them |
> | **Pod** | The smallest unit Kubernetes runs: one or more containers sharing a network | One Ingest pod = Gunicorn/Flask container + Cloud SQL proxy sidecar |
> | **Replica** | One copy of a pod | Ingest runs 1 to 4 replicas and Search runs 1 to 6 |
>
> So the "copies" are **pod replicas**. The "1 to 4 copies" and "1 to 6 copies" on the slide mean pod replicas, not nodes.
>
> **How they relate:**
>
> - One node usually runs **several pods**, often a mix, such as an Ingest pod and a Search pod side by side.
> - Kubernetes decides which node each pod runs on, based on the CPU and memory the pod asks for. Our API pods request 250m CPU (a quarter of a core) and 512 MiB of memory, plus 50m CPU for the proxy.
>
> **Two levels of scaling:**
>
> 1. **More pods.** When average CPU goes above 70%, the HPA (horizontal pod autoscaler) adds pod replicas, for example Search going from 2 to 3.
> 2. **More nodes.** If the new pod doesn't fit on the existing nodes, Autopilot adds a node. When pods are removed, it removes nodes that are no longer needed.
>
> We only configure the first level. Autopilot handles the second, which is what "no VMs to manage" means.
>
> **A detail relevant here:** our pods ask for **Spot** nodes (`cloud.google.com/gke-spot: "true"`). Spot nodes are spare Google capacity, much cheaper, but Google can take them back with 25 seconds' notice. When that happens, Kubernetes recreates the pods on another node, and the load balancer stops sending them traffic in the meantime.
>
> An analogy for the talk: nodes are the servers in the building, and pods are the apps running on them. Scaling up means running more copies of the app first, then adding servers if the building is full.

### Prompt 14

> is hpa standard with GKE?

**Claude:**

> Yes, but it's a standard Kubernetes feature, not something specific to GKE. The HPA (horizontal pod autoscaler) is part of Kubernetes itself (API `autoscaling/v2`), so the same [hpa.yaml](../../../deploy/k8s/base/search/hpa.yaml) would work on AKS or EKS too.
>
> What GKE provides:
>
> - **CPU and memory metrics out of the box.** The HPA needs a metrics source to know each pod's CPU. GKE has one running in every cluster. On some other platforms, such as a plain EKS cluster, you have to install the Kubernetes metrics-server yourself before an HPA works.
> - **Node scaling to match.** The HPA only adds pods. Autopilot adds the nodes those pods need, with no setup from us.
>
> What it doesn't do automatically: no app gets an HPA by default. You create one per deployment, which we did:
>
> ```yaml
> minReplicas: 1
> maxReplicas: 6        # 4 for ingest
> metrics:
>   - resource:
>       name: cpu
>       target: { type: Utilization, averageUtilization: 70 }
> ```
>
> The 70% is measured against each pod's CPU *request* (250m), so the HPA adds a pod when the average pod is using more than about 175m CPU. That's also why the deployments have no `replicas:` field: the HPA owns the pod count.
>
> GKE also supports scaling on other metrics, such as request rate from the load balancer or a Cloud Monitoring metric, but we only use CPU.
>
> For the slide: "HPA is built into Kubernetes; GKE supplies the CPU metrics, and Autopilot adds nodes when new pods need room."

### Prompt 15

> why are we using private nodes?

**Claude:**

> Private nodes keep the machines running our pods off the internet. The architecture doc's reason is: "Nothing but the load balancer is reachable from the internet."
>
> **What "private nodes" means.** The nodes (VMs) get internal IP addresses only. Set in [modules/gke/main.tf](../../../infra/terraform/modules/gke/main.tf):
>
> ```hcl
> private_cluster_config {
>   enable_private_nodes    = true
>   enable_private_endpoint = false
> }
> ```
>
> Nobody on the internet can connect to a node or a pod directly. Traffic comes in only through the HTTPS load balancer, and the NetworkPolicy then lets in only load-balancer traffic on port 8080.
>
> **Why it matters:**
>
> - **Smaller attack surface.** A public node would expose every open port: the kubelet, SSH, any mistake in a pod's config. With private nodes, there's only one way in, and it's the load balancer we configured.
> - **Defense in depth.** It's one of several layers working together: private nodes, the NetworkPolicy, private-IP Cloud SQL, and non-root, read-only containers. If one layer is misconfigured, the others still hold.
> - **The proposal promised it.** Its security section names least privilege and private-IP Cloud SQL "to limit lateral access", and private nodes are the same idea applied to the cluster.
>
> **How the pods still reach the outside world.** The pods still have to make outbound calls, which [modules/gcp-network/main.tf](../../../infra/terraform/modules/gcp-network/main.tf) covers in two ways:
>
> - **Private Google Access** for Google's own APIs. That includes the YouTube Data API calls from Ingest, plus Cloud SQL, Secret Manager and Artifact Registry, without public IPs.
> - **Cloud NAT** for everything else, mainly the nightly backup upload to Azure Blob Storage. NAT lets pods start outbound connections but never accepts incoming ones.
>
> **One part stays public:** `enable_private_endpoint = false` means the cluster's control plane (the Kubernetes API that `kubectl` and the GitHub Actions deploys talk to) still has a public address. It's protected by Google sign-in and IAM, not by the network. Making it private too would mean running CI from inside the network through a VPN or a bastion host, which is more setup than this project needs.
>
> For the slide:
>
> - **Nodes have no public IPs:** the load balancer is the only way in
> - **Outbound only:** Private Google Access for Google APIs, Cloud NAT for Azure backups
> - **One security layer among several:** private nodes, NetworkPolicy, private-IP Cloud SQL, locked-down containers

### Prompt 16

> does having our app on GKE allow easier access to youtube api?

**Claude:**

> Not really. The YouTube Data API is a public HTTPS API that works the same from any cloud, or from a laptop. The proposal's "ecosystem fit" argument was about keeping things together, not about better access.
>
> **How Ingest calls YouTube.** It doesn't use the pod's Google identity at all. The professor approves a read-only YouTube permission in the browser, and the web app sends that access token with the request in the `X-YouTube-Token` header. Ingest then calls `https://www.googleapis.com/youtube/v3` with the professor's token ([youtube.py](../../../services/ingest/src/ingest/youtube.py)). The same code would work unchanged on AKS or EKS.
>
> **What being on Google Cloud actually gives us:**
>
> - **One project for everything.** The YouTube Data API is enabled in the same Google Cloud project as the OAuth client used for sign-in, and that project also holds the backend. The API quota, the OAuth consent screen and the logs live in one place under one team's access. The proposal's point was "keeps OAuth clients, quotas, and logs together." That's an admin convenience, and it would mostly hold even with the backend elsewhere, since the OAuth client and API settings have to live in a Google project either way.
> - **A slightly simpler network path.** Our nodes are private, and Private Google Access lets them reach `googleapis.com` without going through Cloud NAT. On another cloud, the call would simply go out over the internet. That's a small difference, not a capability.
> - **Possibly lower latency.** The calls stay on Google's network. For a few API calls per lecture, it doesn't matter in practice.
>
> So in the presentation, I'd avoid saying GKE gives "easier access to the YouTube API". A sharper reviewer could push back on that. A more accurate wording:
>
> > "YouTube and Google sign-in already live in a Google Cloud project, so running the backend there keeps the OAuth setup, API quotas and logs in one place."
>
> The stronger reasons for GKE were the cost (free-tier credit covers the cluster fee) and Autopilot.

### Prompt 17

> can you lookover the slides concerning Application Layer here : 
> [link]
> and add talking points for the slides here:
> [link]

**Claude:**

> I added talking points for the eight Application Layer slides (16–23) to Walter Talking Points. The doc link stays the same. They follow the format you already use: a "Slide N: Title" heading, bullets with bold lead-ins, and a bold "If asked" paragraph under some slides. I read the doc back afterwards and the headings, bullets and bold all came out right.
>
> The talking points follow the slides in order and match what's in the code:
>
> - **Purpose, Ingest and Search:** what each service does and why there are two of them. They include the YouTube ownership check and the fact that the YouTube permission is never stored, plus Search's read-mostly database login.
> - **Implementation:** a left-to-right walk through the diagram.
> - **Load Balancer and Sidecar:** what each part does, and why we use Flask, Gunicorn and the proxy instead of connecting to the database directly.
> - **Cloud Implementation and Rationale:** Autopilot, Spot pods, private nodes, and why GKE.
>
> I didn't change the slides. A few things worth fixing:
>
> 1. **Slide 23, Cloud Rationale:**
>    - "GKE is same ecosystem as YouTube" overstates it, since the YouTube API works the same from any cloud. Something like "Same Google project as YouTube and Google sign-in" is more accurate. The talking points include an "if asked" answer for this.
>    - The slide leaves out the two strongest reasons: the course required Kubernetes (AKS, EKS or GKE), and GKE's free-tier credit covers the cluster fee while EKS charges by the hour.
>    - Typo: "If pods one one node reach max". Clearer: "When new pods don't fit, Autopilot adds a node."
> 2. **Slide 21, Sidecar:** it has 11 lines, and the Horizontal Pod Autoscaler bullets aren't about sidecars. They'd fit better on slide 22 (Cloud Implementation), which only has three short lines.
> 3. **Slides 16 and 18:** each ends with an empty line in the body text box, which may show as an empty bullet in the editor.
>
> Want me to make those slide edits?

### Prompt 18

> review my talking points and the slides again for consistency

**Claude:**

> I re-read slides 16–23 and the talking points for them. You've since moved the HPA off the Sidecar slide and changed the last two slides, so most of the mismatches are in the talking points, and they're easy to fix.
>
> **Talking points that no longer match the slides**
>
> 1. **The HPA is in the wrong place.** The talking points still cover it under Slide 21 (Sidecar), but the slide now has it under Slide 22 (Cloud Implementation). Slide 23 also has "HPA allows autoscaling of pods", which has no talking point. Fix: move the HPA bullet to Slide 22, right after GKE to match the slide's order, and add a one-line HPA point to Slide 23.
> 2. **The order on Slide 22 is different.** The slide reads GKE → HPA → Autopilot → Private Nodes. The notes read GKE → Autopilot → "Nodes are not copies of pods" → Spot pods → Private nodes. The Autopilot bullet also says "the autoscaler adds pods", which should now say "the HPA adds pods". Spot pods and "nodes are not copies" aren't on the slide. They're fine as extras, but could be marked as "not on the slide", like the Slide 11 notes do.
> 3. **The order on Slide 23 is different.** The slide ends with "Free tier credits", but the notes cover cost second. Moving the Cost bullet to the end would match the slide.
>
> **Slide text worth tightening**
>
> 4. **Slide 23, "GKE is same ecosystem as YouTube":** still the overstated version. The notes soften it ("keeps the sign-in setup, API quotas and logs in one place"), and the "if asked" answer says GKE doesn't make YouTube easier to reach. That works, but the slide and the speaker will say slightly different things. "Same Google project as YouTube and sign-in" would match.
> 5. **Slide 23, "Private nodes restricts access":** should be "restrict".
> 6. **Slide 21, "Flask is a simple design":** the notes give the reasons as "the team already knew it" and "each service is small". To match the slide, open that note with "Flask is simple:". The slide also says "WSGI server" without explaining it. Adding "WSGI is Python's standard way for a web server to run a web app" to the Gunicorn note would cover it.
> 7. **"Transcripts" vs "captions":** Slide 18 says "transcripts", while Slides 17 and 19 and the notes say "captions". Either works, but choosing one avoids sounding like two different things.
> 8. **Empty lines at the end of the text on slides 16, 18, 21 and 22:** each may show as an empty bullet. Also, Slide 22's "Private Nodes" uses different capitalization from "Private nodes" on Slide 23.
>
> **Already consistent:** slides 16, 17, 19 and 20 match their notes in order and facts. The pod counts (1–4 and 1–6), the 70% CPU threshold, and "the proxy logs in as the pod's Google identity" are the same on the diagram, in the footer and in the notes.
>
> One gap outside this section: the talking-points doc has nothing for slides 13–15, the Front End rationale and cloud slides.
>
> Want me to apply the talking-point fixes (1–3, plus the wording in 6 and 7), and the slide fixes (5 and 8, and 4 if you like the wording)?

### Prompt 19

> make the fixes

**Claude:**

> I made the fixes in the deck and in the talking points, and read both back. The talking points now follow the slides in order and wording, and the headings, bullets and bold all came out right. Both links stay the same.
>
> **Slides** (deck):
> - **Slide 23:** "GKE is same ecosystem as YouTube" now reads "Same Google project as YouTube and sign-in", and "Private nodes restricts" is now "restrict".
> - **Slide 22:** "Private Nodes" is now "Private nodes", to match slide 23.
> - **Not changed:** the empty last lines on slides 16, 18, 21 and 22. On a closer look they have no bullet, so they show nothing. Deleting them could have removed the bullet from the line above.
>
> **Talking points** (Walter Talking Points):
> - **Slide 18:** "One job" now says "transcripts", like the slide, and explains that the transcripts are the captions Ingest stored, so it lines up with slides 17 and 19.
> - **Slide 21:**
>   - Removed the HPA bullet, since it's no longer on the slide.
>   - The Flask bullet now opens "Flask is simple:", matching the slide's wording.
>   - The Gunicorn bullet now starts with the slide's "standard production WSGI server" and explains what WSGI is.
> - **Slide 22:**
>   - Now follows the slide's order: GKE, HPA, Autopilot, Private nodes.
>   - The HPA note moved here from slide 21, and the Autopilot note now says "The HPA adds pods".
>   - "Nodes are not copies of pods" stays after Autopilot.
>   - Spot pods moved to the end, marked "(not on the slide)".
> - **Slide 23:**
>   - Now matches the slide's five bullets in order.
>   - The first bullet uses the slide's new "Same Google project" wording.
>   - Added an "HPA scales pods" point.
>   - Cost moved to the end and is relabelled "Free tier credits".
>   - The "if asked" answer about YouTube is unchanged.
>
> The talking points still have nothing for slides 13–15, the Front End rationale and cloud slides, if you want those added too.

### Prompt 20

> add talking points for slides 13-15

**Claude:**

> I added talking points for slides 13–15 to Walter Talking Points, between the slide 12 notes and slide 16. The doc link stays the same, and I read it back to check the headings, bullets and bold. The facts come from the frontend Dockerfile, the nginx config, the Cloud Run Terraform module and ADR 0001.
>
> - **Slide 13, Implementation Rationale:** one bullet per item on the slide, in the slide's order:
>   - **React:** why we use it.
>   - **TypeScript:** what "contract between frontend and API" means in practice.
>   - **Vite:** what it does locally and for production.
>   - **nginx:** sends the files, makes page links like /courses/3 work on reload, and adds the security headers.
>   - **"That's it":** the front end has no server-side code.
>   - **Docker:** pinned versions, and Cloud Run needs a container anyway.
>   - **If asked:** an answer about the two-stage image.
> - **Slide 14, Cloud Implementation:** Cloud Run, then the slide's three-step process:
>   - **HTTPS:** Cloud Run handles it, so nginx only speaks plain HTTP on port 8080.
>   - **Spinning up:** zero instances when idle, with a short wait for the first visitor after that, and at most 2 instances (1 CPU and 256 MB each).
>   - **nginx serving:** index.html is never cached, so new releases show up on the next page load, while the bundled files are cached for a year.
> - **Slide 15, Cloud Rationale:**
>   - **Static Web Apps:** why it would have been simpler, and the region mismatch that blocked it (our subscription allows five regions, and Static Web Apps is offered in five others).
>   - **Cloud Run:** the course lists it as a front-end host, it reuses the API pipeline, and it scales to zero.
>   - **If asked:** why not Blob Storage, nginx on GKE or Firebase.
>
> There's some overlap now: the slide 12 notes already have a "Why Cloud Run" subsection, plus the "Deploys" and "Trade-off" paragraphs, which cover the same ground as slide 15. Want me to remove that subsection from slide 12, or move the Deploys note to slide 14?

### Prompt 21

> yes

**Claude:**

> I removed the overlap between the slide 12, 14 and 15 notes in Walter Talking Points. The doc link stays the same, and I read it back to check the result.
>
> - **Slide 12:** now ends at "After the browser loads the files… nginx is no longer involved." I removed the "Why Cloud Run" subsection and the Trade-off paragraph, because slide 15 covers both.
> - **Slide 14:** the Deploys note is now the last bullet, after "nginx serves the request". Its wording is unchanged and "Deploys:" is still bold.
> - **Slide 15:** the Trade-off paragraph had one detail slide 15 lacked, that Static Web Apps serves files from many locations. I added it to the first bullet, which now says Static Web Apps "hosts the files directly, with no nginx or Docker, serves them from many locations, and has built-in GitHub deploys."
>
> Each point about Cloud Run and Static Web Apps now appears once, under the slide it belongs to.
