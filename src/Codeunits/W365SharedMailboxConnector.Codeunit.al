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
        Client: Codeunit "Rest Client";
        Recipients: List of [Text];
        ToAddress: Text;
        Subject: Text;
        Body: Text;
        JsonBody: JsonObject;
        NoRecipientsErr: Label 'The email message has no recipients.';
    begin
        EmailMessage.GetRecipients(Enum::"Email Recipient Type"::"To", Recipients);
        if Recipients.Count() = 0 then
            Error(NoRecipientsErr);

        Recipients.Get(1, ToAddress);
        Subject := EmailMessage.GetSubject();
        Body := EmailMessage.GetBody();

        // Resolve the shared mailbox account by the fixed SystemId-based AccountId
        if not FindSharedMailboxByAccountId(AccountId, SharedMailbox) then
            Error('Shared mailbox account not found for Account ID %1.', AccountId);

        SharedMailbox.GetAppRegistration(AppReg);
        GraphSession.GetRestClient(AppReg."Code", Client);

        ExecuteSharedMailboxSend(Client, SharedMailbox.GetSendMailEndpoint(), ToAddress, Subject, Body);
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
        exit('Send emails from Business Central using a shared mailbox via Microsoft Graph. Multiple shared mailboxes can be configured independently.');
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

    local procedure ExecuteSharedMailboxSend(var Client: Codeunit "Rest Client"; Endpoint: Text; ToAddress: Text; Subject: Text; Body: Text)
    var
        HttpResponseMessage: Codeunit "Http Response Message";
        HttpContentLocal: Codeunit "Http Content";
        JsonBody: JsonObject;
        JsonBodyText: Text;
        MsgObj: JsonObject;
        BodyObj: JsonObject;
        RecipientsArr: JsonArray;
        RecipientObj: JsonObject;
        EmailAddressObj: JsonObject;
        RootObj: JsonObject;
        StatusCode: Integer;
        ThrottledErr: Label 'Microsoft Graph is throttling requests. Please wait a moment and try again.';
        ConnectErr: Label 'Could not reach Microsoft Graph. Check BC server outbound connectivity.';
        ErrorCode: Text;
        JsonObj: JsonObject;
        JsonToken: JsonToken;
        ErrorObj: JsonObject;
        ResponseText: Text;
        GenericErr: Label 'Microsoft Graph returned status %1 when sending from shared mailbox. Check the app registration has Mail.Send.Shared permission and the user has delegated access to the mailbox.';
    begin
        EmailAddressObj.Add('address', ToAddress);
        RecipientObj.Add('emailAddress', EmailAddressObj);
        RecipientsArr.Add(RecipientObj);
        BodyObj.Add('contentType', 'HTML');
        BodyObj.Add('content', Body);
        MsgObj.Add('subject', Subject);
        MsgObj.Add('body', BodyObj);
        MsgObj.Add('toRecipients', RecipientsArr);
        RootObj.Add('message', MsgObj);
        RootObj.Add('saveToSentItems', true);

        RootObj.WriteTo(JsonBodyText);
        HttpContentLocal := HttpContentLocal.Create(JsonBodyText);
        HttpResponseMessage := Client.Post(Endpoint, HttpContentLocal);

        StatusCode := HttpResponseMessage.GetHttpStatusCode();

        if StatusCode = 202 then
            exit;

        if StatusCode = 429 then
            Error(ThrottledErr);

        if StatusCode = 0 then
            Error(ConnectErr);

        // Parse error code from response
        ResponseText := HttpResponseMessage.GetErrorMessage();
        ErrorCode := '';
        if JsonObj.ReadFrom(ResponseText) then
            if JsonObj.Get('error', JsonToken) then begin
                ErrorObj := JsonToken.AsObject();
                if ErrorObj.Get('code', JsonToken) then
                    ErrorCode := JsonToken.AsValue().AsText();
            end;

        if ErrorCode <> '' then
            Error('Microsoft Graph error: %1 (HTTP %2).', ErrorCode, StatusCode)
        else
            Error(GenericErr, StatusCode);
    end;
}
