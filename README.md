# D365BC-graph-api-email - Graph API Emailing

> **AI-Driven Proof of Concept**
> This project was written almost entirely by GitHub Copilot (Claude Sonnet), with direction and testing by [Andy Wingate](https://github.com/andywingate). Security review and code feedback by [Arend-Jan Kauffmann](https://github.com/ajkauffmann). It is a proof-of-concept. See [.github/instructions/](.github/instructions/) for the full AI context (coding standards and instructions) used throughout development.

An AL extension for Microsoft Dynamics 365 Business Central that lets every user - guest or member - send email from their own work address via the Microsoft Graph API (`Mail.Send`), with zero per-user configuration by admins.

## Dependencies

This extension has a hard dependency on **Rest Client OAuth** by Arend-Jan Kauffmann. Both apps must be installed in BC for this extension to function.

| **App** | **Publisher** | **Source** |
|---|---|---|
| Rest Client OAuth | AJ Kauffmann | [ajkauffmann/RestClientOAuth](https://github.com/ajkauffmann/RestClientOAuth) |

The `Rest Client OAuth` library provides the OAuth 2.0 Client Credentials flow, in-memory token handling (`SecretText` only, no persistent storage), and the `Rest Client` wrapper used for all Graph API calls. The dependency is declared in `app.json` and BC will require both PTEs to be deployed together.

## The Problem

Business Central's built-in email connectors do not work cleanly in multi-tenant scenarios:

- **"Current User"** - works only for accounts native to the BC host tenant. Entra B2B guest users have a cross-tenant identity; BC cannot obtain a `Mail.Send` token for them using this connector.
- **Microsoft 365** - guest users cannot use this connector because their identity belongs to a different tenancy.
- **SMTP** - this is often the only viable built-in account choice for guest users, but it comes with two problems: it sends from a separate address or service account rather than the individual's own address. SMTP AUTH is disabled by default in Exchange Online and requires deliberate per-mailbox re-enablement - something Microsoft actively discourages.

The result: guest users have no clean path. The Current User and Microsoft 365 connectors are off-limits due to cross-tenancy identity. In a modern workplace where recipients expect email to come from a real person at a real address or on-behalf from a shared M365 mailbox, a generic shared sender breaks trust, makes correspondence untraceable, and is simply not what users or customers expect.

## The Solution

This extension implements the **"Current User" pattern** for Microsoft Graph - one logical account, every user sends as themselves.

A single email account called **Current User (Microsoft Graph)** is registered with BC's email framework. An admin sets it as the system default once and configures one or more Entra App Registrations (one per user home domain). After that, every send is fully automatic: the connector resolves the user's home domain from their BC identity at send time, selects the matching App Registration, and calls Graph using application-level (client credentials) authentication. No per-user consent flow, no token management per user, no admin action per send.

When any email is sent in BC - compose dialog, customer statements, scheduled reports, background jobs, ISV extensions - the connector decodes the current user's identity, routes to the correct App Registration, and calls `POST /v1.0/users/{email}/sendMail` using client credentials with the app's `Mail.Send` application permission (not delegated).

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
       | authenticates app-only against that tenancy
       v
[POST /v1.0/users/{email}/sendMail]  <-- sends as the user's own address
```

1. You register one **Current User (Microsoft Graph)** email account in BC and set it as the default.
2. You add one **App Registration** in BC for each tenancy you need to send mail from. Each registration holds the Entra App ID, Tenant ID, a Domain Filter (e.g. `contoso.com`), and the client secret.
3. When a user sends email, the connector reads their home email domain, finds the App Registration whose Domain Filter matches, and sends as that user's own address.

There is no per-user consent, no token to manage, and no admin action per user. Adding a new tenancy is a single App Registration row.

## Setup

These two apps are distributed as source. The high-level flow is below; see [QUICKSTART.md](QUICKSTART.md) for full step-by-step instructions.

1. **Build and install the apps.** Download the source for this extension and the [Rest Client OAuth](https://github.com/ajkauffmann/RestClientOAuth) dependency, build them as PTEs, and install both in your BC environment.
2. **Create the Entra app registrations.** In each tenancy you need to send mail from, create an app registration with two **application permissions** granted and admin consent given: `Mail.Send` (to send email) and `Organization.Read.All` (used by the Test Connection check). Note the App ID, Tenant ID, and a client secret.
3. **Add the email account in BC.** Open **Email Accounts**, choose **New > Set Up Email Account**, and select **Current User (Microsoft Graph)**.
4. **Enter the App Registration details.** Add one App Registration row per tenancy (App ID, Tenant ID, Domain Filter, client secret), then set the account as default.

## Intended use

This extension is designed for BC environments where users are a mix of member users (same tenancy as BC) and guest users (member of a different tenancy, added as B2B guest accounts). The app registrations can be recorded for as many external tenancies as required and the home tenancy. Replacing the use the 'current tenancy only' built in 'Current User' email account type.

### Mixed home-tenancy and B2B guest users

A typical scenario: an organisation runs BC in one Entra tenancy (`tenancy1.com`) but also has users whose identities are homed in a second tenancy (`tenancy2.com`) - added to BC as Entra B2B guests. This is one organisation, one BC environment, but with a multi-tenancy identity landscape. Both groups are active BC users and both need to send email from their own real address, not from a generic shared account.

The setup is a one-time admin task: set **Current User (Microsoft Graph)** as the default email account, then create one App Registration for each home domain. At send time the connector reads the current user's BC identity, decodes their home domain, and routes automatically to the correct App Registration. Users from tenancy1 send as `user@tenancy1.com`; users from tenancy2 send as `user@tenancy2.com`. No routing flags, no per-user configuration, no admin action per user.

![Email Accounts - Current User (Microsoft Graph) set as default](docs/images/2026-06-07_10h21_17.png)

*A single account covers all users. BC resolves the correct sender identity at send time.*

![App Registrations - two registrations for two home tenants](docs/images/2026-06-07_10h22_08.png)

*One App Registration per home domain. The Domain Filter on each registration determines which users it applies to. The connector selects the matching registration automatically based on the sending user's home email domain.*

## Acknowledgements

**Arend-Jan Kauffmann** ([ajkauffmann](https://github.com/ajkauffmann)) - security review, code feedback, and architecture guidance. AJ's review identified critical improvements around `SecretText`, `[NonDebuggable]`, `IsolatedStorage` encryption, token lifecycle, and adoption of System Application modules. These are tracked in Phase 3a of the project plan.

OAuth flow architecture patterns were informed by AJ's reference implementation: [ajkauffmann/RestClientOAuth](https://github.com/ajkauffmann/RestClientOAuth).
