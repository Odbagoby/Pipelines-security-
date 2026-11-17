# Threat model

Scope: the path from a developer's commit to a running container, and the API itself.

## Assets

The API key and stored notes, the AWS account, the container image, and the integrity of the
pipeline (whoever controls the pipeline controls production).

## Trust boundaries

1. Developer workstation to GitHub repository
2. GitHub Actions runner to third-party actions and package registries
3. GitHub Actions to AWS (OIDC federation)
4. Internet to the running API

## Threats and mitigations

| # | Threat | Category (STRIDE) | Mitigation in this repo | Residual risk |
|---|---|---|---|---|
| 1 | A credential is committed to git | Information disclosure | Gitleaks on full history; `.gitignore` for env and key files; GitHub push protection | Secrets in formats the scanners do not recognise |
| 2 | A vulnerable or malicious dependency is pulled in | Tampering | Exact pins, pip-audit gate, Dependabot, SBOM for later lookup | Transitive dependencies are not hash-pinned; zero-days |
| 3 | A third-party action is compromised | Tampering, elevation of privilege | Read-only default token, per-job permissions, `persist-credentials: false`, AWS access only in the release job | Actions are pinned by tag, not SHA |
| 4 | Stolen long-lived cloud keys | Spoofing | None exist: OIDC issues short-lived credentials | A workflow change on `main` could still misuse the role |
| 5 | A pull request or fork tries to deploy | Elevation of privilege | Role trust is bound to the `production` environment; release job runs only on push to `main` | Depends on environment branch restrictions being configured |
| 6 | The pipeline role is abused for lateral movement | Elevation of privilege | Policy scoped to one ECR repo and one service; `iam:PassRole` limited to one role and one service principal | An attacker could push an image to that one repo |
| 7 | An image is replaced or tampered with in the registry | Tampering | Immutable tags, deploy by commit SHA, Cosign signature on the digest | Signature is not enforced at deploy time yet |
| 8 | Vulnerable OS packages in the image | Elevation of privilege | Slim base, multi-stage build, Grype gate, weekly scheduled re-scan, ECR scan on push | Unfixed CVEs are tolerated by design |
| 9 | Container breakout or persistence | Elevation of privilege | Non-root UID, read-only filesystem, all capabilities dropped, no shell tools added | Kernel-level vulnerabilities |
| 10 | Unauthenticated API access | Spoofing | API key on all data routes, constant-time compare, fail-closed when unconfigured, regression tests | Single shared key, no rate limiting |
| 11 | Injection or oversized input | Tampering, denial of service | Strict Pydantic models, UUID path parameters, bounded lengths, capped store | Volumetric denial of service is left to the platform |
| 12 | Missing browser-facing protections | Information disclosure | Security headers on every response, verified by tests and ZAP | ZAP is report-only for now |
| 13 | Misconfigured cloud resources | Various | Checkov gate on Terraform; encrypted, scanned, immutable ECR | Checkov only sees what is in code |
| 14 | An AI coding agent is steered by injected instructions (in an issue, a web page, a dependency, or a tampered `CLAUDE.md`) into weakening a control or leaking a secret | Tampering, elevation of privilege | Security invariants in `CLAUDE.md`; agent plugin from official sources at a pinned version with hooks off by default; agent config changes go through pull requests; the agent has no route to production because the AWS role trusts only the `production` environment and every gate still runs | Instructions to an agent are guidance, not enforcement; agent config is not yet scanned in CI |
