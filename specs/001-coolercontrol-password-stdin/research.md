# Research

## Decision

Use subprocess stdin and curl's existing `--netrc-file` option with the Linux
`/dev/stdin` descriptor path. Preserve the existing netrc host entries and
password encoding so the fix changes transport rather than account scope.

## Rationale

The current helper writes the password to `TemporaryDirectory()/netrc`.
Directory permissions reduce access but do not remove the on-disk copy.
A pipe delivers the same login data without creating a credential file or putting
its contents in argv. Curl documents an explicit path for `--netrc-file`:
<https://curl.se/docs/manpage.html#--netrc-file>.

## Alternatives considered

- Passing `--user user:password`: exposes credentials in argv.
- Encrypting the file: curl needs plaintext and this introduces key handling.
- `--config -`: needs a different quoting and host-scoping contract for credentials.

Independent transport review and a real-curl fixture verify the chosen approach.
