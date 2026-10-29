# Node.js

CI, release, container build, ECS deploy, and Lambda deploy for a Node.js repository.

Use it when the build should fail on ESLint, ESLint security errors, `npm audit` high findings, tests under 70% line coverage, Trivy high findings, or secrets in the tree. CodeQL runs beside the tests.

The default runtime is Node 26.13.0, the current 26 LTS line. Set `NODE_VERSION` to pin a different release.

## Prerequisites

- `package-lock.json` at the repository root. The workflow runs `npm ci`, not `npm install`.
- A `src/` directory, unless you set `COVERAGE_SOURCE`.
- A test runner. Jest if it is a dependency. Otherwise Mocha. Otherwise a `scripts.test` entry that is not the npm placeholder. Coverage is enforced with Jest's threshold or with c8.
- An ESLint config, or a `lint` script. If you have neither, copy `templates/node/eslint.config.mjs` to `eslint.config.mjs` and install `eslint@9.39.5` and `eslint-plugin-security@4.2.0`.
- For ECS or Lambda: an AWS OIDC role and the GitHub environments below. No access keys.

The security step installs its own ESLint and `eslint-plugin-security` under the runner temp directory. It does not change `package.json` or the lockfile. Errors from that config fail the job. Warnings do not. `npm audit --audit-level=high` fails the job. Moderate findings are a warning.

## Customize

1. Copy `templates/node/.github/workflows/` to `.github/workflows/` in the client repository.
2. Set `NODE_VERSION` and `COVERAGE_SOURCE` if the defaults are wrong.
3. For an image, copy `Dockerfile.node-base` to `Dockerfile` and `.dockerignore.template` to `.dockerignore`. Change `CMD`. `npm ci --omit=dev` runs install scripts. Remove a dependency that you do not trust rather than hoping the image build skips scripts.
4. For ECS, create `ecs/task-definition.json` before the first deploy. Start from [`templates/ecs/task-definition.json.example`](../ecs/task-definition.json.example). The container `name` must match `ECS_CONTAINER_NAME`. AWS describes the file shape in the [task definition template](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-definition-template.html).
5. Create GitHub environments before the first deploy. `production` needs required reviewers. Lambda also needs `staging`.

## Workflows

| Workflow | Required | What it does |
| --- | --- | --- |
| `ci.yml` | Yes | ESLint, security ESLint, npm audit, tests, Trivy, coverage artifact, pull request comment. |
| `reusable-codeql.yml` | Yes, with `ci.yml` | CodeQL for `javascript-typescript`. `build-mode` is `none`. |
| `release.yml` | No | On a `vX.Y.Z` tag, `npm pack` and open a GitHub release with generated notes. It does not publish to npm. |
| `docker.yml` | No | Build, scan, and push to ghcr.io. Pull requests scan and do not push. |
| `reusable-image.yml` | No, with `docker.yml` | The image build `docker.yml` calls. |
| `deploy-aws-ecr.yml` | No | On `main`, OIDC, push to ECR, update ECS. Environment `production`. |
| `deploy-aws-lambda.yml` | No | Staging, then production. SAM by default, or Terraform. |

`ci.yml` calls `reusable-codeql.yml` by path. Copy both.

## Thresholds

| Knob | Default | Effect |
| --- | --- | --- |
| `COVERAGE_MIN` | `70` | Jest line threshold, or c8 `--lines`. |
| `COVERAGE_SOURCE` | `src` | Jest `collectCoverageFrom`, or the c8 include. |
| `TRIVY_FAIL_SEVERITY` | `CRITICAL,HIGH` | Severities that fail the job. |
| `TRIVY_WARN_SEVERITY` | `MEDIUM` | Severities that warn. |
| `TRIVY_IGNORE_UNFIXED` | `false` | Set `true` to skip vulnerabilities with no fix. |

Trivy skips `.git`, `vendor`, `.terraform`, `.venv`, and `node_modules`. Lockfiles are still scanned. A clean scan on a new repository with no dependency manifest is a pass. Secrets fail the job. A `.trivyignore` file suppresses a false positive.

A typical CI run is 4–8 minutes. The image build is 4–8. ECS is 6–10. Lambda, both environments, is 5–10. The image is `linux/amd64` so it can be scanned before the push.

## Variables and tokens

`GITHUB_TOKEN` comments on pull requests, uploads the release, and pushes to ghcr.io. AWS uses `AWS_ROLE_ARN` and `AWS_REGION`. There is no `AWS_ACCESS_KEY_ID`.

The variable table in the root README is the full list.

## ECS

Same file as the Python and Go templates. It runs only on `main`, in `production`, and assumes the role with OIDC. Create `ecs/task-definition.json` before the first deploy.

Turn on the ECS deployment circuit breaker with rollback. To roll back by hand:

```bash
aws ecs list-task-definitions --family app --sort DESC
aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$PREVIOUS_ARN"
```

## Lambda

`LAMBDA_DEPLOY_TOOL` is `sam` or `terraform`.

SAM needs `template.yaml` (or `template.yml`) and `samconfig.toml` with `staging` and `production` environments. Node is installed before `sam build` so function builds have a runtime.

Terraform needs `.tf` files in `TF_WORKING_DIR`. Set `TF_VAR_environment` on the GitHub environment only when the module declares `variable "environment"`.

## HarderAWS

Apply [HarderAWS](https://github.com/chwaee/HarderAWS) before the first production deploy. It is the account baseline: CloudTrail, GuardDuty, S3 Block Public Access, KMS, and Config. It does not create a GitHub OIDC provider or a deploy role.

The trust policy must limit `token.actions.githubusercontent.com:sub` to `repo:ORG/REPO:environment:production`, and the staging twin if staging uses another role. The audience is `sts.amazonaws.com`.

ECS needs ECR push, `ecs:DescribeTaskDefinition`, `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `ecs:DescribeServices`, and `iam:PassRole` on the task execution role. Lambda SAM needs CloudFormation and Lambda deploy actions scoped to the stack.
