namespace Wingate365.GuestEmailAPI;

using System.Email;
using System.RestClient;
using Microsoft.Identity.Client;

codeunit 50105 "W365 Graph Mail Mgt"
{
    Access = Internal;

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /// <summary>
    /// Tests the App Registration credentials by acquiring a token and calling
    /// GET /organization. Safe to call from page actions - error is caught and
    /// returned in ErrorText rather than crashing the session.
    /// </summary>
    procedure TestAppRegConnection(AppRegCode: Code[20]; var ErrorText: Text): Boolean
    var
        GraphSession: Codeunit "W365 Graph Session";
        HttpResponseMessage: Codeunit "Http Response Message";
    begin
        if not TryPingGraph(AppRegCode, HttpResponseMessage) then begin
            ErrorText := GetLastErrorText();
            GraphSession.ClearSession(AppRegCode);
            exit(false);
        end;
        if HttpResponseMessage.GetHttpStatusCode() = 200 then
            exit(true);
        ErrorText := StrSubstNo('Microsoft Graph returned HTTP %1. Check the App ID, Tenant ID, Client Secret, and that Mail.Send application permission has admin consent.', HttpResponseMessage.GetHttpStatusCode());
        GraphSession.ClearSession(AppRegCode);
        exit(false);
    end;

    [TryFunction]
    local procedure TryPingGraph(AppRegCode: Code[20]; var HttpResponseMessage: Codeunit "Http Response Message")
    var
        AppReg: Record "W365 App Registration";
        OAuthClientApp: Codeunit "OAuth Client Application KFM";
        MicrosoftEntraID: Codeunit "Microsoft Entra ID KFM";
        ClientCredFlow: Codeunit "Client Credentials Flow KFM";
        HttpAuthOAuth2: Codeunit "Http Authentication OAuth2 KFM";
        OAuthAuthority: Interface "OAuth Authority KFM";
        OAuthAuthorizationFlow: Interface "OAuth Authorization Flow KFM";
        HttpAuthentication: Interface "Http Authentication";
        PingClient: Codeunit "Rest Client";
        ClientSecret: Text;
        ClientSecretAsSecret: SecretText;
        OrgEndpoint: Label 'https://graph.microsoft.com/v1.0/organization?$select=id', Locked = true;
        NoSecretErr: Label 'No client secret is configured for App Registration %1. Open the App Registration and set the client secret.', Comment = '%1 = App Registration code';
    begin
        // Build the OAuth stack fresh - no SingleInstance codeunit in this error path
        // so any exception thrown by the OAuth library is properly caught by [TryFunction].
        if not AppReg.Get(AppRegCode) then
            Error('App Registration %1 not found.', AppRegCode);
        if not AppReg.GetClientSecret(ClientSecret) then
            Error(NoSecretErr, AppRegCode);

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
        PingClient.Initialize(HttpAuthentication);
        HttpResponseMessage := PingClient.Get(OrgEndpoint);
    end;

    procedure GetCurrentUserEmail(): Text
    var
        GraphSession: Codeunit "W365 Graph Session";
        AppReg: Record "W365 App Registration";
        Client: Codeunit "Rest Client";
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        MeEndpoint: Label 'https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName', Locked = true;
    begin
        if not GraphSession.ResolveAppRegForCurrentUser(AppReg) then
            exit('');
        GraphSession.GetRestClient(AppReg."Code", Client);
        if not TryGetAsJson(Client, MeEndpoint, ResponseJson) then
            exit('');
        if ResponseJson.Get('mail', JsonToken) then
            if JsonToken.AsValue().AsText() <> '' then
                exit(JsonToken.AsValue().AsText());
        if ResponseJson.Get('userPrincipalName', JsonToken) then
            exit(JsonToken.AsValue().AsText());
        exit('');
    end;

    procedure SendEmail(ToAddress: Text; Subject: Text; BodyHtml: Text): Boolean
    begin
        exit(SendEmailInternal(ToAddress, Subject, BodyHtml, ''));
    end;

    procedure SendEmail(ToAddress: Text; Subject: Text; BodyHtml: Text; BodyText: Text): Boolean
    begin
        exit(SendEmailInternal(ToAddress, Subject, BodyHtml, BodyText));
    end;

    /// <summary>
    /// Full send - all recipients (To/Cc/Bcc) and attachments from the Email Message codeunit.
    /// Called by the connector's Send() implementation for complete Email Connector v4 compliance.
    /// </summary>
    procedure SendEmailMessage(var EmailMessage: Codeunit "Email Message"; GraphEndpoint: Text; var Client: Codeunit "Rest Client"): Boolean
    var
        JsonBody: JsonObject;
    begin
        JsonBody := BuildSendMailJsonFromMessage(EmailMessage);
        exit(ExecutePost(Client, GraphEndpoint, JsonBody));
    end;

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    local procedure SendEmailInternal(ToAddress: Text; Subject: Text; BodyHtml: Text; BodyText: Text): Boolean
    var
        GraphSession: Codeunit "W365 Graph Session";
        AppReg: Record "W365 App Registration";
        Client: Codeunit "Rest Client";
        JsonBody: JsonObject;
        GraphEndpoint: Label 'https://graph.microsoft.com/v1.0/me/sendMail', Locked = true;
        ContentType: Text;
        Body: Text;
        NoAppRegErr: Label 'No App Registration found for your account. Contact your administrator.';
    begin
        if not GraphSession.ResolveAppRegForCurrentUser(AppReg) then
            Error(NoAppRegErr);
        GraphSession.GetRestClient(AppReg."Code", Client);
        if BodyHtml <> '' then begin
            ContentType := 'HTML';
            Body := BodyHtml;
        end else begin
            ContentType := 'Text';
            Body := BodyText;
        end;
        JsonBody := BuildSendMailJson(ToAddress, Subject, Body, ContentType);
        exit(ExecutePost(Client, GraphEndpoint, JsonBody));
    end;

    local procedure ExecutePost(var Client: Codeunit "Rest Client"; Endpoint: Text; JsonBody: JsonObject): Boolean
    var
        HttpResponseMessage: Codeunit "Http Response Message";
        HttpContentLocal: Codeunit "Http Content";
        BodyText: Text;
        StatusCode: Integer;
        ConnectErr: Label 'Could not reach Microsoft Graph. Check BC server outbound connectivity.';
        ThrottledErr: Label 'Microsoft Graph is throttling requests. Please wait a moment and try again.';
    begin
        JsonBody.WriteTo(BodyText);
        HttpContentLocal := HttpContentLocal.Create(BodyText, 'application/json');
        HttpResponseMessage := Client.Post(Endpoint, HttpContentLocal);
        StatusCode := HttpResponseMessage.GetHttpStatusCode();
        if StatusCode = 202 then
            exit(true);
        if StatusCode = 429 then
            Error(ThrottledErr);
        if StatusCode = 0 then
            Error(ConnectErr);
        ParseAndRaiseGraphError(HttpResponseMessage, StatusCode);
        exit(false);
    end;

    [TryFunction]
    local procedure TryGetAsJson(var Client: Codeunit "Rest Client"; Endpoint: Text; var ResponseJson: JsonObject)
    var
        HttpResponseMessage: Codeunit "Http Response Message";
    begin
        HttpResponseMessage := Client.Get(Endpoint);
        if not HttpResponseMessage.GetIsSuccessStatusCode() then
            Error('');
        ResponseJson := HttpResponseMessage.GetContent().AsJson().AsObject();
    end;

    local procedure BuildSendMailJson(ToAddress: Text; Subject: Text; Body: Text; ContentType: Text): JsonObject
    var
        MsgObj: JsonObject;
        BodyObj: JsonObject;
        RecipientsArr: JsonArray;
        RecipientObj: JsonObject;
        EmailAddressObj: JsonObject;
        RootObj: JsonObject;
    begin
        EmailAddressObj.Add('address', ToAddress);
        RecipientObj.Add('emailAddress', EmailAddressObj);
        RecipientsArr.Add(RecipientObj);
        BodyObj.Add('contentType', ContentType);
        BodyObj.Add('content', Body);
        MsgObj.Add('subject', Subject);
        MsgObj.Add('body', BodyObj);
        MsgObj.Add('toRecipients', RecipientsArr);
        RootObj.Add('message', MsgObj);
        RootObj.Add('saveToSentItems', true);
        exit(RootObj);
    end;

    local procedure BuildSendMailJsonFromMessage(var EmailMessage: Codeunit "Email Message"): JsonObject
    var
        MsgObj: JsonObject;
        BodyObj: JsonObject;
        RootObj: JsonObject;
        AttachmentsArr: JsonArray;
        AttachmentObj: JsonObject;
        AttachmentBase64: Text;
        AttachmentName: Text[250];
        AttachmentContentType: Text[250];
    begin
        BodyObj.Add('contentType', 'HTML');
        BodyObj.Add('content', EmailMessage.GetBody());
        MsgObj.Add('subject', EmailMessage.GetSubject());
        MsgObj.Add('body', BodyObj);
        MsgObj.Add('toRecipients', BuildRecipientsArray(EmailMessage, Enum::"Email Recipient Type"::"To"));
        MsgObj.Add('ccRecipients', BuildRecipientsArray(EmailMessage, Enum::"Email Recipient Type"::"Cc"));
        MsgObj.Add('bccRecipients', BuildRecipientsArray(EmailMessage, Enum::"Email Recipient Type"::"Bcc"));

        // Inline attachments (base64 - suitable for attachments up to ~3MB per Graph API guidance)
        if EmailMessage.Attachments_First() then
            repeat
                AttachmentBase64 := EmailMessage.Attachments_GetContentBase64();
                AttachmentName := EmailMessage.Attachments_GetName();
                AttachmentContentType := EmailMessage.Attachments_GetContentType();
                Clear(AttachmentObj);
                AttachmentObj.Add('@odata.type', '#microsoft.graph.fileAttachment');
                AttachmentObj.Add('name', AttachmentName);
                AttachmentObj.Add('contentType', AttachmentContentType);
                AttachmentObj.Add('contentBytes', AttachmentBase64);
                if EmailMessage.Attachments_IsInline() then begin
                    AttachmentObj.Add('isInline', true);
                    AttachmentObj.Add('contentId', EmailMessage.Attachments_GetContentId());
                end else
                    AttachmentObj.Add('isInline', false);
                AttachmentsArr.Add(AttachmentObj);
            until EmailMessage.Attachments_Next() = 0;
        MsgObj.Add('attachments', AttachmentsArr);

        RootObj.Add('message', MsgObj);
        RootObj.Add('saveToSentItems', true);
        exit(RootObj);
    end;

    local procedure BuildRecipientsArray(var EmailMessage: Codeunit "Email Message"; RecipientType: Enum "Email Recipient Type"): JsonArray
    var
        Recipients: List of [Text];
        Address: Text;
        RecipientObj: JsonObject;
        EmailAddressObj: JsonObject;
        RecipientsArr: JsonArray;
    begin
        EmailMessage.GetRecipients(RecipientType, Recipients);
        foreach Address in Recipients do begin
            Clear(EmailAddressObj);
            Clear(RecipientObj);
            EmailAddressObj.Add('address', Address);
            RecipientObj.Add('emailAddress', EmailAddressObj);
            RecipientsArr.Add(RecipientObj);
        end;
        exit(RecipientsArr);
    end;

    local procedure ParseAndRaiseGraphError(var HttpResponseMessage: Codeunit "Http Response Message"; StatusCode: Integer)
    var
        JsonObj: JsonObject;
        ErrorObj: JsonObject;
        JsonToken: JsonToken;
        ResponseText: Text;
        ErrorCode: Text;
        GenericErr: Label 'Microsoft Graph returned status %1. Check the app registration permissions and try again.';
    begin
        ErrorCode := '';
        ResponseText := HttpResponseMessage.GetErrorMessage();
        if JsonObj.ReadFrom(ResponseText) then
            if JsonObj.Get('error', JsonToken) then begin
                ErrorObj := JsonToken.AsObject();
                if ErrorObj.Get('code', JsonToken) then
                    ErrorCode := JsonToken.AsValue().AsText();
            end;
        if ErrorCode <> '' then
            Error('Microsoft Graph error: %1 (HTTP %2). Check the app registration and try again.', ErrorCode, StatusCode)
        else
            Error(GenericErr, StatusCode);
    end;
}
