# D365BC-graph-api-email - Graph API Emailing

> **AI-Driven Proof of Concept**
> This project was written almost entirely by GitHub Copilot (Claude Sonnet), with direction and testing by [Andy Wingate](https://github.com/andywingate). Security review and code feedback by [Arend-Jan Kauffmann](https://github.com/ajkauffmann). It is a proof-of-concept. See [.github/instructions/](.github/instructions/) for the full AI context (coding standards and instructions) used throughout development.

An AL extension for Microsoft Dynamics 365 Business Central that lets every user - guest or member - send email from their own work address via the Microsoft Graph API (`Mail.Send`), with zero per-user configuration by admins.

## Dependencies

This extension has a hard dependency on **Rest Client OAuth** by Arend-Jan Kauffmann. Both apps must be installed in BC for this extension to function.

| **App** | **Publisher** | **Source** |
|---|---|---|
| Rest Client OAuth | AJ Kauffmann | [ajkauffmann/RestClientOAuth](https://github.com/ajkauffmann/RestClientOAuth) |

The `Rest Client OAuth` library provides the OAuth 2.0 Authorization Code Grant flow (with PKCE S256), in-memory token handling (`SecretText` only, no persistent storage), and the `Rest Client` wrapper used for all Graph API calls. The dependency is declared in `app.json` and BC will require both PTEs to be deployed together.

## The Problem

Business Central's built-in email connectors do not work cleanly in multi-tenant scenarios:

- **"Current User"** - works only for accounts native to the BC host tenant. Entra B2B guest users have a cross-tenant identity; BC cannot obtain a `Mail.Send` token for them using this connector.
- **Microsoft 365** - guest users cannot use this connector because their identity belongs to a different tenancy.
- **SMTP** - this is often the only viable built-in account choice for guest users, but it comes with two problems: it sends from a separate address or service account rather than the individual's own address. SMTP AUTH is disabled by default in Exchange Online and requires deliberate per-mailbox re-enablement - something Microsoft actively discourages.

The result: guest users have no clean path. The Current User and Microsoft 365 connectors are off-limits due to cross-tenancy identity. In a modern workplace where recipients expect email to come from a real person at a real address, a generic shared sender breaks trust, makes correspondence untraceable, and is simply not what users or customers expect.

## The Solution

This extension implements the **"Current User" pattern** for Microsoft Graph using **delegated permissions** - one logical account, every user sends as themselves, with their own Entra sign-in.

A single email account called **Current User (Microsoft Graph)** is registered with BC's email framework. An admin sets it as the system default once and configures one or more Entra App Registrations (one per user home domain). On the first send in each BC session, the connector triggers an interactive sign-in popup (Authorization Code Grant with PKCE S256) so the user consents to `Mail.Send` on their behalf. Subsequent sends within the same session use the cached delegated token silently.

When any email is sent in BC, the connector decodes the current user's identity, routes to the correct App Registration, and calls `POST /v1.0/users/{email}/sendMail` using the user's own delegated token.

## How it works

```
[BC Email Framework]
       |
       | one account, set as default
       v
[Current User (Microsoft Graph)]
       |
       | reads the sender's home email domain
       v
[App Registration]  <-- matched by Domain Filter (one per tenancy)
       |
       | Authorization Code Grant (PKCE S256) - delegated Mail.Send
       | interactive sign-in popup on first use per session
       v
[POST /v1.0/users/{email}/sendMail]  <-- sends as the user's own address
```

1. You register one **Current User (Microsoft Graph)** email account in BC and set it as the default.
2. You add one **App Registration** in BC for each tenancy you need to send mail from. Each registration holds the Entra App ID, Tenant ID (optional - blank means 'common' for multi-tenant), a Domain Filter (e.g. `contoso.com`), and the client secret.
3. On the first send in a BC session, the user sees a sign-in popup and consents to `Mail.Send` on their behalf.
4. Subsequent sends in the same session use the cached delegated token silently (with automatic silent refresh when the access token expires).

## Setup

These two apps are distributed as source. The high-level flow is below; see [QUICKSTART.md](QUICKSTART.md) for full step-by-step instructions.

1. **Build and install the apps.** Download the source for this extension and the [Rest Client OAuth](https://github.com/ajkauffmann/RestClientOAuth) dependency, build them as PTEs, and install both in your BC environment.
2. **Create the Entra app registrations.** In each tenancy you need to send mail from, create an app registration with `Mail.Send` granted as a **delegated permission**, with user consent or admin consent on behalf of users. Note the App ID, Tenant ID (if restricting to a single home tenant), and a client secret.
3. **Add the email account in BC.** Open **Email Accounts**, choose **New > Set Up Email Account**, and select **Current User (Microsoft Graph)**.
4. **Enter the App Registration details.** Add one App Registration row per tenancy (App ID, Domain Filter, client secret; Tenant ID is optional), then set the account as default.

## Intended use

This extension is designed for BC environments where users are a mix of member users (same tenancy as BC) and guest users (member of a different tenancy, added as B2B guest accounts). The app registrations can be recorded for as many external tenancies as required and the home tenancy. Replacing the use the 'current tenancy only' built in 'Current User' email account type.

### Mixed home-tenancy and B2B guest users

A typical scenario: an organisation runs BC in one Entra tenancy (`tenancy1.com`) but also has users whose identities are homed in a second tenancy (`tenancy2.com`) - added to BC as Entra B2B guests. This is one organisation, one BC environment, but with a multi-tenancy identity landscape. Both groups are active BC users and both need to send email from their own real address, not from a generic shared account.

The setup is a one-time admin task: set **Current User (Microsoft Graph)** as the default email account, then create one App Registration for each home domain. At send time the connector reads the current user's BC identity, decodes their home domain, and routes automatically to the correct App Registration. On first use per session, each user signs in interactively. Subsequent sends are silent.

![Email Accounts - Current User (Microsoft Graph) set as default](docs/images/2026-06-07_10h21_17.png)

*A single account covers all users. BC resolves the correct sender identity at send time.*

![App Registrations - two registrations for two home tenants](docs/images/2026-06-07_10h22_08.png)

*One App Registration per home domain. The Domain Filter on each registration determines which users it applies to. The connector selects the matching registration automatically based on the sending user's home email domain.*

## Known Limitations

- **Delegated (per-user) only.** The Guest Email connector now uses delegated `Mail.Send` with Authorization Code Grant. This means only the authenticated user can send - there is no app-only (background) send path for this connector.
- **Interactive sign-in required on first use per session.** On the first email send of each BC session (or after token expiry), the user will see a Microsoft sign-in popup. This is expected behaviour and cannot be suppressed.
- **Background / automated sends not supported.** Scheduled tasks, posting routines, or any other automated process that sends email cannot use the Guest Email connector because they have no UI context for the interactive sign-in popup. Use the Shared Mailbox connector for automated sends.
- **Refresh token lifetime.** The delegated token is automatically refreshed silently within a session. If a session is idle for more than 90 days, the refresh token expires and the user will need to sign in again.

## Connectors

| Connector | Auth flow | Permission type | Use for |
|---|---|---|---|
| Current User (Microsoft Graph) | Authorization Code Grant (PKCE S256) | Delegated `Mail.Send` | Per-user sends from a user's own address |
| Shared Mailbox | Client Credentials | Application `Mail.Send` | Automated sends from a fixed shared mailbox |

## Acknowledgements

**Arend-Jan Kauffmann** ([ajkauffmann](https://github.com/ajkauffmann)) - security review, code feedback, and architecture guidance. AJ's review identified critical improvements around `SecretText`, `[NonDebuggable]`, `IsolatedStorage` encryption, token lifecycle, and adoption of System Application modules. These are tracked in Phase 3a of the project plan.

OAuth flow architecture patterns were informed by AJ's reference implementation: [ajkauffmann/RestClientOAuth](https://github.com/ajkauffmann/RestClientOAuth).

