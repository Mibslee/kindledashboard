# Security Policy

## Supported Versions

Security fixes are currently tracked on the latest public release only.

## Reporting a Vulnerability

Please open a GitHub issue with a minimal reproduction. Do not include credentials, private IP addresses, access tokens, personal screenshots, or files copied from a Kindle that may contain account data.

## Privacy Model

KindleDashboard is designed to run locally:

- The Mac app serves a local HTTP dashboard.
- The Kindle extension fetches dashboard frames from the Mac on the same trusted network.
- No cloud backend is required by the project itself.

Any optional data source you connect, such as weather, calendar, music, or task data, should be reviewed separately according to that provider's own permissions and privacy model.

## Hardware and Jailbreak Boundary

This project assumes you already understand and accept the risks of modifying your own Kindle. It does not bypass third-party accounts, DRM, paid services, or device ownership controls.
