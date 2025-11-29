# Security Scanning Setup

This repository uses automated security scanning to detect vulnerabilities and security misconfigurations.

## Workflows

### CodeQL Analysis (`codeql.yml`)
- Scans Python and JavaScript code for security vulnerabilities
- Runs on push, PR, and weekly schedule
- Results appear in the **Security > Code scanning** tab

### Security Scanning (`security-scan.yaml`)
- **Python SCA**: Scans all Lambda function dependencies using Safety
- **Node.js SCA**: Scans UI test dependencies using npm audit
- **Trivy File System Scan**: Comprehensive vulnerability scanning
- **Infrastructure Scan**: Scans CloudFormation templates for misconfigurations
- Results appear in the **Security > Code scanning** tab

## Enabling Code Scanning

For code scanning results to appear in the Security tab, you need to enable it:

1. Go to **Settings > Security > Code security and analysis**
2. Under "Code scanning", click **Set up** or **Enable**
3. Select "Set up with GitHub Actions" (workflows are already configured)
4. Results will appear after the next workflow run

## Failure Behavior

All scans are configured to **fail the workflow** if HIGH or CRITICAL vulnerabilities are found:
- Safety (Python): Fails on any vulnerability
- npm audit: Fails on HIGH or CRITICAL vulnerabilities
- Trivy: Fails on HIGH or CRITICAL vulnerabilities
- Infrastructure scan: Fails on HIGH or CRITICAL misconfigurations

## Dependabot

Dependabot is configured to:
- Monitor all Python and Node.js dependencies
- Create pull requests for security updates
- Run weekly checks on Mondays

View alerts in **Security > Dependabot alerts**.

