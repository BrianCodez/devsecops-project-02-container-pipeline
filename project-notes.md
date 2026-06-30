# Project Notes

## Commands I ran

```bash
terraform fmt -check -recursive
terraform validate
```

## Problems encountered

- Azure CLI is installed, but this WSL session is not logged in yet: `az account show` asks for `az login`.
- GitHub CLI is not installed in this WSL session; use the GitHub web UI for secrets unless you install/authenticate `gh`.
- Added `scripts/verify-registries.sh` to capture staging/production ACR tags after the workflow runs.
- `explorer.exe` returned exit code 1 from this shell; use Windows Explorer manually if needed.

## Decisions

- Keep ACR admin users disabled; use service principals and scoped RBAC instead.
- Promote the image by digest so production receives the exact artifact that Trivy scanned.
- Store screenshots under `images/` when evidence collection starts.

## Evidence checklist

- [ ] Terraform plan
- [ ] Terraform apply
- [ ] Azure resource group
- [ ] Staging ACR
- [ ] Production ACR
- [ ] GitHub secrets
- [ ] Workflow YAML
- [ ] Successful GitHub Actions run
- [ ] Trivy JSON artifact
- [ ] CycloneDX SBOM artifact
- [ ] SPDX SBOM artifact
- [ ] Production ACR tags
- [ ] Terraform destroy
- [ ] Resource group deleted

## Interview notes

- Two registries enforce staging/production separation at the infrastructure boundary.
- SBOMs give a durable record of what shipped.
- Digest promotion prevents tag drift between scan and production promotion.
- Do not destroy Azure resources until the user confirms screenshots/evidence are collected.
- East US Basic ACR retail meter from Azure Retail Prices API: $0.1666/day per registry; two registries are roughly $0.33/day before network/extra storage.
