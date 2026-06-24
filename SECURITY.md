# Security Policy

`descripex` provides the Descripex discovery/`describe` protocol — `api()`
annotations, `__api__/0` introspection, manifest building, and MCP tool
generation. It is introspection infrastructure, but it gates dependency version
bounds across a wider stack and emits manifests/schemas consumed by automated
agents, so we take security reports seriously.

## Supported Versions

This library is pre-1.0; only the current release line receives security fixes.

| Version | Supported          |
| ------- | ------------------ |
| 0.11.x   | :white_check_mark: |
| < 0.11   | :x:                |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately through GitHub's **Security** tab on this repository:
**Security → Advisories → "Report a vulnerability"**
(<https://github.com/ZenHive/descripex/security/advisories/new>).

This opens a private advisory visible only to you and the maintainers.

### In scope

- Manifest building (`Descripex.Manifest`) and schema generation from annotations
- MCP tool generation (`Descripex.MCP`) and the discovery surface (`Descripex.Discoverable`)
- Any path where crafted annotations or input produce incorrect or unsafe manifests/schemas

### Out of scope

- Vulnerabilities in applications that consume the generated manifests
- Vulnerabilities in upstream dependencies — report those to their projects, though a heads-up is welcome.

### What to expect

- **Acknowledgement** within a few business days.
- A fix or mitigation plan communicated through the private advisory.
- Coordinated disclosure: we'll agree on a disclosure timeline with you before any public release.

Thank you for helping keep the stack safe.
