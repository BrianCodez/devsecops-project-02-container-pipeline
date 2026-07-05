# Registry evidence — captured 2026-07-05T17:52Z, prior to lab teardown

Same digest (sha256:0031748...) present in BOTH registries — proof the
production image is byte-identical to what Trivy scanned in staging.

## Staging registry (acrstagingbrian36502)
```json
[
  {
    "digest": "sha256:003174807253758e2f59722febbd06ed7789b66803490de6f06dd6aa5ddc8d36",
    "tags": [
      "889067cb1e16ec3cda2246e332d9d44061181fa8",
      "staging-latest"
    ]
  },
  {
    "digest": "sha256:bd1dc75baeb13fa3ea79fc5aff62130f72ea1d9e4973fb8acbf3e938857d0a76",
    "tags": [
      "74084aae20710afe21b03f89516410d416afe3b1"
    ]
  }
]
```

## Production registry (acrprodbrian36502)
```json
[
  {
    "digest": "sha256:003174807253758e2f59722febbd06ed7789b66803490de6f06dd6aa5ddc8d36",
    "tags": [
      "889067cb1e16ec3cda2246e332d9d44061181fa8",
      "latest"
    ]
  }
]
```
