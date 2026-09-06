# Feature Specification: CoolerControl password handoff

**Feature Branch**: `001-coolercontrol-password-stdin`

**Created**: 2026-09-06

**Status**: Implemented

**Input**: Fleet security remediation of the reported temporary password storage.

## User Scenarios & Testing

### User Story 1 - Authenticate without password files (Priority: P1)

A Waybar user can authenticate to CoolerControl with their configured password
without the helper writing that password into a temporary file.

**Why this priority**: A password file can survive an interrupted process and
unnecessarily exposes the password to storage inspection.

**Independent Test**: Exercise password authentication with disposable credentials
and an isolated transport double. Inspect child arguments and temporary files.

**Acceptance Scenarios**:

1. **Given** a valid password, **when** login succeeds, **then** status requests
   authenticate and no temporary transport file or child process argument contains it.
2. **Given** a rejected login or transport error, **when** authentication fails,
   **then** no password file remains and the normal failure result is returned.
3. **Given** a working bearer token, **when** authentication starts, **then**
   the existing token preference avoids password login.

### Edge Cases

- Missing password, failed login, status rejection, and subprocess timeout.
- Existing loopback aliases and credential scope must be preserved.
- Fixture authentication must remain isolated from real services.

## Requirements

### Functional Requirements

- **FR-001**: Password transport MUST NOT create temporary files containing the password.
- **FR-002**: The password MUST NOT appear in child process arguments or logs.
- **FR-003**: Token preference, password fallback, cookie-session cleanup, and
  authentication failure behavior MUST remain compatible.
- **FR-004**: Validation MUST use disposable credentials and isolated fixtures.

### Key Entities

- Password: user-provided credential used for the login exchange only.
- Session: existing authenticated cookie state used for later requests.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Successful and failed login tests create zero password files.
- **SC-002**: Credential exposure checks find zero passwords in child arguments.
- **SC-003**: Existing auth preference, fixture, and session checks pass.

## Assumptions

- The existing Linux desktop and CoolerControl authentication contract is retained.
- This change does not alter live settings, restart services, or rotate credentials.
- Bearer-header, cookie, and configured secrets-overlay storage are outside this
  temporary password-transport repair.

## Equivalent helper coverage

Apply the same password transport to the API client, API dump, authentication
check, and password sync helper. Preserve existing netrc host matching and
credential syntax; this repair does not redesign settings or authentication.
