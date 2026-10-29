# Security policy

This file is the policy for secure-ci-templates. Copy it into a client repository and replace the contact.

## Reporting

Email hello@appliedaiconsulting.io. Replace that address when you copy this file.

Do not open a public issue for a vulnerability, and do not include an exploit. Describe the workflow or Dockerfile, the effect, and whether you have a fix.

## Response

We acknowledge a report within 3 business days. A fix for a high-severity issue in this repository is targeted within 30 days. Those are targets, not a contract.

## Scope

In scope: the workflows, Dockerfiles, and scripts in this repository.

Out of scope: upstream GitHub Actions, scanner databases, a client's cloud account, and findings that require a secret the workflows do not have. Trivy, CodeQL, tfsec, and Dependabot report upstream vulnerabilities. Those reports go to the upstream project.

## GitHub settings that are not in the workflows

Turn these on in the repository settings. A workflow cannot enable them.

- Secret scanning
- Push protection
- Dependabot alerts
- Code scanning, if the CodeQL workflow is not already the advanced setup

Private repositories need GitHub Code Security for CodeQL and secret scanning.
