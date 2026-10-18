# ADR 0001: Host the frontend on Cloud Run instead of Azure Static Web Apps

- **Status:** Accepted
- **Date:** 2026-10-18
- **Changes:** the frontend hosting in the [Milestone 1 proposal](../milestones/m1_project_proposal/CS6030_F26_ProjectProposal_LectureIndexer.pdf)

## Context

The proposal put the React frontend on **Azure Static Web Apps** and everything else except backups on Google Cloud. When we first applied the infrastructure, Azure refused to create resources in `eastus2`:

```
RequestDisallowedByAzure: Resource 'id-li-github' was disallowed by Azure: This policy
maintains a set of best available regions where your subscription can deploy resources.
```

Our **Azure for Students** subscription has a policy, `sys.regionrestriction` ("Allowed resource deployment regions"), that allows only five regions. Static Web Apps is offered in five different ones, with no overlap:

| Regions the subscription allows | Regions Static Web Apps is offered in |
|---|---|
| Canada Central, Mexico Central, North Central US, France Central, Sweden Central | Central US, East US 2, West US 2, West Europe, East Asia |

So a Static Web App can't be created on this subscription in any region. To check:

```sh
az policy assignment show -n sys.regionrestriction --query parameters
az provider show -n Microsoft.Web --query "resourceTypes[?resourceType=='staticSites'].locations"
```

The other Azure resources (the CI identities, and the backup storage in step 5) work in an allowed region, so they move to **North Central US**.

## Decision

Serve the frontend from **Google Cloud Run**, which the [course requirements](../milestones/m1_project_proposal/project-requirements.md) list as a frontend host alongside Static Web Apps.

- The built app is served by nginx in a container (`frontend/Dockerfile`), with the security headers that `staticwebapp.config.json` used to set, including the Content-Security-Policy.
- Terraform creates the Cloud Run service `li-frontend` (public, 0–2 instances); the `frontend-deploy.yml` workflow builds the image and deploys each revision.
- The app keeps calling the API cross-origin, now from its `https://li-frontend-….run.app` URL. Nothing changes in the API, the database, or the GKE setup.

## Alternatives considered

| Option | Why not |
|---|---|
| Azure Blob Storage static website | Stays on Azure, but can't send response headers, so no CSP header |
| Ask Azure support to allow a Static Web Apps region | Unknown timing and outcome; deployment was blocked until then |
| nginx behind the existing GKE load balancer | Same origin as the API, but it adds a pod that always runs, and the frontend would go down whenever the cluster is paused |
| Firebase Hosting | Works too, but adds a separate tool and CLI; Cloud Run reuses the Docker, Artifact Registry and deploy identity we already have |

## Consequences

- **Cloud split:** Google Cloud now hosts the frontend too; Azure holds the nightly encrypted backups and the CI identities that manage them. The project still uses two clouds, but Azure's share is smaller than proposed. The final architecture talk should explain why.
- **Cost:** about $0. Cloud Run scales to zero, and our traffic is far inside its free tier. It needs no pause step.
- **Security:** the CSP is now set by nginx; its `connect-src` names the API origin at build time. The Static Web Apps deploy token, which Terraform stored in state, no longer exists. The M3 security review should cover both.
- **Sign-in:** the Google OAuth client's authorized JavaScript origin is the Cloud Run URL (Terraform output `frontend_url`) instead of the Static Web Apps URL.
- **Deploys:** `gcloud run deploy`, using the same keyless `github-deploy` identity as the services, with deploy rights on this one service only.
