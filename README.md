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

- **"Current User"** (built-in) - works only for accounts native to the BC host tenant. Entra B2B guest users have a cross-tenant identity; BC cannot obtain a `Mail.Send` token for them using this connector.
- **Microsoft 365 / SMTP** - sends from a shared mailbox or service account, not from the individual user's own address. For guest users this means either email is not sent at all, or it arrives from a generic address that has no meaning to the recipient.

The result: guest users in BC either cannot send email, or their email arrives from the wrong address - causing confusion for customers, poor traceability, and broken workflows.

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

This extension is designed for BC environments where users belong to multiple home tenants - for example, a business that has invited users from another organisation as Entra B2B guests. It also works where all users share a single home tenant; one App Registration with the Domain Filter set to that tenant's domain covers that case.

### Mixed home-tenancy and B2B guest users

A typical scenario: a business runs BC in their own Entra tenancy (`contoso.onmicrosoft.com`). They also work closely with a supplier or partner organisation and have invited those users into BC as Entra B2B guests (signing in from `supplier.com`). Both groups are active BC users and both need to send email - customer correspondence, statements, notifications - from their own real email address, not from a generic shared account.

The setup is a one-time admin task: set **Current User (Microsoft Graph)** as the default email account, then create one App Registration for each home domain. At send time the connector reads the current user's BC identity, decodes their home domain, and routes automatically to the correct App Registration. Internal users send as `user@contoso.onmicrosoft.com`; B2B guests send as `user@supplier.com`. No routing flags, no per-user configuration, no admin action per user.

![Email Accounts - Current User (Microsoft Graph) set as default](docs/images/2026-06-07_10h21_17.png)

*A single account covers all users. BC resolves the correct sender identity at send time.*

![App Registrations - two registrations for two home tenants](docs/images/2026-06-07_10h22_08.png)

*One App Registration per home domain. The Domain Filter on each registration determines which users it applies to. The connector selects the matching registration automatically based on the sending user's home email domain.*

`Mail.Send` only. Reply, inbox retrieval, and folder management are not implemented.

## Acknowledgements

**Arend-Jan Kauffmann** ([ajkauffmann](https://github.com/ajkauffmann)) - security review, code feedback, and architecture guidance. AJ's review identified critical improvements around `SecretText`, `[NonDebuggable]`, `IsolatedStorage` encryption, token lifecycle, and adoption of System Application modules. These are tracked in Phase 3a of the project plan.

OAuth flow architecture patterns were informed by AJ's reference implementation: [ajkauffmann/RestClientOAuth](https://github.com/ajkauffmann/RestClientOAuth).
