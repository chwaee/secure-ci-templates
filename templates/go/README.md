# Go

CI, release, container build, and ECS deploy for a Go module.

Use it when the build should fail on golangci-lint, `go vet`, gosec high findings, tests under 70% coverage, Trivy high findings, or secrets in the tree. CodeQL runs beside the tests and uses `autobuild`.

There is no Lambda workflow. Ship the function as a container with `deploy-aws-ecr.yml`, or write the function deploy yourself.

The Go version is pinned at 1.27.3 in the workflow and in `Dockerfile.go-base`. Set `GO_VERSION` to move the CI toolchain. Bump the Dockerfile digest in the same change when a new stable ships. The workflow does not look up a version at runtime.

## Prerequisites

- `go.mod` at the repository root. Commit `go.sum`.
- Tests under packages that `go test ./...` covers. The total from `go tool cover -func` must be at least `COVERAGE_MIN` (default 70).
- For a release, package `main` at the module root. The release builds `linux/amd64` and `linux/arm64`.
- For an image, the same `main` package. The runtime image is distroless and has no shell.
- For ECS: an AWS OIDC role and a `production` environment with required reviewers. No access keys.

If the repository has no `.golangci.yml`, CI writes the default from `templates/go/.golangci.yml`: errcheck, gosec, govet, ineffassign, and staticcheck. A file you commit wins, and gosec still runs as its own step.

## Customize

1. Copy `templates/go/.github/workflows/` to `.github/workflows/` in the client repository.
2. Copy `templates/go/.golangci.yml` to the module root if you want that config in review, or leave it out and let CI write the default.
3. Set `GO_VERSION` only when you have bumped the Dockerfile to the same release.
4. For an image, copy `Dockerfile.go-base` to `Dockerfile` and `.dockerignore.template` to `.dockerignore`.
5. For ECS, create `ecs/task-definition.json` before the first deploy. Start from [`templates/ecs/task-definition.json.example`](../ecs/task-definition.json.example). The container `name` must match `ECS_CONTAINER_NAME`. AWS describes the file shape in the [task definition template](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-definition-template.html).

## Workflows

| Workflow | Required | What it does |
| --- | --- | --- |
| `ci.yml` | Yes | golangci-lint, `go vet`, gosec, `go test` with coverage, Trivy, pull request comment. |
| `reusable-codeql.yml` | Yes, with `ci.yml` | CodeQL for Go. `build-mode` is `autobuild`. |
| `release.yml` | No | On a `vX.Y.Z` tag, build two binaries, write SHA256SUMS, and open a GitHub release. |
| `docker.yml` | No | Build, scan, and push to ghcr.io. Pull requests scan and do not push. |
| `reusable-image.yml` | No, with `docker.yml` | The image build `docker.yml` calls. |
| `deploy-aws-ecr.yml` | No | On `main`, OIDC, push to ECR, update ECS. Environment `production`. |

## Thresholds

| Knob | Default | Effect |
| --- | --- | --- |
| `COVERAGE_MIN` | `70` | Total coverage from `go tool cover -func`. |
| `TRIVY_FAIL_SEVERITY` | `CRITICAL,HIGH` | Severities that fail the job. |
| `TRIVY_WARN_SEVERITY` | `MEDIUM` | Severities that warn. |
| `TRIVY_IGNORE_UNFIXED` | `false` | Set `true` to skip vulnerabilities with no fix. |

gosec `-severity high` fails the job. Medium is a warning. Secrets from Trivy fail the job. A `.trivyignore` file suppresses a false positive.

Trivy skips `.git`, `vendor`, `.terraform`, `.venv`, and `node_modules`. A clean scan on a module with no third-party findings is a pass. A module with no `go.sum` still scans; an empty result is a pass.

A typical CI run is 4–9 minutes. The image build is 4–8. ECS is 6–10. The image is `linux/amd64` so it can be scanned before the push.

## Variables and tokens

`GITHUB_TOKEN` comments on pull requests, uploads the release, and pushes to ghcr.io. AWS uses `AWS_ROLE_ARN` and `AWS_REGION`. There is no `AWS_ACCESS_KEY_ID`.

## ECS

The deploy workflow matches the Python and Node copies. It runs only on `main`, in `production`, and assumes the role with OIDC. Create `ecs/task-definition.json` before the first deploy.

Turn on the ECS deployment circuit breaker with rollback. To roll back by hand:

```bash
aws ecs list-task-definitions --family app --sort DESC
aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$PREVIOUS_ARN"
```

## HarderAWS

Apply [HarderAWS](https://github.com/chwaee/HarderAWS) before the first production deploy. It is the account baseline: CloudTrail, GuardDuty, S3 Block Public Access, KMS, and Config. It does not create a GitHub OIDC provider or a deploy role.

The trust policy must limit `token.actions.githubusercontent.com:sub` to `repo:ORG/REPO:environment:production`. The audience is `sts.amazonaws.com`.

ECS needs ECR push, `ecs:DescribeTaskDefinition`, `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `ecs:DescribeServices`, and `iam:PassRole` on the task execution role.
