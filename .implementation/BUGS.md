# Known Bugs

## BUG-004 - Test Connection crashes session on invalid credentials

**Status**: Open  
**Severity**: High  
**Affected**: W365AppRegistrationCard - Test Connection action  

**Symptom**: When credentials are incorrect (wrong App ID, Tenant ID, or Client Secret), clicking Test Connection produces a full-page BC session crash ("Something went wrong") instead of a readable error dialog.  

**Reproduced**: Intentionally added a character to App (Client) ID on the VSG registration. Test Connection crashed at 14:55:25 GMT, Operation: 0bce691c3ef84c1faab1588444dcf9fd.  

**Root cause hypothesis**: The RestClientOAuth library raises errors via `ErrorInfo.Create(..., true)` (collectible/callstack errors). These bypass `[TryFunction]` under certain conditions - specifically when the token request itself returns an HTTP error (e.g., 401 unauthorized from Entra ID). The `TryPingGraph` function catches the case where the HTTP call cannot be made at all, but not the case where Entra ID responds with an error that the library then re-raises as a collectible ErrorInfo.  

**Context**: Same class of problem as the original send crash (BUG fixed earlier today). Test Connection works correctly when credentials are valid. The `[TryFunction]` in `W365GraphMailMgt.TryPingGraph` is not sufficient to catch all error paths from the library.  

**Fix approach (when ready)**: Investigate whether `ErrorInfo.Collectible` errors can be caught with a different AL pattern, or whether the token acquisition needs to be pre-validated before calling the library (e.g., manually checking the token endpoint response before passing to RestClientOAuth).

---

## BUG-001 - Domain routing: Is Default concept may cause ambiguity

**Status**: Deferred  
**Severity**: Medium  
**Affected**: W365AppRegistration table, W365AppRegistrations list  

**Symptom**: If no App Registration has a Domain Filter matching the current user's home domain, the fallback to Is Default may silently use the wrong registration. The Is Default toggle on the card is also confusing UX.  

**Fix approach (when ready)**: Make Domain Filter mandatory (NotBlank). Remove Is Default concept - admin must explicitly set a domain filter per registration. Schema change requires care if sandbox has existing data.

---

## BUG-002 - Delete App Registration crashes if cached session exists

**Status**: Open  
**Severity**: Low  
**Affected**: W365AppRegistrations list - Delete action  

**Symptom**: Deleting an App Registration record while the SingleInstance codeunit holds a cached Rest Client for that code causes a crash.  

**Fix approach**: Call `GraphSession.ClearSession(Rec.Code)` in an OnDelete trigger on the table, or show a Message and prevent deletion if a session is active.

---

## BUG-003 - RESOLVED

`#EXT#` UPN decoded to real home email in both Email Accounts display and Graph sendMail endpoint. Fixed 2026-06-06 using local `ResolveHomeEmail` procedure in W365GuestEmailConnector (no SingleInstance reference).
