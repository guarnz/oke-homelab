#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NS="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repository ArgoCD tracks. Defaults to this checkout's origin remote so a fork
# points at itself; override with REPO_URL=... when running from a tarball.
REPO_URL="${REPO_URL:-$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null)}"
if [[ -z "$REPO_URL" ]]; then
  echo "REPO_URL is not set and could not be derived from git. Export REPO_URL=https://github.com/<you>/<repo> and re-run." >&2
  exit 1
fi
echo "==> Using repository: $REPO_URL"

# ── point every Application source at this fork ───────────────────────────────
# ArgoCD reads from git, so the repoURL baked into the Application/ApplicationSet
# manifests must match this fork. Only rewrite `repoURL:` lines that point at a
# checkout of THIS repo (matched by its name), never upstream chart or doc links.
# Rewrite any that differ and remind the user to commit — otherwise the next sync
# reverts them.
GITOPS_DIR="$SCRIPT_DIR/../gitops"
TARGET_URL="${REPO_URL%.git}"
REPO_NAME="$(basename "$TARGET_URL")"
REPO_RE="repoURL: https://github\.com/[^/]+/${REPO_NAME}([[:space:]]|/|$)"
if grep -rlE "$REPO_RE" "$GITOPS_DIR" 2>/dev/null | grep -q .; then
  echo "==> Repointing Application sources to: $TARGET_URL"
  grep -rlE "$REPO_RE" "$GITOPS_DIR" \
    | xargs sed -ri "s#(repoURL: )https://github\.com/[^/]+/${REPO_NAME}#\1${TARGET_URL}#g"
  echo "    NOTE: Application manifests were rewritten. Commit and push them before"
  echo "          ArgoCD syncs, or the next reconcile will revert them."
fi

# ── repository credentials (private repos only) ───────────────────────────────
read -rsp "GitHub token (leave empty if repo is public): " GH_TOKEN; echo

# ── install ArgoCD via Helm ───────────────────────────────────────────────────
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || helm repo update argo
helm upgrade --install argocd argo/argo-cd \
  -n "$ARGOCD_NS" --create-namespace \
  -f "$SCRIPT_DIR/../gitops/bootstrap/argocd/values.yaml" \
  --wait

if [[ -n "$GH_TOKEN" ]]; then
  # NOTE: this creates a Kubernetes Secret directly as a bootstrap step.
  # Once Vault is running, migrate this secret to Vault and manage it via
  # External Secrets Operator instead.
  kubectl create secret generic argocd-repo-creds \
    -n "$ARGOCD_NS" \
    --from-literal=type=git \
    --from-literal=url="$REPO_URL" \
    --from-literal=password="$GH_TOKEN" \
    --from-literal=username=git \
    --dry-run=client -o yaml | \
    kubectl label --local -f - "argocd.argoproj.io/secret-type=repository" --dry-run=client -o yaml | \
    kubectl apply -f -
fi

# ── apply App of Apps and ArgoCD self-managed app ────────────────────────────
kubectl apply -f "$SCRIPT_DIR/../gitops/bootstrap/apps-of-apps.yaml"
kubectl apply -f "$SCRIPT_DIR/../gitops/bootstrap/argocd/application.yaml"

echo ""
echo "==> ArgoCD bootstrap complete!"
echo "    Initial password: $(kubectl get secret argocd-initial-admin-secret -n $ARGOCD_NS -o jsonpath='{.data.password}' | base64 -d)"
