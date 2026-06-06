# Quick Start and Setup Guide

This guide covers everything needed to get the Graph API Emailing extension deployed and working in a Business Central sandbox or production environment.

The extension provides two email connectors:

- **Current User (Microsoft Graph)** - sends email from each user's own home-tenancy address. One logical account; the connector resolves the sender at runtime from the current user's BC identity.
- **Shared Mailbox (Microsoft Graph)** - sends email from a configured shared mailbox. One account per mailbox, each linked to an App Registration.

Both use the OAuth 2.0 Client Credentials (app-only) flow. No per-user consent steps are required.

## Prerequisites

- Business Central 27 (SaaS or on-prem runtime 16.0+)
- An Azure / Microsoft Entra app registration in each **home tenant** whose users will send email (see Part 1)
- `Mail.Send` granted as an **application permission** with admin consent on each app registration
- The AL Language VS Code extension with access to download symbols for your BC environment

---

## Part 1 - Entra App Registration

Create one app registration per user home domain (or one shared registration if all users are in the same tenant). App registrations are created in the [Azure portal](https://portal.azure.com) under **Microsoft Entra ID > App registrations**.

> **Which tenant?** Create the app registration in the **home tenant** of the users who will send email (e.g. `contoso.com`'s Entra ID, not the BC host tenant's Entra ID). The registration needs to be in the tenant that owns the mailboxes.

### Required settings

| **Setting** | **Value** |
|---|---|
| Supported account types | **Accounts in this organizational directory only** (single tenant) |
| Platform | Web (for the Redirect URI field) |
| Redirect URI | `https://businesscentral.dynamics.com/OAuthLanding.htm` (not used for auth, but required by some Entra validation) |

### API permissions

Under **API permissions > Add a permission > Microsoft Graph > Application permissions**, add:

| **Permission** | **Type** |
|---|---|
| `Mail.Send` | Application |

Click **Grant admin consent for [tenant]** after adding it. The button must be clicked by a Global Administrator in that tenant.

> **Why Application permission?** This connector uses Client Credentials (app-only) authentication. There is no signed-in user in the OAuth flow - the app authenticates as itself and sends on behalf of users via `/v1.0/users/{email}/sendMail`. This requires an Application permission with admin consent, not a Delegated permission.

> **Security note:** `Mail.Send` application permission allows the app to send email as any user in the tenant. Limit who has access to the client secret and audit sends via Microsoft Purview / Exchange message trace.

### Client secret

Under **Certificates & secrets > Client secrets**, click **+ New client secret**. Copy the **Value** immediately - it is only shown once. Store it in a password manager until you paste it into BC.

### Values to note down

From the app registration **Overview** page:

- **Application (Client) ID**
- **Directory (Tenant) ID**

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
| Tenant ID | Directory ID from the Azure portal |
| Domain Filter | The home email domain of users this registration covers, e.g. `contoso.com`. This value is required. |
| Is Default | Optional marker field (not used by runtime routing in the current implementation) |
| Redirect URI | `https://businesscentral.dynamics.com/OAuthLanding.htm` |

6. In the **Client Secret** section, paste the client secret value into **Enter New Client Secret** and press Tab or Enter. The value is stored encrypted and cannot be read back. **Client Secret Status** changes to **Configured**.

7. Click **Test Connection** to verify the app registration can acquire a token from Graph. A success message confirms the setup.

8. Repeat steps 4-7 for each additional home domain.

---

## Part 5 - Configure Current User (Microsoft Graph)

The **Current User (Microsoft Graph)** connector appears as a single account in Email Accounts once at least one App Registration exists.

1. Search BC for **Email Accounts**
2. Select **Current User (Microsoft Graph)** and click **Set as Default** if this should be the default account for all sends
3. Click **Send Test Email** to confirm Graph accepts sends from the current user's identity

No per-user setup is required. Every user who sends from BC will automatically have their home domain matched to the correct App Registration at send time.

### How domain matching works

When a user sends an email, the connector:

1. Reads the user's **Authentication Email** from their BC User record
2. Decodes the home domain (B2B guest format `user_contoso.com#EXT#@host.onmicrosoft.com` becomes `contoso.com`; member format `user@contoso.com` becomes `contoso.com`)
3. Finds the App Registration whose **Domain Filter** matches that domain
4. Calls `POST /v1.0/users/{userEmail}/sendMail` using Client Credentials from that registration

---

## Part 6 - Configure Shared Mailbox (Microsoft Graph)

The **Shared Mailbox (Microsoft Graph)** connector supports one or more shared mailboxes. Each mailbox is a separate Email Account in BC, linked to an App Registration.

> **Entra setup required:** The App Registration used for a shared mailbox must also have `Mail.Send` application permission with admin consent in the tenant that owns the mailbox. You can reuse an App Registration created in Part 1 if it is in the correct tenant.

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

---

## Troubleshooting

| **Symptom** | **Likely cause** | **Resolution** |
|---|---|---|
| "No App Registration found for your account" | User's home domain has no matching Domain Filter | Create an App Registration with a Domain Filter matching the user's domain |
| "No client secret is configured for App Registration" | Secret was not stored or was stored against a different App Registration | Open the App Registration card and re-enter the client secret |
| "Microsoft Graph returned HTTP 401" | App ID, Tenant ID, or client secret is wrong; or admin consent has not been granted | Check the Azure portal - confirm the app registration exists in the correct tenant and `Mail.Send` application permission has admin consent. Re-enter the client secret. |
| "Microsoft Graph returned HTTP 403" | Admin consent not granted | In Azure portal > app registration > API permissions, click **Grant admin consent** |
| "Microsoft Graph returned HTTP 404 on sendMail" | User's Authentication Email is empty or malformed in BC | Check the user's BC record: **Users** > open user > **Authentication Email** must contain a valid email address |
| Email arrives from wrong address | User's BC Authentication Email does not match their actual mailbox | Verify the user's **Authentication Email** in BC matches their home-tenancy email address |
| Shared mailbox account does not appear in Email Accounts | No Shared Mailbox Account records exist | Complete Part 6 to create at least one shared mailbox account |
| Test Connection fails with "invalid_client" | Wrong client secret | Delete and re-enter the client secret on the App Registration card |
