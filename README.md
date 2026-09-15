# DDIA Labs

Hands-on experiments from the **Designing Data-Intensive Applications** book club
(craft and code club). Each experiment lives in its own directory as a small,
self-contained app — source code, docs, and its own deployment notes.

Live at **<https://ddia.artr.com.br>** (landing page linking each experiment).

## Experiments

| Experiment | Dir | What it does | URL |
|---|---|---|---|
| [Avro Lab](avro-lab/README.md) | `avro-lab/` | Rails app benchmarking Avro vs JSON for the same payload: server-side encoding (Apache `avro` gem), browser-side decoding (Apache `avro-js`), encode/download/decode timeline per run | <https://ddia.artr.com.br/avro> |

## Conventions

- One experiment per directory, fully self-contained (own Gemfile, Dockerfile, tests).
- Rails experiments follow the `rails-dev` skill shipped inside the experiment's
  `.agents/skills/` (models are nouns, thin CRUD controllers, Minitest).
- Deploys: the repo's GitHub Actions build an arm64 OCI image, push it to OCIR,
  and bump the image tag in `artieeez/artr-gitops` (staging namespace); Argo CD
  syncs to the cluster. See `.github/workflows/build-push-ocir.yaml`.
- Agents do not push to `artr-gitops` (its AGENTS.md forbids it): prepare the
  manifests and suggest a commit instead.
