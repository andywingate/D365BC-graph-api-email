namespace Wingate365.GuestEmailAPI;

using System.Email;
using System.RestClient;

codeunit 50118 "W365 Shared Mailbox Connector" implements "Email Connector", "Email Connector v4", "Default Email Rate Limit"
{
    Access = Internal;

    // =========================================================================
    // "Email Connector" interface
    // =========================================================================

    procedure Send(EmailMessage: Codeunit "Email Message"; AccountId: Guid)
    var
        SharedMailbox: Record "W365 Shared Mailbox Account";
        AppReg: Record "W365 App Registration";
        GraphSession: Codeunit "W365 Graph Session";
        GraphMailMgt: Codeunit "W365 Graph Mail Mgt";
        Client: Codeunit "Rest Client";
        Recipients: List of [Text];
        NoRecipientsErr: Label 'The email message has no recipients.';
    begin
        EmailMessage.GetRecipients(Enum::"Email Recipient Type"::"To", Recipients);
        if Recipients.Count() = 0 then
            Error(NoRecipientsErr);

        if not FindSharedMailboxByAccountId(AccountId, SharedMailbox) then
            Error('Shared mailbox account not found for Account ID %1.', AccountId);

        SharedMailbox.GetAppRegistration(AppReg);
        GraphSession.GetRestClient(AppReg."Code", Client);

        GraphMailMgt.SendEmailMessage(EmailMessage, SharedMailbox.GetSendMailEndpoint(), Client);
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
        GraphSession: Codeunit "W365 Graph Session";
        AppReg: Record "W365 App Registration";
        ConfirmMsg: Label 'This will remove the shared mailbox account configuration. Continue?';
    begin
        if not Confirm(ConfirmMsg) then
            exit(false);

        if FindSharedMailboxByAccountId(AccountId, SharedMailbox) then begin
            // Clear the session cache for this app registration
            SharedMailbox.GetAppRegistration(AppReg);
            GraphSession.ClearSession(AppReg."Code");
            SharedMailbox.Delete();
        end;
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
