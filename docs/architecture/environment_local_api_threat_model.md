# Environment local API / Socket / SSH/SFTP — threat model (#50)

**Status:** research / non-operational. No listener, SSH service, network socket or privileged binding is installed by this package.

## Trust and deployment boundaries

- Android PRoot is **not a VM**: it shares the Android host network and kernel. A bound port in PRoot is not isolated from the host.
- Only explicit loopback addresses (`127.0.0.1`, `::1`) qualify for the local API proof of concept. Never rely on a hostname, unspecified bind address, `0.0.0.0`, or a default exposed interface.
- Both **binding** and **request authorization** are required. A local connection does not by itself grant privileges.
- Do not place bearer tokens, SSH private keys, passwords, secrets, request bodies or raw user paths in logs or model-visible tool output.
- Authorization is per client, per task and per action, revocable and fail-closed. The global permission broker remains owned by #27; this package never implements or replaces it.

## Threat / mitigation matrix

| Threat | Required mitigation | Verification |
| --- | --- | --- |
| Listener accidentally binds public interface | Explicit loopback bind; reject unknown families | `environment_loopback_auth_test.dart` policy assertions |
| Another local application calls API | Authenticated client/session/task, deny by default | Anonymous and wrong-task denial |
| Token replay | Expiry / nonce or sequence, revocation | Stale and revoked token denial |
| Unlimited requests | Rate and size limits, cancellation | Reject over-budget requests |
| Remote forwarding to SSH/SFTP | Separate per-client authorization and consent | Not yet implemented or tested |
| PRoot assumed network-isolated | Model as shared-host | Explicit documented restriction |
| Secret/log exfiltration | Redact credentials and request payloads | Log review required on physical device |

## Required integration and acceptance gates

1. The eventual production socket binding must be under the #53 runtime interface and #27 capability owner; no shared entry points change here.
2. A real Android API24/25 and modern Android device must validate loopback binding, revoke/expiry, external-app connection attempts and network exposure with sanitized logs.
3. SSH/SFTP requires a separate audited implementation, credential handling, host key verification, and platform owner approval.
4. Existing tests provide only a **deterministic admission-policy model**, not live network security, TLS, OS isolation or active socket validation.
5. Keep #50 Open until actual platform enforcement and end-to-end authorization evidence pass.
