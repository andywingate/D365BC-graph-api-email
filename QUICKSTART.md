# Quick Start and Setup Guide

This guide covers everything needed to get the Graph API Emailing extension deployed and working in a Business Central sandbox or production environment.

The extension provides two email connectors:

- **Current User (Microsoft Graph)** - sends email from each user's own home-tenancy address using their own delegated sign-in (Authorization Code Grant with PKCE). One logical account; the connector resolves the sender at runtime from the current user's BC identity. On the first send of each BC session the user sees a Microsoft sign-in popup; subsequent sends in the session are silent.
- **Shared Mailbox (Microsoft Graph)** - sends email from a configured shared mailbox using the OAuth 2.0 Client Credentials (app-only) flow. One account per mailbox, each linked to an App Registration.

## Prerequisites

- Business Central 27 (SaaS or on-prem runtime 16.0+)
- An Azure / Microsoft Entra app registration in each **home tenant** whose users will send email (see Part 1)
- For the Guest connector: `Mail.Send` granted as a **delegated permission** with user or admin consent
- For the Shared Mailbox connector: `Mail.Send` granted as an **application permission** with admin consent
- The AL Language VS Code extension with access to download symbols for your BC environment

---

## Part 1 - Entra App Registration

Create one app registration per user home domain (or one shared registration if all users are in the same tenant). App registrations are created in the [Azure portal](https://portal.azure.com) under **Microsoft Entra ID > App registrations**.

> **Which tenant?** Create the app registration in the **home tenant** of the users who will send email (e.g. `contoso.com`'s Entra ID, not the BC host tenant's Entra ID). The registration needs to be in the tenant that owns the mailboxes.

### Required settings

| **Setting** | **Value** |
|---|---|
| Supported account types | **Accounts in any organizational directory (multitenant)** for B2B guest support, or **Accounts in this organizational directory only** for single-tenant |
| Platform | **Web** |
| Redirect URI | Leave blank or use the default - the `Rest Client OAuth` library uses BC's built-in OAuth landing page automatically |

### API permissions — Guest Email connector (delegated)

Under **API permissions > Add a permission > Microsoft Graph > Delegated permissions**, add:

| **Permission** | **Type** | **Purpose** |
|---|---|---|
| `Mail.Send` | Delegated | Send email as the signed-in user via `/users/{email}/sendMail` |

Click **Grant admin consent for [tenant]** after adding it (or allow users to grant consent themselves if your policy permits). A Global Administrator in that tenant must grant admin consent if user self-consent is not permitted.

> **Why Delegated permission?** The Guest Email connector uses Authorization Code Grant (PKCE S256). The signed-in BC user's identity is used for the OAuth flow, so only delegated permissions are needed. This is less privileged than application permissions because the app can only send as the specific user who has consented.

### API permissions — Shared Mailbox connector (application)

Under **API permissions > Add a permission > Microsoft Graph > Application permissions**, add:

| **Permission** | **Type** | **Purpose** |
|---|---|---|
| `Mail.Send` | Application | Send email as any user in the tenant via `/users/{email}/sendMail` |

Click **Grant admin consent for [tenant]** after adding it.

> **Security note:** `Mail.Send` application permission allows the app to send email as any user in the tenant. Limit who has access to the client secret and audit sends via Microsoft Purview / Exchange message trace. The Guest Email connector's delegated permission is scoped only to the signed-in user.

### Client secret

Under **Certificates & secrets > Client secrets**, click **+ New client secret**. Copy the **Value** immediately - it is only shown once. Store it in a password manager until you paste it into BC.

### Values to note down

From the app registration **Overview** page:

- **Application (Client) ID**
- **Directory (Tenant) ID** *(optional for the Guest connector if using multi-tenant)*

---

## Part 2 - Deploy the Extension

1. Open the workspace in VS Code
2. Ensure your `launch.json` points to the target BC environment
3. Press **F5** (or run **AL: Publish Without Debugging**) to compile and deploy
4. Confirm the extension appears in BC under **Extension Management**

---

## Part 3 - Assign Permissions

Every user who needs to manage setup or who sends email via this connector needs the **Graph API Emailing** permission set.

1. Search BC for **Users** and open each user's card
2. Go to the **User Permission Sets** section
3. Add a row: **Permission Set** = `W365 GUEST EMAIL`

---

## Part 4 - Create App Registrations in BC

App Registrations in BC are the bridge between the extension and the Entra app registrations created in Part 1. Create one BC App Registration row for each Entra app registration.

1. Search BC for **Email Accounts** and open the page
2. Click **New > Set Up Email Account** and select **Current User (Microsoft Graph)** - this opens the **App Registrations** list
3. Alternatively, if the account already exists, select it and click **View Details** > **App Registrations**

In the **App Registrations** list:

4. Click **New** to open the **App Registration** card
5. Fill in the fields:

| **Field** | **Value** |
|---|---|
| Code | Short identifier, e.g. `CONTOSO` |
| Description | Friendly name, e.g. `Contoso home tenant` |
| App (Client) ID | Application ID from the Azure portal |
| Tenant ID | Directory ID from the Azure portal. **Leave blank** to use `common` (multi-tenant, enables B2B guest sign-in). Set to a specific tenant GUID to restrict sign-in to one home tenant. |
| Domain Filter | The home email domain of users this registration covers, e.g. `contoso.com`. Required and must be unique across all registrations. |
| Redirect URI | Optional. The `Rest Client OAuth` library uses BC's built-in OAuth redirect automatically; this field is for reference only. |

6. In the **Client Secret** section, paste the client secret value into **Enter New Client Secret** and press Tab or Enter. The value is stored encrypted and cannot be read back. **Client Secret Status** changes to **Configured**.

7. Click **Test Connection (Shared Mailbox)** to verify the Client Credentials (app-only) connection. This action is only relevant for the Shared Mailbox connector. The Guest Email connector tests its delegated connection on the first email send (interactive sign-in popup).

8. Repeat steps 4-7 for each additional home domain.

---

## Part 5 - Configure Current User (Microsoft Graph)

The **Current User (Microsoft Graph)** connector appears as a single account in Email Accounts once at least one App Registration exists.

1. Search BC for **Email Accounts**
2. Select **Current User (Microsoft Graph)** and click **Set as Default** if this should be the default account for all sends
3. Click **Send Test Email** - on first use you will see a Microsoft sign-in popup to authorise the delegated `Mail.Send` permission

No per-user setup is required. Every user who sends from BC will automatically have their home domain matched to the correct App Registration at send time. Each user will see the sign-in popup on their first send of each BC session.

### How domain matching works

When a user sends an email, the connector:

1. Reads the user's **Authentication Email** from their BC User record
2. Decodes the home domain (B2B guest format `user_contoso.com#EXT#@host.onmicrosoft.com` becomes `contoso.com`; member format `user@contoso.com` becomes `contoso.com`)
3. Finds the App Registration whose **Domain Filter** matches that domain
4. Triggers the delegated Authorization Code Grant flow (sign-in popup on first use per session)
5. Calls `POST /v1.0/users/{userEmail}/sendMail` using the user's delegated token

---

## Part 6 - Configure Shared Mailbox (Microsoft Graph)

The **Shared Mailbox (Microsoft Graph)** connector supports one or more shared mailboxes. Each mailbox is a separate Email Account in BC, linked to an App Registration.

> **Entra setup required:** The App Registration used for a shared mailbox must have `Mail.Send` **application** permission with admin consent in the tenant that owns the mailbox. The Shared Mailbox connector uses Client Credentials (app-only) and requires a specific Tenant ID to be set on the App Registration.

### Create a shared mailbox account

1. Search BC for **Email Accounts** and click **New > Set Up Email Account**
2. Select **Shared Mailbox (Microsoft Graph)** and click **Next** - the **Shared Mailbox Accounts** list opens
3. Click **New** to open the **Shared Mailbox Account** card
4. Fill in the fields:

| **Field** | **Value** |
|---|---|
| Code | Short identifier, e.g. `SALES` |
| Display Name | Name shown in Email Accounts, e.g. `Sales Mailbox` |
| Mailbox Email | The SMTP address of the shared mailbox, e.g. `sales@contoso.com` |
| App Registration | Select the App Registration from Part 4 that covers this mailbox's tenant |
| Description | Optional free-text description |

5. Close the card. Back in the **Shared Mailbox Accounts** list, the new mailbox appears.
6. Close the list. The wizard returns to Email Accounts where the new account is now listed.
7. Select the account and click **Send Test Email** to verify.

### Assign to Email Scenarios (optional)

1. Search BC for **Email Scenarios**
2. Assign the shared mailbox account to the relevant scenario (e.g. **Sales - Invoice** routes through `sales@contoso.com`)

---

## Part 7 - Email Scenarios

Both connectors integrate fully with BC's Email Scenarios.

1. Search BC for **Email Scenarios**
2. Assign the **Current User (Microsoft Graph)** account as the default account for user-driven sends, or assign individual scenarios to whichever account is appropriate
3. Assign shared mailbox accounts to automated scenarios (background jobs, scheduled reports) that should come from a fixed address

> **Important:** The Current User (Microsoft Graph) connector requires an interactive user session. Do **not** assign it to automated or background scenarios - use the Shared Mailbox connector for those instead.

---

## Troubleshooting

| **Symptom** | **Likely cause** | **Resolution** |
|---|---|---|
| "No App Registration found for your account" | User's home domain has no matching Domain Filter | Create an App Registration with a Domain Filter matching the user's domain |
| "No client secret is configured for App Registration" | Secret was not stored or was stored against a different App Registration | Open the App Registration card and re-enter the client secret |
| Sign-in popup appears on every send | Token not being cached between sends | Expected behaviour if BC session variables are cleared; the token is cached for the duration of the BC session |
| Sign-in popup cancelled / "The authorization was canceled" | User dismissed the popup | User must complete the sign-in to send email |
| "Microsoft Graph returned HTTP 401" | Wrong credentials or consent not granted | Check the Azure portal - confirm `Mail.Send` delegated permission has consent. Re-enter the client secret. |
| "Microsoft Graph returned HTTP 403" | Admin consent not granted for delegated permission | In Azure portal > app registration > API permissions, grant admin consent or ask users to grant user consent |
| "Microsoft Graph returned HTTP 404 on sendMail" | User's Authentication Email is empty or malformed in BC | Check the user's BC record: **Users** > open user > **Authentication Email** must contain a valid email address |
| Email arrives from wrong address | User's BC Authentication Email does not match their actual mailbox | Verify the user's **Authentication Email** in BC matches their home-tenancy email address |
| Shared mailbox account does not appear in Email Accounts | No Shared Mailbox Account records exist | Complete Part 6 to create at least one shared mailbox account |
| Test Connection (Shared Mailbox) fails with "invalid_client" | Wrong client secret | Delete and re-enter the client secret on the App Registration card |
| Test Connection fails with "Tenant ID is required" | Tenant ID blank on App Registration used for Shared Mailbox | Enter the Directory (Tenant) ID for the Shared Mailbox connector's App Registration |
