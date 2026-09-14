# AGENTS.md

DDIA Labs: hands-on experiments from the Designing Data-Intensive Applications
book club (craft and code club). One self-contained experiment per directory.

- Rails code follows the `rails-dev` skill in `<experiment>/.agents/skills/rails-dev`.
- Deploys: `.github/workflows/build-push-ocir.yaml` builds the arm64 image, pushes
  to OCIR, and bumps the tag in `artieeez/artr-gitops` (`apps/staging/<app>/deployment.yaml`).
- **Never push to `artieeez/artr-gitops`** — its AGENTS.md says the human commits
  and pushes. Prepare manifests and suggest a commit message instead.
- Agents do not commit or push this repo unless the human asks.