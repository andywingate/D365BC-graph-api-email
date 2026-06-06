# Testing Guide

Manual sandbox test paths for the Graph API Emailing extension.

## Pre-test Checklist

- Extension deployed to sandbox
- App Registration created in Azure portal with `Mail.Send` application permission and admin consent granted
- App Registration configured in BC (App Registrations list) with valid App ID, Tenant ID, Domain Filter, and client secret
- Test user is a B2B guest (Authentication Email contains `#EXT#`)

---

## Path 1 - App Registration Setup

**Goal:** Confirm App Registration saves correctly and validates input.

1. Open **Email Accounts**, select **Current User (Microsoft Graph)**, click the account to drill in
2. Click **App Registrations** from the account card
3. Click **New** - card opens
4. Enter a Code (e.g. `VSG`) and Description
5. Enter App (Client) ID as a valid GUID
6. Enter Tenant ID
7. Enter Domain Filter (e.g. `contoso.com`)
8. Enter client secret in **Enter New Client Secret** and Tab out

**Expected:**
- Client Secret Status shows **Configured**
- All fields persist on save

**Validation tests:**
- Enter a non-GUID in App (Client) ID and Tab out - error: "App (Client) ID must be a valid GUID"
- Clear Domain Filter and attempt save - error: "Domain Filter is required"
- Enter same Domain Filter as an existing registration - error: duplicate domain

---

## Path 2 - Test Connection

**Goal:** Confirm Test Connection validates credentials against Microsoft Graph.

1. Open the App Registration card for a correctly configured registration
2. Click **Test Connection**

**Expected (valid credentials):** Success dialog - "Connection successful."

**Expected (invalid credentials):** Session crash ("Something went wrong") - this is BUG-004, a known limitation. The RestClientOAuth library raises uncatchable collectible errors on auth failure.

---

## Path 3 - Current User Email Send

**Goal:** Confirm a B2B guest user can send email from their home-tenancy address.

1. Sign in to BC as a guest user (Authentication Email contains `#EXT#`)
2. Open **Email Accounts** - the account should show the decoded home email (e.g. `user@contoso.com`)
3. Open any record with an email send action (e.g. Customer Card > Send Email)
4. Compose an email and click **Send**

**Expected:**
- Email is delivered to the recipient
- From address is the guest user's home-tenancy address (e.g. `user@contoso.com`), not the BC host tenant address
- No session errors

---

## Path 4 - Current User Wizard Setup

**Goal:** Confirm the Set Up Email wizard completes successfully.

1. Open **Email Accounts** and click **New**
2. Select **Current User (Microsoft Graph)** and click **Next**
3. The App Registrations list opens - confirm at least one registration exists with a Domain Filter, then close the list
4. Wizard advances to the completion screen

**Expected:**
- Wizard reaches "Congratulations" screen
- Account Name shows "Current User (Microsoft Graph)"
- Note: Email Address is blank on this screen (BUG-005, cosmetic) - it shows correctly on the Rate Limit page

---

## Path 5 - Attachments

**Goal:** Confirm attachments are included in the sent email.

1. Sign in as a guest user
2. Compose an email and attach a file
3. Send

**Expected:** Email received with attachment intact.

---

## Path 6 - Shared Mailbox Send

**Goal:** Confirm a shared mailbox account sends from the correct address.

1. Open **Email Accounts** - confirm a Shared Mailbox account exists (e.g. `sales@contoso.com`)
2. Compose an email selecting the shared mailbox as the From account
3. Send

**Expected:**
- Email delivered to recipient
- From address is the shared mailbox address
- No session errors

---

## Path 7 - Shared Mailbox Setup

**Goal:** Confirm shared mailbox accounts can be created and deleted.

1. Open **Email Accounts**, click **New**
2. Select **Shared Mailbox (Microsoft Graph)** and click **Next**
3. The Shared Mailbox Accounts list opens - create a new entry with Display Name, Mailbox Email, and App Registration
4. Close the list - wizard completes

**Expected:** New account appears in Email Accounts list.

**Delete test:**
1. Select a Shared Mailbox account in Email Accounts
2. Click **Delete Account** - confirmation prompt appears
3. Confirm - account is removed, no session crash

---

## Path 8 - CC and BCC

**Goal:** Confirm CC and BCC recipients are delivered correctly.

1. Compose an email, click **Show more** to expand CC and BCC fields
2. Add recipients to CC and BCC
3. Send

**Expected:** All recipients (To, CC, BCC) receive the email. BCC recipients are not visible to To/CC recipients.

---

## Path 1 - Admin Setup

**Goal:** Confirm the setup card saves app registration details and stores the client secret correctly.

1. Search BC for **W365 Email Setup** and open it
2. Enter the following:
   - **App (Client) ID** - `deda566a-3ed3-4b8e-9238-e1eb3665c3f7`
   - **Host Tenant ID** - `585f2caa-d65b-4e77-92bd-f83b9697165c`
   - **Redirect URI** - `https://businesscentral.dynamics.com/OAuthLanding.htm`
3. In **Enter New Client Secret**, paste the secret value and press Tab

**Expected:**
- "Client secret saved." message appears
- **Client Secret Status** field shows **Configured**
- App ID, Tenant ID, and Redirect URI persist on the page

---

## Path 2 - Guest Auto-Detection

**Goal:** Confirm the app correctly identifies guest vs member accounts using the `#EXT#` check on Authentication Email - no manual flagging required.

1. Search BC for **Users** and open the card for your guest user
2. Check the **Authentication Email** field - it should contain `#EXT#` (e.g. `user_theircompany.com#EXT#@yourtenant.onmicrosoft.com`)
3. Open the card for a regular member account - their Authentication Email should have no `#EXT#`

**Expected:**
- Guest user Authentication Email contains `#EXT#`
- Member user Authentication Email does not contain `#EXT#`
- No User Setup configuration is needed - the distinction is automatic

---

## Path 3 - OAuth Consent via Direct Page (Happy Path)

**Goal:** Complete the full consent flow via the direct consent page and confirm a token is stored.

1. Search BC for **W365 User Token Status**
2. Click **Authorise (Consent Flow)** to open the **Connect Your Email** page
3. Click **Connect my Email**
4. A sign-in popup opens automatically - sign in with the guest user's home-tenancy account (e.g. `user@theircompany.com`) and click **Accept**
5. The popup closes automatically

**Expected:**
- Page updates to show **Connected** status without any manual URL copy/paste
- **W365 User Token Status** list shows the user with status **Active** and a populated expiry timestamp

---

## Path 3b - OAuth Consent via Email Accounts Wizard

**Goal:** Complete the full consent flow via BC's native Set Up Email Account wizard.

1. Search BC for **Email Accounts** and click **New**
2. Select **Guest Email (Microsoft Graph)** from the account type list and click **Next**
3. The **Connect Current User Email API** page opens - click **Connect my Email**
4. Sign in with your home-tenancy account in the popup and click **Accept**
5. Click **Next** then **Finish** in the wizard

**Expected:**
- The wizard completes and returns to Email Accounts
- The single **Current User Email API** account row is present (or remains present if already created)
- Account email address now shows your home-tenancy address (was "not connected" before consent)

---

## Path 4 - Send Test Email via Connect Your Email Page

**Goal:** Confirm an email is sent from the guest user's home-tenancy address via the consent page.

1. On the **Connect Your Email** page (after a successful consent), scroll to the **Test Email** section
2. Enter your own email address in **Test Recipient Address**
3. Click **Send Test Email**

**Expected:**
- "Test email sent successfully via Microsoft Graph." message appears
- Email arrives in the recipient inbox
- The **From** address is the guest user's home-tenancy address (e.g. `user@theircompany.com`), not a BC host tenant address

---

## Path 4b - Send Test Email via Email Accounts Page

**Goal:** Confirm BC's native Send Test Email works through the connector.

1. Search BC for **Email Accounts**
2. Select the **Current User Email API** account row
3. Click **Send Test Email** from the action bar

**Expected:**
- BC sends a test email using the connector
- Email arrives in the recipient inbox from your home-tenancy address
- No errors in BC

---

## Path 4c - Email Connector Account Information

**Goal:** Confirm Show Account Information is a no-op (by design).

1. Search BC for **Email Accounts**
2. Select the **Current User Email API** account row
3. Click **Show Account Information**

**Expected:**
- Nothing opens - this is intentional. The account row itself shows all relevant status.
- No errors

---

## Path 5 - Error Scenarios

**Goal:** Confirm all user-facing errors are surfaced correctly with helpful messages.

| Scenario | How to trigger | Expected error message |
|---|---|---|
| Setup not configured | Clear the App ID field, attempt consent (Step 1) | "W365 Email Setup has not been configured. Open the W365 Email Setup Card..." |
| Client secret missing | Use **Clear Client Secret** action on the Setup Card, attempt Step 2 | "Client secret has not been configured. Open the W365 Email Setup Card..." |
| Redirect URL missing `code=` param | Paste any URL without `code=` into the redirect field and Tab out | "The URL does not appear to contain an authorisation code..." |
| No recipient entered | Leave Test Recipient blank, click Send Test Email | "Please enter a recipient email address in the Test Recipient Address field." |
| No redirect URL when clicking Step 2 | Click Step 2 without pasting a URL | "Please paste the redirect URL from your browser..." |
| Token cleared | Click **Disconnect** on the consent page | Confirms prompt appears; after confirming, Token Status shows blank/none and Send Test Email is greyed out |

---

## Path 6 - Disconnect and Re-Authorise

**Goal:** Confirm a user can revoke their token and re-connect cleanly.

1. On **W365 - Authorise Email Access**, confirm Token Status is **Active**
2. Click **Disconnect** and confirm
3. **Expected:** Token Status clears; Send Test Email button is disabled
4. Complete Path 3 again (Steps 1 and 2 of the consent flow)
5. **Expected:** Token Status returns to **Active**; Send Test Email works again

---

## Path 7 - Single Account / Current User Model

**Goal:** Confirm that all users' sends route through their own token via the single fixed account.

1. Complete the consent flow (Path 3) as user A
2. Complete the consent flow (Path 3) as user B (different session)
3. As user A, send a test email - confirm it arrives from user A's home address
4. As user B, send a test email - confirm it arrives from user B's home address
5. Confirm there is still only **one** row in **Email Accounts** (Current User Email API)

**Expected:**
- One account row exists regardless of how many users have consented
- Each user's send resolves to their own Graph token at runtime
- A user who has not consented gets an error at send time (token not found) - correct signal to run consent flow

---

## Notes

- Automated AL test codeunits are not included in Phase 1 - the OAuth consent flow requires a real browser session that cannot be simulated in automated tests
- Token refresh is tested implicitly - after a successful consent, wait for the access token to expire (typically 1 hour) and confirm the next send still succeeds without re-consenting
