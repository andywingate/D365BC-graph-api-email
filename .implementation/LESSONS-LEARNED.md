# Lessons Learned

## SingleInstance Codeunits and TryFunction - a critical AL constraint

The most significant technical lesson from this project: **`[TryFunction]` cannot reliably catch exceptions thrown from within, or triggered by, a `SingleInstance` codeunit**.

### The flawed approach

The initial architecture used a `SingleInstance` codeunit (`W365 Graph Session`) to cache authenticated `Rest Client` instances per App Registration. The intent was to avoid re-acquiring a token on every send.

When called from a `[TryFunction]`, any exception thrown by the RestClientOAuth library - including the BC outbound HTTP consent dialog appearing mid-call - would bypass the try/catch and crash the entire BC session with "Something went wrong". This affected every interactive action: sending email, testing the connection, even deleting the account.

The key mistake: the RestClientOAuth library raises errors using `ErrorInfo.Create(message, true)` - the second parameter `true` marks the error as a **collectible error**. Collectible errors bypass `[TryFunction]` entirely, regardless of where the try boundary is placed. Combined with a `SingleInstance` codeunit in the call chain, the error had no way to be caught.

Repeated attempts to fix this by wrapping calls in `[TryFunction]` at different levels all failed. The session kept crashing on first use.

### How it was diagnosed

A dedicated **Graph API Diagnostics page** (`W365 Graph Diagnostics`) was built to isolate each step of the send pipeline:

1. **Step 1** - resolve user identity and App Registration from the table directly (no codeunit calls)
2. **Step 2** - build the OAuth stack fresh and call `GET /organization` to prove token acquisition
3. **Step 3** - call `POST /users/{email}/sendMail` with a hardcoded JSON payload

Step 1 ran without error. Step 2 revealed a second issue: `IsolatedStorage.Get` was returning false because the App ID used as the storage key had been entered incorrectly during testing (a stray character). Once the client secret was re-entered, Step 2 returned HTTP 200 from Graph. Step 3 returned HTTP 202 - the send pipeline was proven end-to-end in the diagnostic page before a single line of the connector was changed.

### The fix

All interactive code paths - `Send()`, `TryPingGraph()`, `TrySend()` - were rewritten to be **completely self-contained**: they build the OAuth stack from scratch inside the `[TryFunction]` boundary with no `SingleInstance` codeunit in the call chain at all.

```al
// WRONG - SingleInstance in the try boundary, collectible errors bypass the catch
[TryFunction]
local procedure TrySend(...)
var
    GraphSession: Codeunit "W365 Graph Session";  // SingleInstance
    Client: Codeunit "Rest Client";
begin
    GraphSession.GetRestClient(AppRegCode, Client);  // crash here is uncatchable
    GraphMailMgt.SendEmailMessage(...);
end;

// CORRECT - self-contained, no SingleInstance in the call chain
[TryFunction]
local procedure TrySend(...)
var
    AppReg: Record "W365 App Registration";
    OAuthClientApp: Codeunit "OAuth Client Application KFM";
    // ... all OAuth codeunits declared locally ...
    Client: Codeunit "Rest Client";
begin
    AppReg.Get(AppRegCode);
    AppReg.GetClientSecret(ClientSecret);
    // build OAuth stack fresh every call
    OAuthClientApp.SetClientId(AppReg."App ID");
    // ...
    Client.Initialize(HttpAuthentication);
    GraphMailMgt.SendEmailMessage(...);
end;
```

The `SingleInstance` codeunit is still present in the codebase for cases where it is safe to use (background jobs, non-interactive server-side calls), but it is never called from within a `[TryFunction]` or from any user-triggered action.

### Rule of thumb

> **Never call a `SingleInstance` codeunit from within a `[TryFunction]`, and never call one from any user-triggered action where an exception from a dependency library could surface.**

If you need to cache something for performance, cache it in a non-SingleInstance codeunit and accept the per-request overhead during interactive operations. The BC session survival is more important than token cache efficiency.
