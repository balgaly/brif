# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in brif, **please do not open a public issue**.

Instead:

1. Email **balgaly@gmail.com** with a description of the vulnerability
2. Include steps to reproduce if possible
3. Allow reasonable time for a fix before any public disclosure

## Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 7 days
- **Fix**: Depends on severity — critical issues are prioritized

## Scope

This policy covers the brif shell scripts, install scripts, and hook scripts in this repository.

## Security Practices

- No network access beyond optional IP geolocation (HTTPS only)
- No data collection or telemetry
- Input validation on all user-supplied arguments
- File permissions enforced on session directories (chmod 700)

## Thank You

Security reports are taken seriously. Contributors who responsibly disclose vulnerabilities will be credited in the changelog (unless they prefer to remain anonymous).
