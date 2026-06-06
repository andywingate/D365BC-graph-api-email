namespace Wingate365.GuestEmailAPI;

using System.RestClient;

codeunit 50105 "W365 Graph Mail Mgt"
{
    Access = Internal;

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

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
        HttpContentLocal := HttpContentLocal.Create(BodyText);
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
