# Secret Service integration coverage

Scope: explicitly saving the entered provider key to the system keyring. No new
AI backend or provider protocol is integrated. Existing read precedence remains.

| Operation | Implementation | Verification |
|---|---|---|
| Search matching app/provider items | SearchItems across collections | Existing-item replacement and lookup tests |
| Find default collection for new key | ReadAlias(default) | New key and missing-alias tests |
| Unlock matching items/collection | Unlock, including returned prompt | Immediate completion, refusal, dismissal and timeout tests |
| Open a secret session | OpenSession(plain) | Read/write session and error tests |
| Create scoped item | CreateItem with matching attributes and replace=true | Write/read round-trip and creation prompt tests |
| Update existing scoped credentials | SetSecret for matched items | Replacement without duplicate test |
| Complete or abandon prompt | Prompt/Completed/Dismiss | Immediate reply, dismissal, timeout and malformed-signal tests |
| Release resources | Session.Close and client/subscription teardown | Success/failure cleanup assertions; close-refusal tests |

Collection management and credential deletion are outside the requested add/set
flow. Missing default keyring returns an actionable inline failure. No plaintext
storage fallback is introduced.
