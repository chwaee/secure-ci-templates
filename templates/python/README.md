# Python

CI, release, container build, ECS deploy, and Lambda deploy for a Python repository.

Use it for a service or a library that should fail the build on ruff, Bandit high findings, tests under 70% coverage, Trivy high findings, or secrets in the tree. CodeQL runs beside the tests.

Python 3.12 is the default. That is conservative for compatibility with client codebases still on 3.11 or 3.12. Set `PYTHON_VERSION` to `3.13` or newer when the project already runs there.

## Prerequisites

- `requirements.txt` or `pyproject.toml` at the repository root, so pip can be cached.
- A `src/` directory, unless you set `COVERAGE_SOURCE`.
- `pyproject.toml` or `setup.py`, when present, must be pip-installable.
- Tests that pytest can collect. Coverage is measured on `COVERAGE_SOURCE` and fails under `COVERAGE_MIN` (default 70).
- For ECS or Lambda: an AWS OIDC role and the GitHub environments below. No access keys.

## Customize

1. Copy `templates/python/.github/workflows/` to `.github/workflows/` in the client repository.
2. Set `PYTHON_VERSION` and `COVERAGE_SOURCE` if the defaults are wrong.
3. For an image, copy `Dockerfile.python-base` to `Dockerfile` and `.dockerignore.template` to `.dockerignore`. Change `CMD`.
4. For ECS, create `ecs/task-definition.json` before the first deploy. Start from [`templates/ecs/task-definition.json.example`](../ecs/task-definition.json.example). The container `name` must match `ECS_CONTAINER_NAME`. AWS describes the file shape in the [task definition template](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-definition-template.html).
5. Create GitHub environments before the first deploy. `production` needs required reviewers. Lambda also needs `staging`.

## Workflows

| Workflow | Required | What it does |
| --- | --- | --- |
| `ci.yml` | Yes | Ruff, Bandit, pytest, Trivy, coverage artifact, pull request comment. |
| `reusable-codeql.yml` | Yes, with `ci.yml` | CodeQL for Python. `build-mode` is `none`. |
| `release.yml` | No | On a `vX.Y.Z` tag, build a wheel and sdist and open a GitHub release with generated notes. |
| `docker.yml` | No | Build, scan, and push to ghcr.io. Pull requests scan and do not push. |
| `reusable-image.yml` | No, with `docker.yml` | The image build `docker.yml` calls. |
| `deploy-aws-ecr.yml` | No | On `main`, OIDC, push to ECR, update ECS. Environment `production`. |
| `deploy-aws-lambda.yml` | No | Staging, then production. SAM by default, or Terraform. |

Copy the whole workflows directory when you want more than CI. `ci.yml` calls `reusable-codeql.yml` by path. `docker.yml` calls `reusable-image.yml` the same way.

## Thresholds

| Knob | Default | Effect |
| --- | --- | --- |
| `COVERAGE_MIN` | `70` | pytest `--cov-fail-under`. |
| `COVERAGE_SOURCE` | `src` | Directory passed to `--cov`. |
| `TRIVY_FAIL_SEVERITY` | `CRITICAL,HIGH` | Severities that fail the job. |
| `TRIVY_WARN_SEVERITY` | `MEDIUM` | Severities that warn. |
| `TRIVY_IGNORE_UNFIXED` | `false` | Set `true` to skip vulnerabilities with no fix. |

Ruff and `ruff format --check` fail the job. The step name is the fix command. Bandit `--severity-level high` fails the job. Medium is a warning. Secrets from Trivy fail the job. A `.trivyignore` file is how you suppress a false positive.

Trivy skips `.git`, `vendor`, `.terraform`, `.venv`, and `node_modules`. A clean scan on a new repository with no dependency manifest is a pass.

A typical CI run is 4–8 minutes. The image build is 4–8. ECS is 6–10. Lambda, both environments, is 5–10. The image build is `linux/amd64` only, so the local image can be scanned before it is pushed. Multi-arch needs a different scan path.

## Variables and tokens

`GITHUB_TOKEN` comments on pull requests, uploads the release, and pushes to ghcr.io. It is the workflow token. Do not add a personal access token.

AWS uses `AWS_ROLE_ARN` and `AWS_REGION`. See the root README for the full variable list. There is no `AWS_ACCESS_KEY_ID`.

## ECS

`deploy-aws-ecr.yml` runs only on `main`, in the `production` environment, and assumes `AWS_ROLE_ARN` with OIDC. It builds `linux/amd64`, scans with Trivy, pushes to `ECR_REPOSITORY`, renders `ECS_TASK_DEFINITION`, and updates `ECS_SERVICE`.

Create `ecs/task-definition.json` at the documented path before the first deploy. The workflow names that path in the error when the file is missing.

Turn on the ECS deployment circuit breaker with rollback on the service. To roll back by hand:

```bash
aws ecs list-task-definitions --family app --sort DESC
aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$PREVIOUS_ARN"
```

## Lambda

`LAMBDA_DEPLOY_TOOL` is `sam` or `terraform`.

SAM needs `template.yaml` (or `template.yml`) and `samconfig.toml` with `staging` and `production` deploy environments. The workflow runs `sam build` and `sam deploy --config-env staging`, then the same for production after the `production` environment approves.

Terraform needs `.tf` files in `TF_WORKING_DIR`. Set the GitHub environment variable `TF_VAR_environment` only when the module declares `variable "environment"`. The workflow exports it for that apply. Leave it unset when the module does not have the variable.

## HarderAWS

Apply [HarderAWS](https://github.com/chwaee/HarderAWS) before the first production deploy. It is the account baseline: CloudTrail, GuardDuty, S3 Block Public Access, KMS, and Config. It does not create a GitHub OIDC provider or a deploy role. Add those yourself.

Trust policy for the deploy role, twice if staging and production differ:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:environment:production"
    }
  }
}
```

ECS needs ECR push (`ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage`), `ecs:DescribeTaskDefinition`, `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `ecs:DescribeServices`, and `iam:PassRole` on the task execution role.

Lambda SAM needs the usual CloudFormation and Lambda deploy actions, scoped to the stack. The Terraform path needs what that root module applies, plus the state bucket.

## Release

`release.yml` does not publish to PyPI. Add a trusted publisher later if the client wants that. The GitHub release notes come from merged pull request titles.
