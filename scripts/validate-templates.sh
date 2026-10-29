#!/usr/bin/env bash
# Check template layout, action pins, and workflow schema.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "missing $1"
}

require_file LICENSE
require_file README.md
require_file SECURITY.md
require_file CODEOWNERS.template
require_file .dockerignore.template
require_file Dockerfile.python-base
require_file Dockerfile.node-base
require_file Dockerfile.go-base
require_file .github/dependabot.yml
require_file .github/workflows/ci.yml
require_file .github/workflows/stale-prs.yml
require_file .github/workflows/dependabot-automerge.yml
require_file templates/ecs/task-definition.json.example
require_file templates/node/eslint.config.mjs
require_file templates/go/.golangci.yml

for stack in python node go terraform; do
  require_file "templates/${stack}/README.md"
done

for stack in python node go; do
  for name in ci.yml reusable-codeql.yml release.yml docker.yml reusable-image.yml deploy-aws-ecr.yml; do
    require_file "templates/${stack}/.github/workflows/${name}"
  done
done

for stack in python node; do
  require_file "templates/${stack}/.github/workflows/deploy-aws-lambda.yml"
done

if [ -f templates/go/.github/workflows/deploy-aws-lambda.yml ]; then
  fail "go has no Lambda workflow"
fi

for name in ci.yml plan.yml apply.yml drift-check.yml; do
  require_file "templates/terraform/.github/workflows/${name}"
done

cmp_same() {
  local first=$1
  shift
  for other in "$@"; do
    cmp -s "$first" "$other" || fail "$first and $other differ"
  done
}

cmp_same \
  templates/python/.github/workflows/reusable-codeql.yml \
  templates/node/.github/workflows/reusable-codeql.yml \
  templates/go/.github/workflows/reusable-codeql.yml
cmp_same \
  templates/python/.github/workflows/reusable-image.yml \
  templates/node/.github/workflows/reusable-image.yml \
  templates/go/.github/workflows/reusable-image.yml
cmp_same \
  templates/python/.github/workflows/docker.yml \
  templates/node/.github/workflows/docker.yml \
  templates/go/.github/workflows/docker.yml
cmp_same \
  templates/python/.github/workflows/deploy-aws-ecr.yml \
  templates/node/.github/workflows/deploy-aws-ecr.yml \
  templates/go/.github/workflows/deploy-aws-ecr.yml

python3 - <<'PY'
import pathlib
import re
import sys

import yaml

root = pathlib.Path(".")
errors = []

def check(condition, message):
    if not condition:
        errors.append(message)

workflows = sorted(root.glob("templates/*/.github/workflows/*.yml"))
workflows += sorted((root / ".github/workflows").glob("*.yml"))
for path in workflows:
    try:
        yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        errors.append(f"{path} is not valid YAML: {exc}")

yaml.safe_load((root / ".github/dependabot.yml").read_text())

sha = re.compile(
    r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?@[0-9a-f]{40}\s+#\s+v[0-9]"
)
local = re.compile(r"^\./\.github/workflows/[\w.-]+\.ya?ml$")
use_re = re.compile(r"^\s*uses:\s+(\S.*?)\s*$", re.M)

for path in workflows:
    text = path.read_text()
    for bad in ("pull_request_target", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "@main", "@master", "@latest"):
        if bad in text:
            errors.append(f"{path} contains {bad}")
    for match in use_re.finditer(text):
        ref = match.group(1).strip().strip("'\"")
        if ref.startswith("./"):
            if not local.match(ref):
                errors.append(f"{path} has a local uses that is not a workflow: {ref}")
                continue
            sibling = path.parent / pathlib.Path(ref).name
            if not sibling.is_file():
                errors.append(f"{path} calls missing {sibling}")
        elif not sha.match(ref):
            errors.append(f"{path} uses is not a pinned SHA: {ref}")

def in_order(path, markers):
    text = path.read_text()
    pos = 0
    for marker in markers:
        found = text.find(marker, pos)
        if found < 0:
            if text.find(marker) < 0:
                errors.append(f"{path} missing {marker!r}")
            else:
                errors.append(f"{path} has {marker!r} out of order")
            return
        pos = found + len(marker)

language_tail = [
    "COVERAGE_MIN",
    "aquasecurity/trivy-action",
    "actions/upload-artifact",
    "actions/github-script",
]
in_order(
    root / "templates/python/.github/workflows/ci.yml",
    ["persist-credentials: false", "ruff check", "bandit", *language_tail],
)
in_order(
    root / "templates/node/.github/workflows/ci.yml",
    ["persist-credentials: false", "npx eslint", "eslint-plugin-security", *language_tail],
)
in_order(
    root / "templates/go/.github/workflows/ci.yml",
    ["persist-credentials: false", "golangci/golangci-lint-action", "securego/gosec", *language_tail],
)

for stack in ("python", "node", "go"):
    ci = (root / f"templates/{stack}/.github/workflows/ci.yml").read_text()
    codeql = root / f"templates/{stack}/.github/workflows/reusable-codeql.yml"
    check("reusable-codeql.yml" in ci, f"{stack} ci does not call reusable-codeql.yml")
    check("workflow_call" in codeql.read_text(), f"{stack} codeql workflow is not reusable")
    check(
        "skip-dirs: .git,vendor,.terraform,.venv,node_modules" in ci,
        f"{stack} ci does not set Trivy skip-dirs",
    )

image = (root / "templates/python/.github/workflows/reusable-image.yml").read_text()
for marker in (
    "docker/setup-buildx-action",
    "docker/build-push-action",
    "aquasecurity/trivy-action",
    "type=sha,format=short",
    "type=raw,value=latest,enable={{is_default_branch}}",
):
    check(marker in image, f"reusable-image.yml missing {marker}")

for stack in ("python", "node", "go"):
    docker = (root / f"templates/{stack}/.github/workflows/docker.yml").read_text()
    check("reusable-image.yml" in docker, f"{stack} docker.yml does not call reusable-image.yml")
    ecr = (root / f"templates/{stack}/.github/workflows/deploy-aws-ecr.yml").read_text()
    for marker in (
        "docker/setup-buildx-action",
        "docker/build-push-action",
        "aquasecurity/trivy-action",
        "type=sha,format=short",
        "type=raw,value=latest,enable={{is_default_branch}}",
        "role-to-assume",
        "id-token: write",
        "environment: production",
    ):
        check(marker in ecr, f"{stack} deploy-aws-ecr.yml missing {marker}")

for stack in ("python", "node"):
    lam = (root / f"templates/{stack}/.github/workflows/deploy-aws-lambda.yml").read_text()
    for marker in ("role-to-assume", "id-token: write", "environment: staging", "environment: production"):
        check(marker in lam, f"{stack} deploy-aws-lambda.yml missing {marker}")

for name in ("Dockerfile.python-base", "Dockerfile.node-base", "Dockerfile.go-base"):
    text = (root / name).read_text()
    check(len(re.findall(r"^FROM ", text, re.M)) >= 2, f"{name} is not multi-stage")
    check(":latest" not in text, f"{name} uses :latest")
    users = re.findall(r"^USER\s+(\S+)", text, re.M)
    check(users, f"{name} has no USER")
    for user in users:
        check(user.split(":")[0] not in {"root", "0"}, f"{name} runs as {user}")

ignore = (root / ".dockerignore.template").read_text()
for marker in (".git", ".env", "node_modules", ".terraform"):
    check(marker in ignore, f".dockerignore.template missing {marker}")

dependabot = (root / ".github/dependabot.yml").read_text()
for marker in ("github-actions", "pip", "npm", "gomod", "interval: weekly", "dependencies", "minor", "patch"):
    check(marker in dependabot, f"dependabot.yml missing {marker}")

stale = (root / ".github/workflows/stale-prs.yml").read_text()
stale_days = int(re.search(r"days-before-pr-stale:\s*(-?\d+)", stale).group(1))
close_days = int(re.search(r"days-before-pr-close:\s*(-?\d+)", stale).group(1))
issue_days = int(re.search(r"days-before-issue-stale:\s*(-?\d+)", stale).group(1))
# days-before-pr-close is the wait after the stale label, not the total age.
check(stale_days > 0 and close_days > 0, "stale workflow days must be positive")
check(stale_days + close_days == 60, f"stale close age is {stale_days + close_days}, want 60")
check(issue_days == -1, "stale workflow should not mark issues")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("template structure ok")
PY

install_actionlint() {
  local version=1.7.12
  local arch
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *)
      fail "unsupported architecture $(uname -m)"
      ;;
  esac
  local dir="${TMPDIR:-/tmp}/actionlint-${version}-${arch}"
  local file="actionlint_${version}_linux_${arch}.tar.gz"
  if [ ! -x "${dir}/actionlint" ]; then
    mkdir -p "$dir"
    curl -fsSL -o "${dir}/${file}" "https://github.com/rhysd/actionlint/releases/download/v${version}/${file}"
    curl -fsSL -o "${dir}/checksums.txt" "https://github.com/rhysd/actionlint/releases/download/v${version}/actionlint_${version}_checksums.txt"
    (
      cd "$dir"
      grep "${file}" checksums.txt | sha256sum -c - >&2
      tar -xzf "${file}" actionlint
    )
  fi
  printf '%s\n' "${dir}/actionlint"
}

actionlint_bin=$(install_actionlint)

echo "actionlint $($actionlint_bin -version)"
"$actionlint_bin" .github/workflows/*.yml

for stack in python node go terraform; do
  tmp=$(mktemp -d)
  mkdir -p "${tmp}/.github/workflows"
  cp "templates/${stack}/.github/workflows/"*.yml "${tmp}/.github/workflows/"
  git init -q "$tmp"
  echo "actionlint templates/${stack}"
  (cd "$tmp" && "$actionlint_bin")
  rm -rf "$tmp"
done

echo "validate-templates.sh passed"
