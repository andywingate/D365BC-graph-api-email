namespace Wingate365.GuestEmailAPI;

using System.RestClient;
using System.Security.AccessControl;
using Microsoft.Identity.Client;

page 50149 "W365 Graph Diagnostics"
{
    Caption = 'Graph API Diagnostics';
    PageType = Card;
    UsageCategory = Administration;
    ApplicationArea = All;

    layout
    {
        area(content)
        {
            group(UserInfo)
            {
                Caption = 'Step 1 - Current User Resolution';
                field(AuthEmail; AuthEmail)
                {
                    ApplicationArea = All;
                    Caption = 'Authentication Email (raw)';
                    Editable = false;
                }
                field(ResolvedEmail; ResolvedEmail)
                {
                    ApplicationArea = All;
                    Caption = 'Resolved Home Email';
                    Editable = false;
                }
                field(HomeDomain; HomeDomain)
                {
                    ApplicationArea = All;
                    Caption = 'Detected Home Domain';
                    Editable = false;
                }
                field(AppRegFound; AppRegFound)
                {
                    ApplicationArea = All;
                    Caption = 'App Registration Code';
                    Editable = false;
                }
                field(AppRegAppId; AppRegAppId)
                {
                    ApplicationArea = All;
                    Caption = 'App ID';
                    Editable = false;
                }
                field(AppRegTenantId; AppRegTenantId)
                {
                    ApplicationArea = All;
                    Caption = 'Tenant ID';
                    Editable = false;
                }
                field(SecretStatus; SecretStatus)
                {
                    ApplicationArea = All;
                    Caption = 'Client Secret';
                    Editable = false;
                }
            }
            group(GraphGroup)
            {
                Caption = 'Step 2 - Token + Graph Ping';
                field(PingStatus; PingStatus)
                {
                    ApplicationArea = All;
                    Caption = 'HTTP Status';
                    Editable = false;
                }
                field(PingResult; PingResult)
                {
                    ApplicationArea = All;
                    Caption = 'Result';
                    Editable = false;
                    MultiLine = true;
                }
            }
            group(SendGroup)
            {
                Caption = 'Step 3 - Send Test Email';
                field(SendToAddress; SendToAddress)
                {
                    ApplicationArea = All;
                    Caption = 'Send To Address';
                }
                field(SendStatus; SendStatus)
                {
                    ApplicationArea = All;
                    Caption = 'HTTP Status';
                    Editable = false;
                }
                field(SendResult; SendResult)
                {
                    ApplicationArea = All;
                    Caption = 'Result';
                    Editable = false;
                    MultiLine = true;
                }
            }
        }
    }

    actions
    {
        area(processing)
        {
            action(DoStep1)
            {
                ApplicationArea = All;
                Caption = 'Step 1: Resolve User';
                Image = Setup;

                trigger OnAction()
                var
                    User: Record User;
                    AppReg: Record "W365 App Registration";
                    ExtPos: Integer;
                    UnderscorePos: Integer;
                    AtPos: Integer;
                    Prefix: Text;
                    i: Integer;
                    AuthEmailLocal: Text;
                begin
                    Clear(AuthEmail);
                    Clear(ResolvedEmail);
                    Clear(HomeDomain);
                    Clear(AppRegFound);
                    Clear(AppRegAppId);
                    Clear(AppRegTenantId);
                    Clear(SecretStatus);

                    if not User.Get(UserSecurityId()) then begin
                        AuthEmail := 'FAIL: User.Get returned false';
                        exit;
                    end;

                    AuthEmail := User."Authentication Email";
                    AuthEmailLocal := AuthEmail;

                    // Decode #EXT# guest UPN
                    ExtPos := StrPos(AuthEmailLocal, '#EXT#');
                    if ExtPos > 0 then begin
                        Prefix := CopyStr(AuthEmailLocal, 1, ExtPos - 1);
                        UnderscorePos := 0;
                        for i := 1 to StrLen(Prefix) do
                            if Prefix[i] = '_' then
                                UnderscorePos := i;
                        if UnderscorePos > 0 then begin
                            ResolvedEmail := CopyStr(Prefix, 1, UnderscorePos - 1) + '@' + CopyStr(Prefix, UnderscorePos + 1);
                            HomeDomain := CopyStr(Prefix, UnderscorePos + 1);
                        end else begin
                            ResolvedEmail := Prefix;
                            HomeDomain := 'FAIL: could not parse domain from EXT UPN';
                        end;
                    end else begin
                        ResolvedEmail := AuthEmailLocal;
                        AtPos := StrPos(AuthEmailLocal, '@');
                        if AtPos > 0 then
                            HomeDomain := CopyStr(AuthEmailLocal, AtPos + 1)
                        else
                            HomeDomain := 'FAIL: no @ in email';
                    end;

                    // Find App Registration - no SingleInstance involved
                    if AppReg.ResolveForDomain(HomeDomain) then begin
                        AppRegFound := AppReg."Code";
                        AppRegAppId := AppReg."App ID";
                        AppRegTenantId := AppReg."Tenant ID";
                        SecretStatus := AppReg."Client Secret Status";
                    end else
                        AppRegFound := 'FAIL: no App Registration found for domain: ' + HomeDomain;
                end;
            }
            action(DoStep2)
            {
                ApplicationArea = All;
                Caption = 'Step 2: Token + Ping';
                Image = TestReport;

                trigger OnAction()
                var
                    AppReg: Record "W365 App Registration";
                    OAuthClientApp: Codeunit "OAuth Client Application KFM";
                    MicrosoftEntraID: Codeunit "Microsoft Entra ID KFM";
                    ClientCredFlow: Codeunit "Client Credentials Flow KFM";
                    HttpAuthOAuth2: Codeunit "Http Authentication OAuth2 KFM";
                    OAuthAuthority: Interface "OAuth Authority KFM";
                    OAuthAuthorizationFlow: Interface "OAuth Authorization Flow KFM";
                    HttpAuthentication: Interface "Http Authentication";
                    Client: Codeunit "Rest Client";
                    HttpResponseMessage: Codeunit "Http Response Message";
                    ClientSecret: Text;
                    ClientSecretAsSecret: SecretText;
                    OrgEndpoint: Label 'https://graph.microsoft.com/v1.0/organization?$select=id', Locked = true;
                begin
                    Clear(PingStatus);
                    Clear(PingResult);

                    if AppRegFound = '' then begin
                        PingResult := 'Run Step 1 first.';
                        exit;
                    end;

                    if not AppReg.Get(AppRegFound) then begin
                        PingResult := 'FAIL: AppReg.Get failed for: ' + AppRegFound;
                        exit;
                    end;

                    if not AppReg.GetClientSecret(ClientSecret) then begin
                        PingResult := 'FAIL: No client secret stored.';
                        exit;
                    end;

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
                    Client.Initialize(HttpAuthentication);

                    if not TryGet(Client, OrgEndpoint, HttpResponseMessage) then begin
                        PingStatus := -1;
                        PingResult := 'EXCEPTION: ' + GetLastErrorText();
                        exit;
                    end;

                    PingStatus := HttpResponseMessage.GetHttpStatusCode();
                    PingResult := HttpResponseMessage.GetContent().AsText();
                end;
            }
            action(DoStep3)
            {
                ApplicationArea = All;
                Caption = 'Step 3: Send Email';
                Image = SendMail;

                trigger OnAction()
                var
                    AppReg: Record "W365 App Registration";
                    OAuthClientApp: Codeunit "OAuth Client Application KFM";
                    MicrosoftEntraID: Codeunit "Microsoft Entra ID KFM";
                    ClientCredFlow: Codeunit "Client Credentials Flow KFM";
                    HttpAuthOAuth2: Codeunit "Http Authentication OAuth2 KFM";
                    OAuthAuthority: Interface "OAuth Authority KFM";
                    OAuthAuthorizationFlow: Interface "OAuth Authorization Flow KFM";
                    HttpAuthentication: Interface "Http Authentication";
                    Client: Codeunit "Rest Client";
                    HttpResponseMessage: Codeunit "Http Response Message";
                    HttpContent: Codeunit "Http Content";
                    ClientSecret: Text;
                    ClientSecretAsSecret: SecretText;
                    JsonBody: Text;
                    Endpoint: Text;
                    EndpointTpl: Label 'https://graph.microsoft.com/v1.0/users/%1/sendMail', Locked = true;
                begin
                    Clear(SendStatus);
                    Clear(SendResult);

                    if SendToAddress = '' then begin
                        SendResult := 'Enter a Send To address first.';
                        exit;
                    end;
                    if ResolvedEmail = '' then begin
                        SendResult := 'Run Step 1 first.';
                        exit;
                    end;
                    if AppRegFound = '' then begin
                        SendResult := 'Run Step 1 first.';
                        exit;
                    end;

                    if not AppReg.Get(AppRegFound) then begin
                        SendResult := 'FAIL: AppReg.Get failed.';
                        exit;
                    end;

                    if not AppReg.GetClientSecret(ClientSecret) then begin
                        SendResult := 'FAIL: No client secret.';
                        exit;
                    end;

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
                    Client.Initialize(HttpAuthentication);

                    Endpoint := StrSubstNo(EndpointTpl, ResolvedEmail);
                    JsonBody := '{"message":{"subject":"BC Diag Test","body":{"contentType":"Text","content":"Test from W365 Diagnostics."},"toRecipients":[{"emailAddress":{"address":"' + SendToAddress + '"}}]},"saveToSentItems":true}';
                    HttpContent := HttpContent.Create(JsonBody, 'application/json');

                    if not TryPost(Client, Endpoint, HttpContent, HttpResponseMessage) then begin
                        SendStatus := -1;
                        SendResult := 'EXCEPTION: ' + GetLastErrorText();
                        exit;
                    end;

                    SendStatus := HttpResponseMessage.GetHttpStatusCode();
                    SendResult := 'Endpoint: ' + Endpoint + ' | Response: ' + HttpResponseMessage.GetContent().AsText();
                end;
            }
        }
        area(Promoted)
        {
            actionref(DoStep1_Promoted; DoStep1) { }
            actionref(DoStep2_Promoted; DoStep2) { }
            actionref(DoStep3_Promoted; DoStep3) { }
        }
    }

    [TryFunction]
    local procedure TryGet(var Client: Codeunit "Rest Client"; Url: Text; var Response: Codeunit "Http Response Message")
    begin
        Response := Client.Get(Url);
    end;

    [TryFunction]
    local procedure TryPost(var Client: Codeunit "Rest Client"; Url: Text; var Content: Codeunit "Http Content"; var Response: Codeunit "Http Response Message")
    begin
        Response := Client.Post(Url, Content);
    end;

    var
        AuthEmail: Text;
        ResolvedEmail: Text;
        HomeDomain: Text;
        AppRegFound: Text;
        AppRegAppId: Text;
        AppRegTenantId: Text;
        SecretStatus: Text;
        PingStatus: Integer;
        PingResult: Text;
        SendToAddress: Text;
        SendStatus: Integer;
        SendResult: Text;
}
