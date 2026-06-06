# D365BC-graph-api-email - Graph API Emailing

> **AI-Driven Proof of Concept**
> This project was written almost entirely by GitHub Copilot (Claude Sonnet), with direction and testing by [Andy Wingate](https://github.com/andywingate). Security review and code feedback by [Arend-Jan Kauffmann](https://github.com/ajkauffmann). It is a proof-of-concept. See [.github/instructions/](.github/instructions/) for the full AI context (coding standards and instructions) used throughout development.

An AL extension for Microsoft Dynamics 365 Business Central that lets every user - guest or member - send email from their own work address via the Microsoft Graph API (`Mail.Send`), with zero per-user configuration by admins.

## The Problem

Business Central's built-in email connectors do not work cleanly in multi-tenant scenarios:

- **"Current User"** (built-in) - works only for accounts native to the BC host tenant. Entra B2B guest users have a cross-tenant identity; BC cannot obtain a `Mail.Send` token for them using this connector.
- **Microsoft 365 / SMTP** - sends from a shared mailbox or service account, not from the individual user's own address. For guest users this means either email is not sent at all, or it arrives from a generic address that has no meaning to the recipient.

The result: guest users in BC either cannot send email, or their email arrives from the wrong address - causing confusion for customers, poor traceability, and broken workflows.

## The Solution

This extension implements the **"Current User" pattern** for Microsoft Graph - one logical account, every user sends as themselves.

A single email account called **Current User Email API** is registered with BC's email framework. An admin sets it as the system default **once**. After that, every user who completes a one-time OAuth consent flow can send email from BC using their own home-tenancy address - whether they are a guest (`user@partner.com`) or a member of the host tenant.

When any email is sent in BC - compose dialog, customer statements, scheduled reports, background jobs, ISV extensions - the connector resolves the correct Graph token for the current user at send time using `UserSecurityId()`. No per-user account management, no routing flags, no admin action per user.

## Architecture

```
[BC Email Framework]
       |
       | sets as default once
       v
[Current User Email API]  <-- single fixed-GUID account
       |
       | at send time, looks up token for UserSecurityId()
       v
[W365 User Email Token]  <-- one row per user, DataScope::User
       |
       | calls Graph with delegated token
       v
[POST /v1.0/me/sendMail]  <-- sends as the user's home-tenancy identity
```

### Key components

| Component | Purpose |
|---|---|
| `W365 Guest Email Connector` | Implements `Email Connector`, `Email Connector v4`, `Default Email Rate Limit`. `GetAccounts()` returns one fixed-GUID account. `Send()` resolves the current user's token at runtime. |
| `W365 OAuth Mgt` | Authorization Code + PKCE flow. Exchanges the auth code for access/refresh tokens and stores them in `IsolatedStorage` (per-user scope). Handles silent refresh before expiry. |
| `W365 Graph Mail Mgt` | Calls `POST /v1.0/me/sendMail` and `GET /me` (to fetch the user's real home email address after consent). |
| `W365 User Email Token` | One row per user. Stores consent status, token expiry, and the user's home email address. Keyed by `User Name`. |
| `W365 OAuth Consent` page | The consent page users complete once. Opens a sign-in popup using PKCE; on return stores the token. |
| `W365 Email Setup` | Admin-only setup card. Stores Entra App ID, Host Tenant ID, and Redirect URI. Client secret stored separately in `IsolatedStorage` (company scope). |

### Token model

- Tokens are stored in `IsolatedStorage` with `DataScope::User` - each user's token is private to them and cannot be accessed by other users or by background tasks running as a different identity.
- Access tokens are refreshed silently before expiry using the stored refresh token. Users do not need to re-consent unless they explicitly disconnect or the refresh token is revoked by an admin.
- The `Home Email` field on `W365 User Email Token` stores the user's real address from `GET /me`, populated at consent time. This is what BC displays in the Email Accounts page and in the compose dialog "From" field.

## Setup

See [QUICKSTART.md](QUICKSTART.md) for full step-by-step instructions. The short version:

1. Create an Entra app registration with `Mail.Send` delegated permission
2. Deploy this extension to BC
3. Open **W365 Email Setup** and enter the app registration details
4. Open **Email Accounts**, find **Current User Email API**, and click **Set as Default**
5. Each user opens the **Connect Current User Email API** page and completes the one-time consent popup

## Intended use

This extension is designed for BC environments where most or all users are Entra B2B guests - for example, a BC tenant hosted by a partner or shared services organisation where end-users sign in from their own company accounts. It also works for member accounts in the host tenant; the OAuth flow is the same regardless of guest status.

Phase 1 (this release) covers `Mail.Send` only. Reply, inbox retrieval, and folder management are not implemented.

## Known limitations

- **Single app registration only** - `W365 Email Setup` stores one Entra App ID and one Host Tenant ID. All users must authenticate against the same app registration. Environments where users belong to multiple home tenants that each require a separate app registration are not supported in Phase 1. Multi-tenancy support (row-based setup with per-domain or per-tenant-ID registration selection) is planned for Phase 3.

## Lessons Learned

### SingleInstance Codeunits and TryFunction - a critical AL constraint

The most significant technical lesson from this project: **`[TryFunction]` cannot reliably catch exceptions thrown from within, or triggered by, a `SingleInstance` codeunit**.

#### The flawed approach

The initial architecture used a `SingleInstance` codeunit (`W365 Graph Session`) to cache authenticated `Rest Client` instances per App Registration. The intent was to avoid re-acquiring a token on every send.

When called from a `[TryFunction]`, any exception thrown by the RestClientOAuth library - including the BC outbound HTTP consent dialog appearing mid-call - would bypass the try/catch and crash the entire BC session with "Something went wrong". This affected every interactive action: sending email, testing the connection, even deleting the account.

The key mistake: the RestClientOAuth library raises errors using `ErrorInfo.Create(message, true)` - the second parameter `true` marks the error as a **collectible error**. Collectible errors bypass `[TryFunction]` entirely, regardless of where the try boundary is placed. Combined with a `SingleInstance` codeunit in the call chain, the error had no way to be caught.

Repeated attempts to fix this by wrapping calls in `[TryFunction]` at different levels all failed. The session kept crashing on first use.

#### How it was diagnosed

A dedicated **Graph API Diagnostics page** (`W365 Graph Diagnostics`) was built to isolate each step of the send pipeline:

1. **Step 1** - resolve user identity and App Registration from the table directly (no codeunit calls)
2. **Step 2** - build the OAuth stack fresh and call `GET /organization` to prove token acquisition
3. **Step 3** - call `POST /users/{email}/sendMail` with a hardcoded JSON payload

Step 1 ran without error. Step 2 revealed a second issue: `IsolatedStorage.Get` was returning false because the App ID used as the storage key had been entered incorrectly during testing (a stray character). Once the client secret was re-entered, Step 2 returned HTTP 200 from Graph. Step 3 returned HTTP 202 - the send pipeline was proven end-to-end in the diagnostic page before a single line of the connector was changed.

#### The fix

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

#### Rule of thumb

> **Never call a `SingleInstance` codeunit from within a `[TryFunction]`, and never call one from any user-triggered action where an exception from a dependency library could surface.**

If you need to cache something for performance, cache it in a non-SingleInstance codeunit and accept the per-request overhead during interactive operations. The BC session survival is more important than token cache efficiency.

---

## Acknowledgements

**Arend-Jan Kauffmann** ([ajkauffmann](https://github.com/ajkauffmann)) - security review, code feedback, and architecture guidance. AJ's review identified critical improvements around `SecretText`, `[NonDebuggable]`, `IsolatedStorage` encryption, token lifecycle, and adoption of System Application modules. These are tracked in Phase 3a of the project plan.

OAuth flow architecture patterns were informed by AJ's reference implementation: [ajkauffmann/RestClientOAuth](https://github.com/ajkauffmann/RestClientOAuth).
