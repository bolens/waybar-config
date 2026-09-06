# Data model

The existing user/password strings form an in-memory netrc payload scoped to
`127.0.0.1` and `localhost`. It is passed only to the login subprocess.
Successful login retains the existing private cookie directory until client close.
Rejected login, status failure, and exceptions clean up that directory as before.
No persistent schema changes are required.
