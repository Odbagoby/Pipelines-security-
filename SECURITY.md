# Security policy

## Reporting a vulnerability

Please do not open a public issue for security problems. Use GitHub's private vulnerability
reporting instead: open the repository's **Security** tab and choose **Report a vulnerability**.

You can expect an acknowledgement within 3 working days and a fix or mitigation plan within 14.

## Supported versions

Only the latest commit on `main` is supported.

## Handling findings from the pipeline

Critical and High findings block the merge. If a finding must be accepted, the exception is
recorded in code (for example a Checkov skip comment or a line in `.zap/rules.tsv`) with a written
justification, so every exception is reviewed in a pull request and visible in history.
