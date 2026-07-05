# Deployment Session Notes & Speaking Points

*July 5, 2026 — first successful end-to-end run of the container pipeline.*

## The one-liner

> "I built a CI/CD pipeline where container images are built into a staging
> registry, scanned with Trivy, inventoried with SBOMs, and only promoted to
> the production registry — by digest — if the scan gate passes. Terraform
> provisions everything with least-privilege service principals."

---

## Starting state

- Terraform code existed but had **never been applied** (state file was empty).
- The GitHub Actions workflow was pushed, but **zero repository secrets** were
  configured — an earlier run had failed instantly at `az login`.

## Step 1 — Provision the infrastructure (`terraform apply`)

Created 13 resources:

| What | Why |
|---|---|
| Resource group `rg-container-pipeline-brian36502` | Blast-radius container; one `terraform destroy` removes everything |
| 2× ACR, Basic SKU (`acrstagingbrian36502`, `acrprodbrian36502`) | **Staging = quarantine zone.** Untrusted builds land here; prod only ever receives scanned images |
| 2× Entra ID service principals + client secrets | Robot identities for CI — one per environment, so staging creds can never touch prod |
| 5× RBAC role assignments | Staging SP: AcrPush/AcrPull on staging only. Prod SP: AcrPush on prod, AcrPull on staging |

Cost: ~$0.17/day per Basic registry — everything else is free.

## Step 2 — Wire CI to Azure (GitHub secrets)

Fed 8 Terraform outputs into GitHub Actions secrets with `gh secret set`:
tenant + subscription IDs, both ACR names, both SP client IDs + secrets.

**Speaking point:** credentials never appear in code or logs. Terraform marks
them `sensitive`; GitHub masks them in run output.

## Step 3 — First run: two failures, two fixes

Build succeeded (image landed in staging), but scan and SBOM failed.

### Fix 1: dead action version

`aquasecurity/trivy-action@0.24.0` no longer resolves — the project moved to
`v`-prefixed tags. Bumped to `@v0.36.0`.

**Lesson:** pinned action versions are supply-chain hygiene, but pins rot;
tags can be renamed or deleted upstream.

### Fix 2: GitHub silently drops job outputs containing secrets

The build job exported the full image reference
(`$ACR_NAME.azurecr.io/demo-app@sha256:...`) as a job output. Because
`ACR_NAME` came from a secret, **GitHub refused to pass the output** (security
feature — outputs are visible in logs), so downstream jobs received an empty
string. The annotation was easy to miss: *"Skip output 'image-ref' since it
may contain secret."*

**Fix:** the build job outputs only the **digest** (a sha256 hash — not
secret); each downstream job rebuilds the full reference from
`secrets.STAGING_ACR_NAME` + the digest.

**Lesson:** never embed secret values in job outputs; pass non-sensitive
identifiers and reconstruct.

## Step 4 — Second run: promote fails with "registry not found"

`az acr import` failed claiming the prod registry didn't exist — even though
it did. Root cause: **data plane vs management plane**.

- `AcrPush`/`AcrPull` are *data-plane* roles — they authorize `docker
  push/pull` against the registry endpoint.
- `az acr import` is a *management-plane* (ARM) API call. It needs
  `Microsoft.ContainerRegistry/registries/read` and
  `.../importImage/action`. Without ARM read, Azure won't even confirm the
  resource exists — hence the misleading "not found."

**Fix (least privilege, not Contributor):** a Terraform custom role
(`azurerm_role_definition`) with exactly those two permissions, assigned to
the prod SP on the prod registry, plus built-in `Reader` on staging so the
import can resolve the source image.

**Lesson / talking point:** this is the strongest interview story of the
session — explaining the data-plane/management-plane split in Azure RBAC, and
choosing a two-permission custom role over granting Contributor.

## Step 5 — Green run, verified on Azure

Re-ran the failed job after ~2 min of RBAC propagation. All four jobs passed:

```
Build → push to staging      ✓
Trivy scan (CRITICAL/HIGH)   ✓  (clean — gate would fail the run otherwise)
SBOM (CycloneDX + SPDX)      ✓  (uploaded as artifacts)
Promote to prod by digest    ✓
```

Verified with `az acr repository show-tags`: staging holds the commit-SHA tag
+ `staging-latest`; prod holds the **same digest** tagged with the SHA +
`latest`.

## Why promotion is by digest (key design point)

A tag (`staging-latest`) is a movable pointer — it can be repointed after the
scan. A **digest** is a content hash of the exact bytes Trivy scanned. Using
`az acr import --source ...@sha256:...` means production provably receives
the scanned artifact, not "whatever the tag points at now." The copy is also
server-side — the image never transits the CI runner on its way to prod.

## The security gate mechanics

- Trivy runs with `exit-code: "1"` on CRITICAL/HIGH, `ignore-unfixed: true`.
- The promote job declares `needs: [build, scan, sbom]` — a failed scan
  **structurally blocks** promotion; there's no override path in the workflow.
- `.trivyignore` is the documented risk-acceptance channel (one CVE per line
  with justification and review date).

## Demo checklist

1. Architecture diagram (`assets/diagrams/`).
2. Code tour: Dockerfile (non-root, healthcheck), workflow (the gate),
   Terraform (registries, SPs, custom role).
3. Push a change to `app/` → watch the job graph go green.
4. Azure portal: both registries' `demo-app` repos (matching digests), IAM
   blade showing scoped roles.
5. Prove the artifact: `docker run --rm -p 8080:8080
   acrprodbrian36502.azurecr.io/demo-app:latest` → `curl localhost:8080`.
6. Teardown on camera: `./scripts/destroy-lab.sh`.

## Teardown

```bash
./scripts/destroy-lab.sh                                        # terraform destroy
gh secret list | awk '{print $1}' | xargs -n1 gh secret delete  # remove dead creds
az group list -o table                                          # confirm empty
```
