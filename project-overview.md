Project 2: Container Image Scanning and Promotion Pipeline

Estimated Time: 4–5 hours
Difficulty: Intermediate
What you will build: A GitHub Actions pipeline that builds a container image, scans it for vulnerabilities using Trivy, generates an SBOM, and on a clean scan promotes the image from a staging registry to a production registry in Azure Container Registry — with no human intervention required.




The Business Problem You Are Solving

A container image is not a static artifact. It is built on a base image that was published weeks or months ago, contains packages with known CVEs, and gets pulled and deployed by engineers who assume someone has already checked it. In most organizations, nobody has.

This project builds the pipeline that closes that gap. Every image that gets built is automatically scanned before it can be promoted to production. If critical vulnerabilities are found, the pipeline afails and the image never reaches the production registry. If the scan is clean, the image is promoted and a bill of materials — an SBOM — is generated and stored alongside it so there is a complete record of what went into the image.

This is what "software supply chain security" means in practice. The job description calls it out by name because most engineers have heard of it but few have implemented it.




What Gets Built

GitHub Repository
└── .github/workflows/container-pipeline.yml
└── app/
    ├── Dockerfile
    └── app.py               ← sample Flask app
└── .trivyignore             ← accepted risk suppressions
 
Azure Container Registry (two registries)
├── acrstagin[yourname]      ← staging — all builds land here
└── acrprod[yourname]        ← production — only clean scans promoted here
 
GitHub Actions Pipeline
├── Build → push to staging ACR
├── Trivy scan → fail on CRITICAL CVEs
├── SBOM generation → upload as artifact
└── Promote → copy image to production ACR






What Trivy Is

Trivy is an open source vulnerability scanner maintained by Aqua Security. It scans container images, filesystems, Git repositories, and IaC files for known CVEs, misconfigurations, and secrets. It is one of the most widely used container scanning tools in the industry and integrates natively with GitHub Actions.

When Trivy scans a container image it checks every package installed in the image against the National Vulnerability Database (NVD) and OS-specific advisories. It reports the CVE ID, severity level, which package is affected, what version fixes it, and whether a fix is available.




What an SBOM Is

An SBOM (Software Bill of Materials) is a complete inventory of every component that went into a piece of software — every package, library, and dependency, with its version and license. It is the equivalent of a food nutrition label, but for software.

The US government now requires SBOMs for software sold to federal agencies. Most large enterprises are beginning to require them from vendors. Generating one as part of your pipeline demonstrates that you understand supply chain security at a practical level, not just conceptually.

Trivy can generate SBOMs in CycloneDX and SPDX formats, both of which are industry standards.




Prerequisites

An active Azure subscription
A GitHub repository for this project
Docker installed locally (for testing)
Azure CLI installed locally




Part 1 — Azure Infrastructure Setup with Terraform

All Azure infrastructure is provisioned with Terraform — both ACR instances, both service principals, and all role assignments. Create an infra/ folder in your repository with the following files.

Step 1 — Write infra/variables.tf

variable "yourname" {
  description = "Your name, lowercase, no spaces."
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



Step 2 — Write infra/terraform.tfvars

yourname = "charles"
location = "eastus"



Step 3 — Write infra/main.tf




Provider and data sources

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}
 
provider "azurerm" {
  features {}
}
 
provider "azuread" {}
 
data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}






Resource group

resource "azurerm_resource_group" "main" {
  name     = "rg-container-pipeline-${var.yourname}"
  location = var.location
  tags     = var.tags
}






Staging ACR

The staging registry is where every build lands first, regardless of scan results. admin_enabled = false is enforced on both registries — access is via service principal only, never via the admin password.

resource "azurerm_container_registry" "staging" {
  name                = "acrstaging${var.yourname}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}






Production ACR

The production registry only receives images that have passed the scan gate. It is a separate resource so the separation is enforced at the infrastructure level — staging credentials cannot write to production regardless of what the pipeline does.

resource "azurerm_container_registry" "prod" {
  name                = "acrprod${var.yourname}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}






Service principal — staging push

This SP has AcrPush on the staging registry only. It is the identity used by the build job in GitHub Actions.

resource "azuread_application" "staging" {
  display_name = "sp-acr-staging-${var.yourname}"
  owners       = [data.azuread_client_config.current.object_id]
}
 
resource "azuread_service_principal" "staging" {
  application_id               = azuread_application.staging.application_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}
 
resource "azuread_service_principal_password" "staging" {
  service_principal_id = azuread_service_principal.staging.object_id
  rotate_when_changed  = { rotation_id = "v1" }
}
 
resource "azurerm_role_assignment" "staging_push" {
  scope                = azurerm_container_registry.staging.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.staging.object_id
}
 
# Staging SP also needs AcrPull on staging so the scan job can pull the image back
resource "azurerm_role_assignment" "staging_pull" {
  scope                = azurerm_container_registry.staging.id
  role_definition_name = "AcrPull"
  principal_id         = azuread_service_principal.staging.object_id
}






Service principal — production push

This SP has AcrPush on the production registry only. It is used exclusively by the promote job. Because it has no access to staging, it cannot be used to bypass the scan gate.

resource "azuread_application" "prod" {
  display_name = "sp-acr-prod-${var.yourname}"
  owners       = [data.azuread_client_config.current.object_id]
}
 
resource "azuread_service_principal" "prod" {
  application_id               = azuread_application.prod.application_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}
 
resource "azuread_service_principal_password" "prod" {
  service_principal_id = azuread_service_principal.prod.object_id
  rotate_when_changed  = { rotation_id = "v1" }
}
 
resource "azurerm_role_assignment" "prod_push" {
  scope                = azurerm_container_registry.prod.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.prod.object_id
}
 
# Prod SP needs AcrPull on staging so az acr import can read from it
resource "azurerm_role_assignment" "prod_staging_pull" {
  scope                = azurerm_container_registry.staging.id
  role_definition_name = "AcrPull"
  principal_id         = azuread_service_principal.prod.object_id
}






Step 4 — Write infra/outputs.tf

output "staging_acr_name" {
  value = azurerm_container_registry.staging.name
}
 
output "prod_acr_name" {
  value = azurerm_container_registry.prod.name
}
 
output "staging_client_id" {
  value     = azuread_application.staging.application_id
  sensitive = true
}
 
output "staging_client_secret" {
  value     = azuread_service_principal_password.staging.value
  sensitive = true
}
 
output "prod_client_id" {
  value     = azuread_application.prod.application_id
  sensitive = true
}
 
output "prod_client_secret" {
  value     = azuread_service_principal_password.prod.value
  sensitive = true
}
 
output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}
 
output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}






Step 5 — Deploy the Infrastructure

az login
az account set --subscription "Your Subscription Name"
cd infra
terraform init
terraform plan
terraform apply



Expect 11 resources to add. After apply, retrieve your GitHub secret values:

terraform output staging_acr_name
terraform output prod_acr_name
terraform output -raw staging_client_id
terraform output -raw staging_client_secret
terraform output -raw prod_client_id
terraform output -raw prod_client_secret
terraform output -raw tenant_id
terraform output -raw subscription_id



Step 6 — Add GitHub Secrets

Add the following secrets to your repository via Settings → Secrets and variables → Actions:

Secret Name
Terraform command
STAGING_ACR_NAME
terraform output -raw staging_acr_name
PROD_ACR_NAME
terraform output -raw prod_acr_name
STAGING_CLIENT_ID
terraform output -raw staging_client_id
STAGING_CLIENT_SECRET
terraform output -raw staging_client_secret
PROD_CLIENT_ID
terraform output -raw prod_client_id
PROD_CLIENT_SECRET
terraform output -raw prod_client_secret
AZURE_TENANT_ID
terraform output -raw tenant_id
AZURE_SUBSCRIPTION_ID
terraform output -raw subscription_id






Part 2 — Application and Dockerfile

Step 3 — Write app/app.py

A minimal Flask application. The content does not matter — this is a vehicle for demonstrating the pipeline.

from flask import Flask, jsonify
 
app = Flask(__name__)
 
@app.route("/")
def health():
    return jsonify({"status": "healthy", "service": "container-pipeline-demo"})
 
@app.route("/version")
def version():
    return jsonify({"version": "1.0.0"})
 
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)



Step 4 — Write the Dockerfile

The Dockerfile follows security best practices: uses a minimal base image, runs as a non-root user, copies only what is needed, and pins the base image to a specific digest rather than a floating tag.

# Use a specific version tag — never use :latest in production images
# Pin to a digest for full reproducibility in a real pipeline
FROM python:3.12-slim
 
# Metadata labels — useful for image provenance and scanning
LABEL org.opencontainers.image.source="https://github.com/your-org/container-pipeline"
LABEL org.opencontainers.image.description="Container pipeline demo application"
 
# Set working directory
WORKDIR /app
 
# Install dependencies as a separate layer for cache efficiency
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
 
# Copy application code
COPY app/ .
 
# Create a non-root user — running as root inside a container is a CIS finding
RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup appuser
 
# Change ownership of the app directory to the non-root user
RUN chown -R appuser:appgroup /app
 
# Switch to non-root user
USER appuser
 
# Expose the application port
EXPOSE 8080
 
# Health check — used by container orchestrators to determine readiness
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/')"
 
CMD ["python", "app.py"]



Step 5 — Write requirements.txt

flask==3.0.3
gunicorn==22.0.0






Part 3 — GitHub Actions Pipeline

Step 6 — Write container-pipeline.yml

This is the complete pipeline. Each job is explained before its code.




Trigger and environment variables

name: Container Image Pipeline
 
on:
  push:
    branches: [main]
    paths:
      - 'app/**'
      - 'Dockerfile'
      - 'requirements.txt'
  pull_request:
    branches: [main]
  workflow_dispatch:
 
env:
  IMAGE_NAME: demo-app






Job 1 — Build and push to staging

This job builds the image and pushes it to the staging registry. Every build lands here regardless of scan results. The image is tagged with both the Git SHA (for traceability) and staging-latest (for easy reference).

jobs:
  build:
    name: Build and Push to Staging
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}
      image-digest: ${{ steps.build.outputs.digest }}
 
    steps:
      - name: Checkout
        uses: actions/checkout@v4
 
      - name: Login to Staging ACR
        uses: azure/login@v1
        with:
          client-id:       ${{ secrets.STAGING_CLIENT_ID }}
          client-secret:   ${{ secrets.STAGING_CLIENT_SECRET }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
 
      - name: Authenticate Docker to Staging ACR
        run: az acr login --name ${{ secrets.STAGING_ACR_NAME }}
 
      - name: Generate image metadata
        id: meta
        run: |
          echo "tags=${{ secrets.STAGING_ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:${{ github.sha }}" >> $GITHUB_OUTPUT
 
      - name: Build and push to staging
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ secrets.STAGING_ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:${{ github.sha }}
            ${{ secrets.STAGING_ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:staging-latest
          labels: |
            org.opencontainers.image.revision=${{ github.sha }}
            org.opencontainers.image.created=${{ github.event.repository.updated_at }}






Job 2 — Vulnerability scan with Trivy

This job scans the image that was just pushed to staging. If critical vulnerabilities with available fixes are found, the job fails and the pipeline stops — the image never reaches production.

exit-code: '1' is what causes the pipeline to fail on findings. ignore-unfixed: true means Trivy only fails on vulnerabilities where a fix is available — there is no point failing a build for a CVE with no patch yet.

  scan:
    name: Vulnerability Scan
    runs-on: ubuntu-latest
    needs: build
 
    steps:
      - name: Login to Staging ACR
        uses: azure/login@v1
        with:
          client-id:       ${{ secrets.STAGING_CLIENT_ID }}
          client-secret:   ${{ secrets.STAGING_CLIENT_SECRET }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
 
      - name: Authenticate Docker to Staging ACR
        run: az acr login --name ${{ secrets.STAGING_ACR_NAME }}
 
      - name: Run Trivy vulnerability scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ secrets.STAGING_ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:${{ github.sha }}
          format: table
          exit-code: '1'
          ignore-unfixed: true
          severity: CRITICAL,HIGH
          trivyignores: .trivyignore
 
      - name: Run Trivy scan — JSON output for artifact
        if: always()
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ secrets.STAGING_ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:${{ github.sha }}
          format: json
          output: trivy-results.json
          ignore-unfixed: true
          severity: CRITICAL,HIGH
 
      - name: Upload Trivy scan results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: trivy-results-${{ github.sha }}
          path: trivy-results.json
          retention-days: 90






Job 3 — SBOM generation

This job generates a Software Bill of Materials in CycloneDX format. It runs in parallel with the scan job since it does not depend on scan results — an SBOM is generated regardless of scan outcome because you need the inventory even for images that fail scanning.

  sbom:
    name: Generate SBOM
    runs-on: ubuntu-latest
    needs: build
 
    steps:
      - name: Login to Staging ACR
        uses: azure/login@v1
        with:
          client-id:       ${{ secrets.STAGING_CLIENT_ID }}
          client-secret:   ${{ secrets.STAGING_CLIENT_SECRET }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
 
      - name: Authenticate Docker to Staging ACR
        run: az acr login --name ${{ secrets.STAGING_ACR_NAME }}
 
      - name: Install Trivy
        run: |
          wget -qO- https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
          echo "deb https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list
          sudo apt-get update && sudo apt-get install -y trivy
 
      - name: Generate SBOM (CycloneDX format)
        run: |
          trivy image \
            --format cyclonedx \
            --output sbom-cyclonedx.json \
            ${{ secrets.STAGING_ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:${{ github.sha }}
 
      - name: Generate SBOM (SPDX format)
        run: |
          trivy image \
            --format spdx-json \
            --output sbom-spdx.json \
            ${{ secrets.STAGING_ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:${{ github.sha }}
 
      - name: Upload SBOMs
        uses: actions/upload-artifact@v4
        with:
          name: sbom-${{ github.sha }}
          path: |
            sbom-cyclonedx.json
            sbom-spdx.json
          retention-days: 365






Job 4 — Promote to production

This job only runs if the scan job passed. It copies the image from staging ACR to production ACR using az acr import, which copies the image by digest — ensuring the exact image that was scanned is what gets promoted, not a newly rebuilt version.

  promote:
    name: Promote to Production
    runs-on: ubuntu-latest
    needs: [scan, sbom]
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
 
    steps:
      - name: Login to Production ACR
        uses: azure/login@v1
        with:
          client-id:       ${{ secrets.PROD_CLIENT_ID }}
          client-secret:   ${{ secrets.PROD_CLIENT_SECRET }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
 
      - name: Promote image to production ACR
        run: |
          az acr import \
            --name ${{ secrets.PROD_ACR_NAME }} \
            --source ${{ secrets.STAGING_ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:${{ github.sha }} \
            --image ${{ env.IMAGE_NAME }}:${{ github.sha }} \
            --image ${{ env.IMAGE_NAME }}:latest \
            --force
 
      - name: Confirm production image
        run: |
          echo "Image promoted to production:"
          az acr repository show-tags \
            --name ${{ secrets.PROD_ACR_NAME }} \
            --repository ${{ env.IMAGE_NAME }} \
            --output table






Step 7 — Write .trivyignore

The .trivyignore file lists CVE IDs that are accepted risks — vulnerabilities you have reviewed and decided to accept, typically because no fix exists for your specific use case or the vulnerability is not exploitable in your environment. This is the formal documented exception process for security findings.

# .trivyignore
# Format: one CVE ID per line, with a comment explaining the accepted risk
# Each entry should be reviewed on a regular cadence
 
# Example — remove this and add real accepted risks
# CVE-2023-XXXXX  # Accepted: affects feature not used in this image, no fix available as of 2026-03



Leave the file mostly empty for the lab — its presence demonstrates you understand the suppression workflow.




Part 4 — Verification

Step 8 — Trigger the Pipeline

Push a change to the app/ directory on the main branch:

git add .
git commit -m "feat: add container pipeline"
git push origin main



Navigate to your GitHub repository → Actions tab and watch the pipeline run.

A successful run will show all four jobs completing in order: Build → Scan + SBOM (parallel) → Promote.

Step 9 — Verify Images in ACR

Mac:
# Staging
az acr repository show-tags \
  --name acrstagingcharles \
  --repository demo-app \
  --output table
 
# Production
az acr repository show-tags \
  --name acrprodcharles \
  --repository demo-app \
  --output table



Windows (PowerShell):
az acr repository show-tags `
  --name acrstagingcharles `
  --repository demo-app `
  --output table
 
az acr repository show-tags `
  --name acrprodcharles `
  --repository demo-app `
  --output table






Verification Checklist

Both ACR instances exist in the portal
GitHub Actions pipeline runs on push to main
Build job pushes image to staging ACR with SHA tag
Trivy scan results artifact uploaded to Actions run
SBOM artifacts (CycloneDX and SPDX) uploaded to Actions run
Promote job copies image to production ACR
Production ACR contains both SHA-tagged and latest-tagged image
Pipeline fails if you introduce a critically vulnerable base image




Troubleshooting

Error
Cause
Resolution
unauthorized: authentication required on ACR push
Service principal credentials expired or wrong registry
Regenerate SP and update GitHub secret
Trivy scan exits 0 despite vulnerabilities
exit-code not set to '1'
Confirm the exit-code: '1' field is present
Promote job runs even after scan failure
Job dependency misconfigured
Confirm needs: [scan, sbom] is set on the promote job
az acr import fails
Staging SP does not have AcrPull on staging registry
Add AcrPull role to the staging SP on the staging registry






Teardown

cd infra
terraform destroy



This removes both ACR instances, both service principals, all role assignments, and the resource group.




Interview Talking Points

Lead with: "I built a container image pipeline that enforces a scan gate before any image can reach production. Staging and production are separate ACR registries. Trivy scans on every build and the pipeline fails on critical CVEs with available fixes. An SBOM in both CycloneDX and SPDX formats is generated and stored for every build regardless of scan outcome."

Be ready to explain: the difference between staging and production registries and why keeping them separate matters, what an SBOM is and why enterprises are requiring them, what az acr import does vs a rebuild, and what the .trivyignore file represents as a formal exception process.


