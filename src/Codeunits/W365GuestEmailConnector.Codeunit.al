namespace Wingate365.GuestEmailAPI;

using System.Email;
using System.RestClient;
using System.Security.AccessControl;
using Microsoft.Identity.Client;

codeunit 50110 "W365 Guest Email Connector" implements "Email Connector", "Email Connector v4", "Default Email Rate Limit"
{
    Access = Internal;

    // =========================================================================
    // "Email Connector" interface
    // =========================================================================

    /// <summary>
    /// Sends an email via Microsoft Graph using the Authorization Code Grant (delegated) flow
    /// and the current user's resolved home address. On the first send in a BC session an
    /// interactive sign-in popup is shown so the user consents to Mail.Send on their behalf.
    /// Subsequent sends in the same session use the cached delegated token silently.
    /// Called by BC's Email module when sending any email assigned to this connector.
    /// </summary>
    procedure Send(EmailMessage: Codeunit "Email Message"; AccountId: Guid)
    var
        AppReg: Record "W365 App Registration";
        GraphSession: Codeunit "W365 Graph Session";
        User: Record User;
        Client: Codeunit "Rest Client";
        Recipients: List of [Text];
        SenderUPN: Text;
        HomeDomain: Text;
        GraphEndpoint: Text;
        ErrorText: Text;
        GraphEndpointTpl: Label 'https://graph.microsoft.com/v1.0/users/%1/sendMail', Locked = true;
        NoRecipientsErr: Label 'The email message has no recipients.';
        NoAppRegErr: Label 'No App Registration found for your account. Contact your administrator.';
        NoUPNErr: Label 'Your account does not have an Authentication Email address configured in Business Central. Contact your administrator.';
    begin
        EmailMessage.GetRecipients(Enum::"Email Recipient Type"::"To", Recipients);
        if Recipients.Count() = 0 then
            Error(NoRecipientsErr);

        if not User.Get(UserSecurityId()) then
            Error(NoUPNErr);
        SenderUPN := ResolveHomeEmail(User."Authentication Email");
        if SenderUPN = '' then
            Error(NoUPNErr);

        // Resolve App Registration directly from table - no SingleInstance codeunit in this
        // error path so any exception is properly propagated to the caller.
        HomeDomain := ResolveDomainFromEmail(User."Authentication Email");
        if not AppReg.ResolveForDomain(HomeDomain) then
            Error(NoAppRegErr);

        GraphEndpoint := StrSubstNo(GraphEndpointTpl, SenderUPN);

        // Build or retrieve the Auth Code Grant Rest Client from the session cache.
        // This only sets up credentials - no HTTP calls or sign-in popup happen here.
        // The popup (if needed) fires lazily inside TrySend() when the first HTTP call is made.
        GraphSession.GetOrBuildGuestRestClient(AppReg."Code", Client);

        if not TrySend(EmailMessage, GraphEndpoint, Client) then begin
            ErrorText := GetLastErrorText();
            Error('Failed to send email via Microsoft Graph: %1', ErrorText);
        end;

        // After a successful send, write the updated client (with any refreshed token state)
        // back into the session cache so the next send in this session can reuse the token.
        GraphSession.UpdateGuestRestClient(AppReg."Code", Client);
    end;

    [TryFunction]
    local procedure TrySend(var EmailMessage: Codeunit "Email Message"; GraphEndpoint: Text; var Client: Codeunit "Rest Client")
    var
        GraphMailMgt: Codeunit "W365 Graph Mail Mgt";
    begin
        // W365 Graph Session (SingleInstance) is NOT on the call stack here - only the
        // pre-built Client is passed in as a value. Any exception thrown during token
        // acquisition (sign-in popup) or the Graph HTTP call is caught by [TryFunction]
        // without risk of corrupting the SingleInstance session state.
        GraphMailMgt.SendEmailMessage(EmailMessage, GraphEndpoint, Client);
    end;

    /// <summary>
    /// Returns one account with a fixed well-known GUID - the same pattern as BC's built-in
    /// "Current User" connector. There is only ever one entry in Email Accounts; set it as
    /// the system default once and every user's sends resolve to their own home email address
    /// at runtime via UserSecurityId(). The email address shown reflects the current user's
    /// decoded Authentication Email.
    /// </summary>
    procedure GetAccounts(var EmailAccount: Record "Email Account")
    var
        AppReg: Record "W365 App Registration";
        User: Record User;
        AccountNameLbl: Label 'Current User (Microsoft Graph)', Locked = true;
    begin
        // Only surface the account once at least one App Registration has been configured.
        // In a fresh company with no setup, nothing appears in Email Accounts.
        if AppReg.IsEmpty() then
            exit;

        EmailAccount.Init();
        EmailAccount."Account Id" := GetFixedAccountId();
        EmailAccount.Name := AccountNameLbl;
        EmailAccount.Connector := Enum::"Email Connector"::"W365 Guest Email";

        // Show the current user's real home email - decoded from #EXT# UPN for guests.
        if User.Get(UserSecurityId()) and (User."Authentication Email" <> '') then
            EmailAccount."Email Address" := CopyStr(ResolveHomeEmail(User."Authentication Email"), 1, MaxStrLen(EmailAccount."Email Address"));

        if EmailAccount.Insert() then;
    end;

    /// <summary>
    /// Fixed well-known GUID used as the single Account Id for this connector.
    /// All users share this one logical account; the connector resolves the actual
    /// sender credentials at send time via UserSecurityId().
    /// </summary>
    local procedure GetFixedAccountId(): Guid
    var
        AccountId: Guid;
    begin
        Evaluate(AccountId, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890');
        exit(AccountId);
    end;

    /// <summary>
    /// Decodes a BC Authentication Email to the user's real home email.
    /// For B2B guests (alice_contoso.com#EXT#@host.onmicrosoft.com) returns alice@contoso.com.
    /// For member accounts returns the value unchanged.
    /// Pure text operation - no codeunit references, safe to call from GetAccounts.
    /// </summary>
    local procedure ResolveHomeEmail(AuthEmail: Text): Text
    var
        ExtPos: Integer;
        UnderscorePos: Integer;
        Prefix: Text;
        i: Integer;
    begin
        if AuthEmail = '' then
            exit('');
        ExtPos := StrPos(AuthEmail, '#EXT#');
        if ExtPos > 0 then begin
            Prefix := CopyStr(AuthEmail, 1, ExtPos - 1);
            UnderscorePos := 0;
            for i := 1 to StrLen(Prefix) do
                if Prefix[i] = '_' then
                    UnderscorePos := i;
            if UnderscorePos > 0 then
                exit(CopyStr(Prefix, 1, UnderscorePos - 1) + '@' + CopyStr(Prefix, UnderscorePos + 1));
            exit(Prefix);
        end;
        exit(AuthEmail);
    end;

    local procedure ResolveDomainFromEmail(AuthEmail: Text): Text
    var
        ExtPos: Integer;
        UnderscorePos: Integer;
        AtPos: Integer;
        Prefix: Text;
        i: Integer;
    begin
        if AuthEmail = '' then
            exit('');
        ExtPos := StrPos(AuthEmail, '#EXT#');
        if ExtPos > 0 then begin
            Prefix := CopyStr(AuthEmail, 1, ExtPos - 1);
            UnderscorePos := 0;
            for i := 1 to StrLen(Prefix) do
                if Prefix[i] = '_' then
                    UnderscorePos := i;
            if UnderscorePos > 0 then
                exit(CopyStr(Prefix, UnderscorePos + 1));
            exit('');
        end;
        AtPos := StrPos(AuthEmail, '@');
        if AtPos > 0 then
            exit(CopyStr(AuthEmail, AtPos + 1));
        exit('');
    end;

    /// <summary>
    /// Shows the account information page for the given account.
    /// Opens the consent page for the relevant user.
    /// </summary>
    procedure ShowAccountInformation(AccountId: Guid)
    var
        AppReg: Record "W365 App Registration";
        GraphSession: Codeunit "W365 Graph Session";
    begin
        // Open the App Registrations list so the admin can review setup
        // The user's resolved registration is shown at the top
        Page.Run(Page::"W365 App Registrations");
    end;

    /// <summary>
    /// Called when "Set Up Email Account" wizard reaches this connector.
    /// Opens the consent page - the user connects their account there.
    /// Returns true once the user has an active token.
    /// </summary>
    procedure RegisterAccount(var EmailAccount: Record "Email Account"): Boolean
    var
        AppReg: Record "W365 App Registration";
        UserRec: Record User;
        AccountNameLbl: Label 'Current User (Microsoft Graph)', Locked = true;
        NoRegErr: Label 'No App Registration has been configured. Open App Registrations, create one with a valid Domain Filter, and save it before completing setup.';
    begin
        // Open App Registrations list so the admin can create/configure one without leaving the wizard.
        Page.RunModal(Page::"W365 App Registrations");

        // After the list closes, verify at least one registration with a domain filter exists.
        AppReg.SetFilter("Domain Filter", '<>%1', '');
        if not AppReg.FindFirst() then
            Error(NoRegErr);

        EmailAccount."Account Id" := GetFixedAccountId();
        EmailAccount.Name := AccountNameLbl;
        EmailAccount.Connector := Enum::"Email Connector"::"W365 Guest Email";

        // Populate email address so the wizard completion screen shows it.
        if UserRec.Get(UserSecurityId()) and (UserRec."Authentication Email" <> '') then
            EmailAccount."Email Address" := CopyStr(ResolveHomeEmail(UserRec."Authentication Email"), 1, MaxStrLen(EmailAccount."Email Address"));

        exit(true);
    end;

    /// <summary>
    /// Deletes the stored token for the given account, disconnecting the user.
    /// </summary>
    procedure DeleteAccount(AccountId: Guid): Boolean
    var
        CannotDeleteMsg: Label 'This account cannot be deleted. It is automatically available to all users based on the App Registration setup. To disable it, delete all App Registrations instead.';
    begin
        Message(CannotDeleteMsg);
        exit(false);
    end;

    /// <summary>
    /// Returns a base64-encoded logo shown in the Email Account setup wizard.
    /// Returning empty string uses the default connector icon.
    /// </summary>
    procedure GetLogoAsBase64(): Text
    begin
        exit('');
    end;

    /// <summary>
    /// Short description shown in the "Set Up Email Account" wizard account type list.
    /// </summary>
    procedure GetDescription(): Text[250]
    begin
        exit('Send emails from Business Central via Microsoft Graph using each user''s own delegated sign-in (Authorization Code Grant). Ideal for B2B guest users or other multi-tenancy deployments. Requires delegated Mail.Send permission.');
    end;

    // =========================================================================
    // "Email Connector v4" interface - read/reply (not implemented in Phase 2)
    // =========================================================================

    /// <summary>Reply to an email. Not implemented - send-only connector.</summary>
    procedure Reply(var EmailMessage: Codeunit "Email Message"; AccountId: Guid)
    begin
        Error('Reply is not supported by the Current User (Microsoft Graph) connector. Use Send instead.');
    end;

    /// <summary>Retrieve emails from inbox. Not implemented - send-only connector.</summary>
    procedure RetrieveEmails(AccountId: Guid; var EmailInbox: Record "Email Inbox"; var Filters: Record "Email Retrieval Filters" temporary)
    begin
        // Send-only connector - no inbox retrieval
    end;

    /// <summary>Mark email as read. Not implemented - send-only connector.</summary>
    procedure MarkAsRead(AccountId: Guid; ExternalId: Text)
    begin
        // Send-only connector - no read state management
    end;

    /// <summary>Get email folders. Not implemented - send-only connector.</summary>
    procedure GetEmailFolders(AccountId: Guid; var EmailFolders: Record "Email Folders" temporary)
    begin
        // Send-only connector - no folder management
    end;

    // =========================================================================
    // "Default Email Rate Limit" interface
    // =========================================================================

    /// <summary>
    /// Graph Mail.Send delegated permission has no strict per-connector rate limit we need to enforce.
    /// Returning 0 means no limit imposed by this connector.
    /// </summary>
    procedure GetDefaultEmailRateLimit(): Integer
    begin
        exit(0);
    end;
}
