# Known Bugs

## BUG-005 - Email address blank on wizard completion screen

**Status**: Open
**Severity**: Low
**Affected**: Set Up Email wizard - final "Congratulations" page

**Symptom**: The Email Address field on the wizard completion screen is blank. The same address displays correctly on the Rate Limit page and in the Email Accounts list.

**Root cause**: `RegisterAccount()` sets `Account Id`, `Name`, and `Connector` on the returned `EmailAccount` record but does not set `EmailAddress`. The wizard completion page reads directly from that record before `GetAccounts()` populates it. Fix: call `ResolveHomeEmail()` inside `RegisterAccount()` and assign it to `EmailAccount."Email Address"`.

**Impact**: Cosmetic only - email sends correctly, the address appears on all other screens.

---

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

## BUG-001 - RESOLVED

Domain Filter is now mandatory and must be unique per App Registration. Is Default concept removed from table logic, card page, and list page. `ResolveForDomain()` matches on Domain Filter only - no fallback. Fixed 2026-06-06.

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
