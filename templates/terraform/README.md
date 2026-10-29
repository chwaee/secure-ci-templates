# Terraform

Format, validate, lint, plan, apply, and a weekly drift check for a Terraform repository.

Use it for a stack that should fail review on `terraform fmt`, `terraform validate`, tflint, or tfsec high findings. Plan output is commented on the pull request. Apply is a manual run with an environment approval.

`ci.yml` runs `terraform init -backend=false`. It does not need credentials and it does not read state. Plan, apply, and drift init the real backend.

## Remote state

Plan, apply, and drift assume a remote backend, either S3 with a DynamoDB lock table or Terraform Cloud. Do not use local state for a shared project. A laptop apply and an Actions apply will otherwise diverge, and the drift check has nothing durable to compare.

[HarderAWS `backend.tf.example`](https://github.com/chwaee/HarderAWS/blob/main/backend.tf.example) is a reference S3 backend: encrypted bucket, lock table, and a key that is not shared with application stacks. This template does not create that bucket. Point `backend.tf` at a bucket you already have before you enable plan or apply.

## Prerequisites

- Terraform CLI 1.17.1, unless you set `TERRAFORM_VERSION`.
- tflint v0.65.0, unless you set `TFLINT_VERSION`.
- For tflint, either your own `.tflint.hcl` or none. If the file is missing, CI writes one that enables `terraform-linters/tflint-ruleset-aws` 0.50.0.
- For plan, apply, and drift: `AWS_ROLE_ARN` for OIDC. The plan job does not use a GitHub environment, so it sees repository variables. Apply uses the `production` environment, so an environment variable of the same name overrides the repository one.
- tfsec 1.28.14. The workflow downloads that release and checks `tfsec_1.28.14_checksums.txt`. Upstream now points people at Trivy config scanning. This template still runs tfsec.

## Customize

1. Copy `templates/terraform/.github/workflows/` to `.github/workflows/` in the client repository.
2. Set `TF_WORKING_DIR` if the stack is not at the repository root.
3. Add `backend.tf` with a remote backend before enabling `plan.yml`.
4. Create the `production` environment with required reviewers before the first apply.
5. Set `AWS_ROLE_ARN`. Use a read-only role for plan if you can, and a narrower apply role on the `production` environment.

## Workflows

| Workflow | Required | What it does |
| --- | --- | --- |
| `ci.yml` | Yes | `fmt -check`, `init -backend=false`, `validate`, tflint, tfsec. |
| `plan.yml` | Yes, for a shared stack | OIDC, plan, comment on the pull request. |
| `apply.yml` | No | `workflow_dispatch`. The input `confirm` must be `apply`. Environment `production`. |
| `drift-check.yml` | No | Mondays 12:00 UTC, and `workflow_dispatch`. Opens or comments on an issue titled `Terraform drift detected` when the plan exit code is 2. |

There is no coverage number. Terraform CI does not upload an artifact.

## Thresholds

tfsec `--minimum-severity HIGH` fails the job. `--minimum-severity MEDIUM --soft-fail` is a warning. `terraform fmt -check` fails the job. The step name says `terraform fmt -recursive` fixes it.

A typical validate run is 2–4 minutes. Plan is 2–5. Drift is 3–6. Apply depends on the stack and is capped at 15 minutes.

## Variables and tokens

| Variable | Default | Used by |
| --- | --- | --- |
| `AWS_ROLE_ARN` | none | plan, apply, drift |
| `AWS_REGION` | `us-east-1` | plan, apply, drift |
| `TF_WORKING_DIR` | `.` | all four workflows |
| `TERRAFORM_VERSION` | `1.17.1` | all four workflows |
| `TFLINT_VERSION` | `v0.65.0` | CI |

`GITHUB_TOKEN` posts the plan comment and opens the drift issue. AWS auth is OIDC. There is no `AWS_ACCESS_KEY_ID`.

Empty `AWS_ROLE_ARN` on plan, apply, or drift fails before `terraform init` talks to the backend.

## Apply

Run the workflow from the Actions tab. Type `apply` in `confirm`. The `production` environment must then approve the job. Create that environment with required reviewers first. If it does not exist, GitHub creates it with no reviewers and the gate does nothing.

Apply takes a saved plan and runs `terraform apply` on that file. It does not cancel an in-progress apply.

## Drift

Exit code 0 is no change. Exit code 1 fails the job. Exit code 2 opens an issue, or comments on the open issue with that title. The plan text is truncated to stay under the GitHub comment limit.

## HarderAWS

Apply [HarderAWS](https://github.com/chwaee/HarderAWS) for the account baseline before this pipeline applies application infrastructure into a new account. HarderAWS does not create the GitHub OIDC provider. Add the provider and a role whose trust policy limits `token.actions.githubusercontent.com:sub` to `repo:ORG/REPO:environment:production` for apply, and to the pull request subject if the plan role is separate.
