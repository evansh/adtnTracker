# Security policy

## Supported versions

Security fixes are applied to the latest commit on `main`. The app has not reached a production release, so no older version is currently supported.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability or include credentials, progress photos, health data, location history, or other personal information in an issue.

Use the repository's **Security → Advisories → Report a vulnerability** flow to disclose the issue privately. If private vulnerability reporting is unavailable, contact the repository owner privately through their GitHub profile.

Include only the minimum information needed to reproduce the issue:

- A concise impact statement
- Affected commit or app version
- Reproduction steps or a minimal proof of concept
- Suggested remediation, if known

Never include real user data or production credentials. Use synthetic test data and redact identifiers.

## Security baseline

Pull requests are expected to pass:

- Swift 6 compilation with warnings treated as errors
- Unit tests and a Release simulator smoke build
- Xcode static analysis
- Repository-history scans for common credential formats
- Checks for tracked secret files, insecure transport overrides, unsafe production logging, excessive workflow permissions, and mutable Action references

GitHub Actions are configured with read-only repository permissions. External Actions must be pinned to a full commit SHA and are maintained through Dependabot.
