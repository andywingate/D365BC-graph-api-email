namespace Wingate365.GuestEmailAPI;

using System.Email;
using System.RestClient;
using Microsoft.Identity.Client;

codeunit 50118 "W365 Shared Mailbox Connector" implements "Email Connector", "Email Connector v4", "Default Email Rate Limit"
{
    Access = Internal;

    // =========================================================================
    // "Email Connector" interface
    // =========================================================================

    procedure Send(EmailMessage: Codeunit "Email Message"; AccountId: Guid)
    var
        SharedMailbox: Record "W365 Shared Mailbox Account";
        Recipients: List of [Text];
        NoRecipientsErr: Label 'The email message has no recipients.';
        AccountNotFoundErr: Label 'Shared mailbox account not found for Account ID %1.', Comment = '%1 = account id';
    begin
        EmailMessage.GetRecipients(Enum::"Email Recipient Type"::"To", Recipients);
        if Recipients.Count() = 0 then
            Error(NoRecipientsErr);

        if not FindSharedMailboxByAccountId(AccountId, SharedMailbox) then
            Error(AccountNotFoundErr, AccountId);

        if not TrySend(EmailMessage, SharedMailbox) then
            Error(GetLastErrorText());
    end;

    [TryFunction]
    local procedure TrySend(var EmailMessage: Codeunit "Email Message"; var SharedMailbox: Record "W365 Shared Mailbox Account")
    var
        AppReg: Record "W365 App Registration";
        OAuthClientApp: Codeunit "OAuth Client Application KFM";
        MicrosoftEntraID: Codeunit "Microsoft Entra ID KFM";
        ClientCredFlow: Codeunit "Client Credentials Flow KFM";
        HttpAuthOAuth2: Codeunit "Http Authentication OAuth2 KFM";
        OAuthAuthority: Interface "OAuth Authority KFM";
        OAuthAuthorizationFlow: Interface "OAuth Authorization Flow KFM";
        HttpAuthentication: Interface "Http Authentication";
        SendClient: Codeunit "Rest Client";
        ClientSecret: Text;
        ClientSecretAsSecret: SecretText;
        GraphMailMgt: Codeunit "W365 Graph Mail Mgt";
        NoSecretErr: Label 'No client secret configured for App Registration %1.', Comment = '%1 = code';
    begin
        SharedMailbox.GetAppRegistration(AppReg);

        if not AppReg.GetClientSecret(ClientSecret) then
            Error(NoSecretErr, AppReg."Code");

        OAuthClientApp.SetClientId(AppReg."App ID");
        ClientSecretAsSecret := ClientSecret;
        OAuthClientApp.SetClientSecret(ClientSecretAsSecret);
        OAuthClientApp.AddScope('https://graph.microsoft.com/.default');
        MicrosoftEntraID.SetTenantID(AppReg.GetAuthorityTenant());
        OAuthAuthority := MicrosoftEntraID;
        ClientCredFlow.SetAuthority(OAuthAuthority);
        OAuthAuthorizationFlow := ClientCredFlow;
        HttpAuthOAuth2.Initialize(OAuthClientApp, OAuthAuthorizationFlow);
        HttpAuthentication := HttpAuthOAuth2;
        SendClient.Initialize(HttpAuthentication);

        GraphMailMgt.SendEmailMessage(EmailMessage, SharedMailbox.GetSendMailEndpoint(), SendClient);
    end;

    procedure GetAccounts(var EmailAccount: Record "Email Account")
    var
        SharedMailbox: Record "W365 Shared Mailbox Account";
    begin
        if SharedMailbox.FindSet() then
            repeat
                EmailAccount.Init();
                EmailAccount."Account Id" := SharedMailbox.SystemId;
                EmailAccount.Name := SharedMailbox."Display Name";
                EmailAccount."Email Address" := CopyStr(SharedMailbox."Mailbox Email", 1, MaxStrLen(EmailAccount."Email Address"));
                EmailAccount.Connector := Enum::"Email Connector"::"W365 Shared Mailbox";
                if EmailAccount.Insert() then;
            until SharedMailbox.Next() = 0;
    end;

    procedure ShowAccountInformation(AccountId: Guid)
    var
        SharedMailbox: Record "W365 Shared Mailbox Account";
    begin
        if FindSharedMailboxByAccountId(AccountId, SharedMailbox) then
            Page.Run(Page::"W365 Shared Mailbox Card", SharedMailbox);
    end;

    procedure RegisterAccount(var EmailAccount: Record "Email Account"): Boolean
    var
        SharedMailbox: Record "W365 Shared Mailbox Account";
    begin
        // Open the Shared Mailbox Accounts list so admin can create a new entry
        Page.RunModal(Page::"W365 Shared Mailbox Accounts");

        // Return the last inserted record if any exist
        if SharedMailbox.FindLast() then begin
            EmailAccount."Account Id" := SharedMailbox.SystemId;
            EmailAccount.Name := SharedMailbox."Display Name";
            EmailAccount."Email Address" := CopyStr(SharedMailbox."Mailbox Email", 1, MaxStrLen(EmailAccount."Email Address"));
            EmailAccount.Connector := Enum::"Email Connector"::"W365 Shared Mailbox";
            exit(true);
        end;
        exit(false);
    end;

    procedure DeleteAccount(AccountId: Guid): Boolean
    var
        SharedMailbox: Record "W365 Shared Mailbox Account";
        ConfirmMsg: Label 'This will remove the shared mailbox account configuration. Continue?';
    begin
        if not Confirm(ConfirmMsg) then
            exit(false);

        if FindSharedMailboxByAccountId(AccountId, SharedMailbox) then
            SharedMailbox.Delete();

        exit(true);
    end;

    procedure GetLogoAsBase64(): Text
    begin
        exit('');
    end;

    procedure GetDescription(): Text[250]
    begin
        exit('Send emails from Business Central via Microsoft Graph using a shared mailbox from another tenancy. Ideal for B2B guest users using a shared mailbox in their home tenancy.');
    end;

    // =========================================================================
    // "Email Connector v4" interface - read/reply (not implemented)
    // =========================================================================

    procedure Reply(var EmailMessage: Codeunit "Email Message"; AccountId: Guid)
    begin
        Error('Reply is not supported by the Shared Mailbox connector. Use Send instead.');
    end;

    procedure RetrieveEmails(AccountId: Guid; var EmailInbox: Record "Email Inbox"; var Filters: Record "Email Retrieval Filters" temporary)
    begin
        // Send-only connector
    end;

    procedure MarkAsRead(AccountId: Guid; ExternalId: Text)
    begin
        // Send-only connector
    end;

    procedure GetEmailFolders(AccountId: Guid; var EmailFolders: Record "Email Folders" temporary)
    begin
        // Send-only connector
    end;

    // =========================================================================
    // "Default Email Rate Limit" interface
    // =========================================================================

    procedure GetDefaultEmailRateLimit(): Integer
    begin
        exit(0);
    end;

    // =========================================================================
    // Internal helpers
    // =========================================================================

    local procedure FindSharedMailboxByAccountId(AccountId: Guid; var SharedMailbox: Record "W365 Shared Mailbox Account"): Boolean
    begin
        SharedMailbox.Reset();
        exit(SharedMailbox.GetBySystemId(AccountId));
    end;
}
