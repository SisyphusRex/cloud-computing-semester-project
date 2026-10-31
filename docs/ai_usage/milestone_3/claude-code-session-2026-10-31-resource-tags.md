# AI usage log: Claude Code session, 2026-10-31 (resource tags)

| | |
|---|---|
| Tool | Claude Code (VS Code extension), model Claude Opus 5.5 |
| User | Theodore Podewil |
| Date | 2026-10-31 |
| Branch | `twp__resource_tags`; rebased and merged through `development` to `main` by the user |
| Commits produced | `8f3a367`, `0fe977b`, plus the commits adding this log |
| Release | `prod-2026-10-31.4` |
| Outcome | Every cloud resource that can carry labels or tags now has `app`, `environment`, `managed-by` and `component`, in both clouds, with no resource replaced or destroyed. The scheme, and the resources that can't be labelled, are in [dashboard-links.md](../../monitoring/dashboard-links.md) |

Each entry gives the prompt exactly as typed, then a summary of what Claude did in response. Where a prompt was terminal output pasted in, the entry describes the output instead of copying it.

---

## 1. Plan the tags

> come up with a plan to add tags to our cloud resources so they are human readable in the web dashboard

Working in plan mode, Claude read the Terraform in `envs/prod`, `bootstrap` and every module, and found that nothing set labels or tags. It then dumped the schemas of the pinned providers (google 8.7, azurerm 5.10, azapi 2.13) to see what each resource supports, rather than rely on memory.

That changed the design:

- The Google provider's `default_labels` looked like the simple answer, but it doesn't reach Cloud SQL or alert policies, and `azurerm` has no default tags at all. The plan used an explicit `labels` or `tags` variable instead.
- The VPC, subnet, router, NAT and service accounts can't take labels, so they would be explained in a docs table.
- GCP label values can't contain spaces, so the plain-English text went in an Azure `purpose` tag and in descriptions on Cloud Run and Artifact Registry.

Renaming was ruled out because it replaces resources, and scripts and CI use the names.

Two web searches left two questions open, and Claude said so. It couldn't confirm whether changing cluster labels rolls GKE Autopilot nodes, or whether a `description` on the cluster, VPC or global address forces replacement. It left those descriptions out, and set a stop condition: both Terraform plans must show `0 to add, 0 to destroy`.

The user approved the plan.

## 2. Implementation

Claude added the labels across the modules and both Terraform roots, a `labels` run in `wiring.tftest.hcl`, the bucket step in `bootstrap.md`, and the docs. It also fixed two stale entries in `dashboard-links.md`. `terraform fmt`, `validate` and all 6 tests passed.

Read-only plans against the real state came next. `bootstrap` showed 5 in-place updates, but `envs/prod` showed `1 to destroy`, which failed the stop condition: the backup failure alert. Claude traced this to the local `terraform.tfvars`, which doesn't set `alert_notification_channel`, a value CI passes from a repository variable. With CI's value the plan became `0 to add, 10 to change, 0 to destroy`. The attribute-level diffs showed only labels, tags and the two new descriptions. Claude noted the remaining hazard: a hand-run apply without that variable would delete the alert.

## 3. Commits

> go head and make the commits.  I'll handle pushing and merging.

Claude made two commits, one for Terraform and one for docs, and pushed nothing.

## 4. Deploy

> i've approved the deploy.

Claude found the release in progress, recorded the current nodes and frontend revision as a baseline, and waited for it to finish. The release succeeded, with `0 added, 10 changed, 0 destroyed`.

Checks after the release:

- The labels and descriptions were present on the resources that `envs/prod` manages.
- The same 2 nodes were running, so the GKE label change didn't roll them. That settled the first open question for this cluster.
- Cloud SQL was still `ALWAYS/RUNNABLE`.
- A second plan showed no changes.
- The frontend returned `200`, and the API the expected `401`.

Claude also corrected its own plan. `scripts/smoke-test.sh` only works on a local stack with dev auth, so it can't test production. The release's load balancer check stood in for it.

## 5. Bootstrap apply

The user pasted the Terraform prompt from `terraform apply` in `bootstrap`, showing `0 to add, 5 to change, 0 to destroy`.

Claude said to type `yes`, because the count matched the earlier plan, and listed which 5 resources to expect. It couldn't see the diff above the prompt, so it told the user what would mean answering `no` instead.

## 6. Backup check

The user pasted the output of `make cloud-backup`, which reported `backup_succeeded`.

Claude confirmed that all three resource groups, both identities and the storage account showed their tags, and that a second `bootstrap` plan showed no changes. The state bucket still had no labels, so it gave the command again.

## 7. State bucket

The user pasted the output of the `gcloud storage buckets update` command. Claude read the labels back from the bucket and confirmed they were set, which finished the rollout.

## 8. This log

> can you add my prompts and your responses to a file in docs/ai_usage/milestone_3 ?

Claude wrote this file in the format of the earlier logs.
