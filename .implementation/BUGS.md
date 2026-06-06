# Known Bugs

## BUG-004 - Test Connection crashes session on invalid credentials

**Status**: Open
**Severity**: High
**Affected**: App Registration Card - Test Connection action

**Symptom**: When credentials are incorrect (wrong App ID, Tenant ID, or Client Secret), clicking Test Connection produces a full-page BC session crash ("Something went wrong") instead of a readable error dialog. Works correctly when credentials are valid.

**Root cause**: The RestClientOAuth library raises errors via `ErrorInfo.Create(message, true)` - collectible errors that bypass `[TryFunction]` entirely. When Entra ID returns a 401, the library re-raises it as a collectible error which cannot be caught at any AL boundary.

**No clean fix available in AL** - this is a constraint of the library's error model. Pre-validating field formats (GUID check on App ID) reduces the chance of a bad credential reaching the library.

---

## BUG-005 - Email address blank on wizard completion screen

**Status**: Open
**Severity**: Low (cosmetic)
**Affected**: Set Up Email wizard - final "Congratulations" page

**Symptom**: Email Address is blank on the wizard completion screen. Displays correctly on the Rate Limit page and in the Email Accounts list.

**Root cause**: `RegisterAccount()` does not set `EmailAccount."Email Address"` on the record it returns. Fix: call `ResolveHomeEmail()` inside `RegisterAccount()` and assign to `EmailAccount."Email Address"`.
