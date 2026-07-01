# Project Notes

Detailed technical outline: [`docs/project-plan.md`](docs/project-plan.md).

## Implementation plan

1. Create GitHub repo and push project code.
2. Run Terraform plan.
3. On explicit approval, run Terraform apply.
4. Add Terraform outputs as GitHub Actions secrets.
5. Run GitHub Actions pipeline.
6. Verify staging ACR has `demo-app:${GITHUB_SHA}` and `demo-app:staging-latest`.
7. Verify Trivy JSON, CycloneDX, and SPDX artifacts exist in GitHub Actions.
8. Verify production ACR has the promoted digest tagged as `${GITHUB_SHA}` and `latest`.
9. Leave Azure resources running until screenshots/evidence are collected.
10. Destroy resources only after explicit teardown approval.

## Commands I ran

```bash
terraform fmt -check -recursive
terraform validate
```

## Problems encountered

- Azure CLI auth initially landed on an account with no subscription; fixed by logging into the subscription-bearing account.
- GitHub CLI was initially missing; installed/authenticated `gh` and created the public GitHub repo.
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
