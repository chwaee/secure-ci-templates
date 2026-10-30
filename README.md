# secure-ci-templates

Opinionated GitHub Actions workflows for freelance delivery. Copy a stack into a client repository, set the deploy target, and the repository has CI, security scanning, and a release path.

This is not a framework. Nothing here is imported. The workflows are files you copy.

Author: Chwaee ([chwaee](https://github.com/chwaee), hello@appliedaiconsulting.io). License: MIT.

This sits next to [HarderAWS](https://github.com/chwaee/HarderAWS), the account hardening modules, [aws-health-audit](https://github.com/chwaee/aws-health-audit), the read-only account audit, and [tf-cost-preview](https://github.com/chwaee/tf-cost-preview), the pre-apply cost estimator. HarderAWS builds the account. These workflows build and ship the application. aws-health-audit checks what is already there. tf-cost-preview tells you what the plan will cost.

## Related tools

| Tool | Use it for |
| --- | --- |
| [HarderAWS](https://github.com/chwaee/HarderAWS) | AWS security hardening Terraform |
| [aws-health-audit](https://github.com/chwaee/aws-health-audit) | Read-only AWS account audit |
| [tf-cost-preview](https://github.com/chwaee/tf-cost-preview) | Estimate Terraform plan costs |
| [appliedaiconsulting.io](https://appliedaiconsulting.io) | Consulting services |

## Templates

| Path | Use it for |
| --- | --- |
| `templates/python` | Python services and libraries. Lint, test, CodeQL, Trivy, GHCR, ECS, and Lambda. |
| `templates/node` | Node.js services and libraries. Same shape as Python, including Lambda. |
| `templates/go` | Go services and libraries. Same shape, without Lambda. |
| `templates/terraform` | Terraform repositories. Format, validate, tflint, tfsec, plan, apply, and drift. |

Root `.github/dependabot.yml`, `.github/workflows/stale-prs.yml`, and `.github/workflows/dependabot-automerge.yml` are for any client repository. Do not copy `.github/workflows/ci.yml`. That workflow validates this repository.

## What template should I use?

| You are shipping | Copy |
| --- | --- |
| A Python library, no deploy | `templates/python/.github/workflows/ci.yml` and `reusable-codeql.yml`. Add `release.yml` when you tag releases. |
| A Python image on GHCR | Those, plus `docker.yml` and `reusable-image.yml`. |
| A Python service on ECS | The image set, plus `deploy-aws-ecr.yml`. |
| A Python function on Lambda | The CI pair, plus `deploy-aws-lambda.yml`. |
| Node.js, same four targets | The matching files under `templates/node`. |
| A Go library or GHCR image | The matching files under `templates/go`. |
| A Go service on ECS | `templates/go` CI, image workflows, and `deploy-aws-ecr.yml`. |
| Go on Lambda | Not in this set. Use the container workflow, or write the function deploy yourself. |
| Terraform | `templates/terraform/.github/workflows/ci.yml` and `plan.yml`. Add `apply.yml` and `drift-check.yml` when applies run from Actions. |

## How to use

For a Python web app deploying to ECS, copy `templates/python/.github/workflows/` into the client repository's `.github/workflows/`. Copy `Dockerfile.python-base` to `Dockerfile` and `.dockerignore.template` to `.dockerignore`. Copy `.github/dependabot.yml`, `.github/workflows/stale-prs.yml`, and `.github/workflows/dependabot-automerge.yml` when the client wants dependency updates and stale-PR cleanup.

Create the task definition before the first deploy. See `templates/ecs/task-definition.json.example`.

Create the GitHub environment `production` and add required reviewers before enabling `deploy-aws-ecr.yml`. If the environment does not exist, GitHub creates it with no reviewers and the approval gate does nothing.

These are opinionated. Delete a workflow you do not need. Do not delete the blocking steps inside `ci.yml` and keep calling it this template.

## What "secure" means here

| Control | Where it lives |
| --- | --- |
| Actions pinned to a full commit SHA | Every `uses:` line. The version is the trailing comment. |
| OIDC to AWS | Deploy, plan, apply, and drift. No long-lived access keys. |
| Dependabot, weekly, minor and patch grouped | `.github/dependabot.yml` |
| Secret findings fail the job | Trivy filesystem and image scans (`vuln,secret`) |
| CodeQL | `reusable-codeql.yml`, in parallel with tests |
| Trivy HIGH and CRITICAL fail the job | Language CI, image build, and ECS deploy |
| Lint fails the job | ruff, ESLint, golangci-lint, or `terraform fmt -check` |
| GitHub secret scanning and push protection | Repository settings. A workflow cannot turn them on. See `SECURITY.md`. |

MEDIUM scanner findings print a warning and do not fail the job. HIGH and CRITICAL do. Coverage under 70% fails the job.

A Trivy filesystem scan of a repository with no dependency manifest is a pass. The log says so. `skip-dirs` skips `.git`, `vendor`, `.terraform`, `.venv`, and `node_modules`.

## Variables

Workflows read repository variables, not secrets. `GITHUB_TOKEN` is the Actions token, used for pull request comments, releases, GHCR, and issues. Set `DEPENDABOT_AUTOMERGE_ACTIONS` to `false` to stop auto-merge of Actions updates.

| Variable | Default | Used by |
| --- | --- | --- |
| `PYTHON_VERSION` | `3.12` | Python CI, release, Lambda |
| `NODE_VERSION` | `26.13.0` | Node CI, release, Lambda |
| `GO_VERSION` | `1.27.3` | Go CI and release |
| `COVERAGE_MIN` | `70` | Language CI |
| `COVERAGE_SOURCE` | `src` | Python and Node CI |
| `TRIVY_FAIL_SEVERITY` | `CRITICAL,HIGH` | CI, images, ECS |
| `TRIVY_WARN_SEVERITY` | `MEDIUM` | CI, images, ECS |
| `TRIVY_IGNORE_UNFIXED` | `false` | CI, images, ECS |
| `AWS_ROLE_ARN` | none | Every AWS workflow |
| `AWS_REGION` | `us-east-1` | Every AWS workflow |
| `ECR_REPOSITORY` | none | ECS deploy |
| `ECS_CLUSTER` | none | ECS deploy |
| `ECS_SERVICE` | none | ECS deploy |
| `ECS_CONTAINER_NAME` | none | ECS deploy |
| `ECS_TASK_DEFINITION` | `ecs/task-definition.json` | ECS deploy |
| `LAMBDA_DEPLOY_TOOL` | `sam` | Lambda deploy |
| `TF_WORKING_DIR` | `.` | Terraform and Lambda terraform path |
| `TF_VAR_environment` | unset | Lambda terraform path, only when the module declares `environment` |
| `TERRAFORM_VERSION` | `1.17.1` | Terraform workflows and the Lambda terraform path |
| `TFLINT_VERSION` | `v0.65.0` | Terraform CI |
| `DEPENDABOT_AUTOMERGE_ACTIONS` | enabled | Dependabot auto-merge |

An environment variable overrides the repository variable of the same name while that job runs. Use that on `production` when the apply role should differ from the plan role.

Auto-merge needs "Allow auto-merge" and a branch protection rule that requires the CI check. Without a required check, GitHub merges the pull request as soon as it is mergeable.

## Build time

Typical GitHub-hosted run, small repository. CodeQL runs beside the tests, so the wall clock is the slower job.

| Workflow | Typical |
| --- | --- |
| Python, Node, or Go CI | 4–8 minutes. Go can reach 9. |
| Terraform CI | 2–4 minutes |
| Terraform plan | 2–5 minutes |
| Docker image | 4–8 minutes |
| ECS deploy | 6–10 minutes |
| Lambda deploy, staging then production | 5–10 minutes |
| Drift check | 3–6 minutes |

Jobs are capped at 10 minutes for tests and image builds, 12 for CodeQL, and 15 for deploy and drift. A large monorepo can exceed the typical number. Split it before raising the cap.

## This repository

`.github/workflows/ci.yml` runs `scripts/validate-templates.sh`. It checks layout, SHA pins, and actionlint. It does not deploy anywhere.

Dependabot is configured for pip, npm, and Go as well as Actions, so the file is what you copy. This repository has no pip, npm, or Go manifest. Dependabot will report that. Delete the blocks the client does not use.

## Consulting

I drop the matching template into the client repository, wire the OIDC role, and leave a pipeline that already fails on lint, tests, and high-severity findings.

CONTACT: hello@appliedaiconsulting.io
