# Project 2: Container Image Scanning and Promotion Pipeline

Estimated time: 4–5 hours  
Difficulty: Intermediate

## What we are building

A GitHub Actions pipeline that builds a container image, scans it for vulnerabilities using Trivy, generates an SBOM, and on a clean scan promotes the image from a staging registry to a production registry in Azure Container Registry with no human intervention.

## Business problem

A container image is not a static artifact. It is built on a base image that may have been published weeks or months ago, contains packages with known CVEs, and gets pulled and deployed by engineers who assume someone has already checked it.

This project closes that gap. Every image is scanned before it can be promoted to production. If critical/high vulnerabilities are found, the pipeline fails and the image never reaches the production registry. If the scan is clean, the image is promoted and an SBOM is generated and stored alongside it so there is a record of what went into the image.

This demonstrates software supply chain security in practice.

## What gets built

```text
GitHub Repository
├── .github/workflows/container-pipeline.yml
├── app/
│   └── app.py
├── Dockerfile
├── requirements.txt
└── .trivyignore

Azure Container Registry
├── acrstaging<yourname>    # staging; every build lands here first
└── acrprod<yourname>       # production; only clean images are promoted here

GitHub Actions Pipeline
├── Build → push to staging ACR
├── Trivy scan → fail on HIGH/CRITICAL CVEs
├── SBOM generation → upload artifacts
└── Promote → copy scanned image digest to production ACR
```

## Trivy

Trivy is an open-source vulnerability scanner maintained by Aqua Security. It scans container images, filesystems, Git repositories, and IaC files for known CVEs, misconfigurations, and secrets.

In this project, Trivy scans the staged container image. It reports CVE ID, severity, affected package, installed version, fixed version when available, and whether a fix exists.

Trivy is not Azure infrastructure. It runs inside GitHub Actions on a GitHub-hosted runner.

## SBOM

An SBOM, or Software Bill of Materials, is an inventory of every component in a software artifact: packages, libraries, versions, and metadata.

This project generates two SBOM formats:

- CycloneDX
- SPDX JSON

The SBOM artifacts are uploaded to GitHub Actions for every build.

## Prerequisites

- Active Azure subscription
- GitHub repository
- Docker installed locally for optional local testing
- Azure CLI installed locally
- Terraform installed locally
- GitHub CLI authenticated for repo/secrets automation

## Part 1 — Azure infrastructure with Terraform

Terraform provisions:

- one Azure resource group
- one staging Azure Container Registry
- one production Azure Container Registry
- one staging service principal
- one production service principal
- role assignments for least-privilege ACR access

### Variables

```hcl
variable "yourname" {
  description = "Lowercase suffix for globally unique Azure resource names."
  type        = string
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "tags" {
  type = map(string)
  default = {
    project    = "container-pipeline"
    managed_by = "terraform"
  }
}
```

Current repo adds cost/lab guardrail variables:

- `expires_on`
- `budget_email`
- `monthly_budget_amount`
- `budget_start_date`

### Resource group

```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-container-pipeline-${var.yourname}"
  location = var.location
  tags     = local.lab_tags
}
```

### Staging ACR

The staging registry receives every build before scanning. Admin access is disabled; access is via service principal only.

```hcl
resource "azurerm_container_registry" "staging" {
  name                = "acrstaging${var.yourname}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.lab_tags
}
```

Current repo uses a small reusable ACR module instead of duplicating the resource block.

### Production ACR

The production registry only receives images that passed the scan gate. It is separate from staging so the boundary is enforced at the infrastructure level.

```hcl
resource "azurerm_container_registry" "prod" {
  name                = "acrprod${var.yourname}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.lab_tags
}
```

### Staging service principal

The staging service principal is used by the build, scan, and SBOM jobs.

Required permissions:

- `AcrPush` on staging ACR
- `AcrPull` on staging ACR

### Production service principal

The production service principal is used only by the promote job.

Required permissions:

- `AcrPush` on production ACR
- `AcrPull` on staging ACR, so `az acr import` can read the scanned image

### Outputs

Terraform outputs values for GitHub Actions secrets:

```text
staging_acr_name
prod_acr_name
staging_client_id
staging_client_secret
prod_client_id
prod_client_secret
tenant_id
subscription_id
```

Sensitive outputs must be read with `terraform output -raw <name>` and must not be committed.

## Part 2 — Application and Dockerfile

The demo application is a minimal Flask service.

Expected app endpoints:

```text
GET /
GET /version
```

Dockerfile security expectations:

- minimal Python base image
- pinned dependencies
- no root runtime user
- only required files copied into image
- health check included
- OCI labels included

Current repo runs the app with Gunicorn instead of `python app.py`, which is a better production-like default.

## Part 3 — GitHub Actions pipeline

Workflow file:

```text
.github/workflows/container-pipeline.yml
```

### Trigger

The workflow runs on:

- push to `main` when app, Dockerfile, requirements, or workflow changes
- pull requests to `main`
- manual `workflow_dispatch`

### Job 1 — Build and push to staging

The build job:

1. checks out the repo
2. logs into Azure with the staging service principal
3. authenticates Docker to staging ACR
4. builds the Docker image
5. pushes two tags to staging:
   - `${GITHUB_SHA}`
   - `staging-latest`
6. outputs the pushed image digest

Current repo promotes by digest, not by mutable tag, so the exact scanned image is what reaches production.

### Job 2 — Vulnerability scan with Trivy

The scan job:

1. logs into Azure with the staging service principal
2. authenticates Docker to staging ACR
3. runs Trivy against the staged image digest
4. fails on HIGH/CRITICAL vulnerabilities
5. saves a JSON report
6. uploads the report as a GitHub Actions artifact

Important fields:

```yaml
exit-code: "1"
ignore-unfixed: true
severity: CRITICAL,HIGH
trivyignores: .trivyignore
```

### Job 3 — SBOM generation

The SBOM job:

1. logs into Azure with the staging service principal
2. authenticates Docker to staging ACR
3. generates CycloneDX SBOM
4. generates SPDX JSON SBOM
5. uploads both as GitHub Actions artifacts

The SBOM job runs after build and does not depend on scan success.

### Job 4 — Promote to production

The promote job:

1. runs only for push events on `main`
2. requires build, scan, and SBOM jobs to pass
3. logs into Azure with the production service principal
4. imports the scanned image digest into production ACR
5. tags it as:
   - `${GITHUB_SHA}`
   - `latest`
6. prints production ACR tags

## .trivyignore

File:

```text
.trivyignore
```

Purpose:

- formal accepted-risk/suppression workflow
- one CVE per line
- each entry should include a reason and review date

For the lab, keep it mostly empty unless a reviewed exception is required.

## GitHub secrets

Add these secrets after Terraform apply:

| Secret | Source |
|---|---|
| `STAGING_ACR_NAME` | `terraform output -raw staging_acr_name` |
| `PROD_ACR_NAME` | `terraform output -raw prod_acr_name` |
| `STAGING_CLIENT_ID` | `terraform output -raw staging_client_id` |
| `STAGING_CLIENT_SECRET` | `terraform output -raw staging_client_secret` |
| `PROD_CLIENT_ID` | `terraform output -raw prod_client_id` |
| `PROD_CLIENT_SECRET` | `terraform output -raw prod_client_secret` |
| `AZURE_TENANT_ID` | `terraform output -raw tenant_id` |
| `AZURE_SUBSCRIPTION_ID` | `terraform output -raw subscription_id` |

## Verification

### Trigger the pipeline

Push to `main` or run the workflow manually from GitHub Actions.

A successful run should show:

```text
Build → Scan + SBOM → Promote
```

### Verify ACR tags

Use the helper script:

```bash
./scripts/verify-registries.sh
```

Expected staging tags:

```text
demo-app:<GITHUB_SHA>
demo-app:staging-latest
```

Expected production tags:

```text
demo-app:<GITHUB_SHA>
demo-app:latest
```

## Verification checklist

- [ ] Both ACR instances exist in Azure Portal
- [ ] GitHub Actions pipeline runs on push to `main`
- [ ] Build job pushes image to staging ACR with SHA tag
- [ ] Trivy scan result artifact is uploaded
- [ ] CycloneDX SBOM artifact is uploaded
- [ ] SPDX SBOM artifact is uploaded
- [ ] Promote job copies the scanned digest to production ACR
- [ ] Production ACR contains SHA and `latest` tags
- [ ] Pipeline fails if a critically vulnerable base image is introduced

## Troubleshooting

| Error | Likely cause | Resolution |
|---|---|---|
| `unauthorized: authentication required` on ACR push | service principal secret wrong or expired | regenerate SP secret and update GitHub secret |
| Trivy exits 0 despite vulnerabilities | missing `exit-code: "1"` | confirm workflow has `exit-code: "1"` |
| Promote runs after scan failure | dependency misconfigured | confirm promote job needs scan/SBOM/build |
| `az acr import` fails | production SP lacks pull on staging | confirm production SP has `AcrPull` on staging ACR |
| image promoted by tag drift | mutable tag used for promotion | promote by digest, as current repo does |

## Teardown

Do not destroy until screenshots/evidence are collected and the user explicitly approves teardown.

When approved:

```bash
./scripts/destroy-lab.sh
```

Verify deletion:

```bash
az group exists --name "rg-container-pipeline-<yourname>"
# expected: false
```

## Interview talking points

Lead with:

> I built a container image pipeline that enforces a scan gate before any image can reach production. Staging and production are separate ACR registries. Trivy scans every build and fails the pipeline on high/critical CVEs. An SBOM in CycloneDX and SPDX formats is generated and stored for every build. Promotion happens by digest so production receives the exact image that was scanned.

Be ready to explain:

- why staging and production registries are separate
- what an SBOM is and why enterprises require it
- what `az acr import` does compared with rebuilding
- why digest promotion prevents tag drift
- what `.trivyignore` represents as a formal exception process
- why ACR admin users are disabled
- why service principals are scoped separately
