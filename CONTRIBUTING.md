# Contributing

Thank you for your interest in contributing! This document covers how to submit changes.

## Workflow

1. **Fork** the repository
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feat/my-feature
   ```
3. **Make your changes** and commit following the guidelines below
4. **Push** to your fork and open a **Pull Request** against `main`

## Branch Naming

| Prefix | Use case |
|--------|----------|
| `feat/` | New feature or application |
| `fix/` | Bug fix |
| `docs/` | Documentation only |
| `chore/` | Maintenance, dependency updates |

## Commit Guidelines

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>
```

**Types:** `feat`, `fix`, `docs`, `chore`, `refactor`

**Examples:**
```
feat(apps): add prometheus stack
fix(vault): correct auto-unseal configuration
docs(readme): update quick start steps
chore(deps): update argocd chart to 9.6.0
```

## Scope

Contributions are welcome for:

- Bug fixes and improvements
- Documentation
- Security issues
- New applications — as long as they fit the free tier constraints, follow the existing architecture (Vault, ExternalSecret, Istio, cert-manager), and add value to the cluster infrastructure

If unsure whether your idea fits, open an issue first to discuss it.

## Guidelines

- **No secrets** — never commit credentials, tokens or keys
- **Keep PRs focused** — one feature or fix per PR
- **Update docs** — if your change affects setup or configuration, update the relevant README

## Free Tier Constraints

This cluster runs on OCI Always Free tier (4 oCPU / 24GB RAM / 2 nodes). Keep resource usage in mind when adding new applications.
