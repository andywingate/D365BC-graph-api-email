namespace Wingate365.GuestEmailAPI;

using System.RestClient;
using System.Security.AccessControl;
using System.Security.Authentication;
using Microsoft.Identity.Client;

/// <summary>
/// SingleInstance codeunit that holds initialised Rest Client instances for the BC session.
/// One instance per App Registration code. First call in a session triggers the OAuth consent
/// popup if needed; subsequent calls reuse the in-memory token.
/// Tokens are held in SecretText inside AJ's library - never persisted to IsolatedStorage.
/// </summary>
codeunit 50114 "W365 Graph Session"
{
    Access = Internal;
    SingleInstance = true;

    var
        RestClients: Dictionary of [Code[20], Codeunit "Rest Client"];

    /// <summary>
    /// Returns an initialised Rest Client for the given App Registration.
    /// Initialises a new one if this is the first call in the session for that registration.
    /// </summary>
    procedure GetRestClient(AppRegCode: Code[20]; var Client: Codeunit "Rest Client")
    var
        AppReg: Record "W365 App Registration";
        OAuthClientApp: Codeunit "OAuth Client Application KFM";
        MicrosoftEntraID: Codeunit "Microsoft Entra ID KFM";
        AuthCodeGrantFlow: Codeunit "Auth. Code Grant Flow KFM";
        HttpAuthOAuth2: Codeunit "Http Authentication OAuth2 KFM";
        OAuthAuthority: Interface "OAuth Authority KFM";
        OAuthAuthorizationFlow: Interface "OAuth Authorization Flow KFM";
        HttpAuthentication: Interface "Http Authentication";
        NewClient: Codeunit "Rest Client";
        ClientSecret: Text;
        ClientSecretAsSecret: SecretText;
        NoSecretErr: Label 'No client secret is configured for App Registration %1. Open App Registrations from the Email Account page and set the client secret.', Comment = '%1 = App Registration code';
    begin
        if RestClients.ContainsKey(AppRegCode) then begin
            RestClients.Get(AppRegCode, Client);
            exit;
        end;

        if not AppReg.Get(AppRegCode) then
            Error('App Registration %1 not found.', AppRegCode);

        if not AppReg.GetClientSecret(ClientSecret) then
            Error(NoSecretErr, AppRegCode);

        // Build OAuth Client Application
        OAuthClientApp.SetClientId(AppReg."App ID");
        ClientSecretAsSecret := ClientSecret;
        OAuthClientApp.SetClientSecret(ClientSecretAsSecret);
        OAuthClientApp.SetRedirectUri(AppReg."Redirect URI");
        OAuthClientApp.AddScope('https://graph.microsoft.com/Mail.Send');

        // Authority - use registration tenant ID or 'common'
        MicrosoftEntraID.SetTenantID(AppReg.GetAuthorityTenant());
        OAuthAuthority := MicrosoftEntraID;

        // Auth Code Grant Flow - SSO-first (PromptInteraction::None tries silent first)
        AuthCodeGrantFlow.SetAuthority(OAuthAuthority);
        AuthCodeGrantFlow.SetPromptInteraction(Enum::"Prompt Interaction"::None);
        OAuthAuthorizationFlow := AuthCodeGrantFlow;

        // Initialise Http Authentication
        HttpAuthOAuth2.Initialize(OAuthClientApp, OAuthAuthorizationFlow);
        HttpAuthentication := HttpAuthOAuth2;

        // Initialise Rest Client with authentication
        NewClient.Initialize(HttpAuthentication);

        RestClients.Add(AppRegCode, NewClient);
        Client := NewClient;
    end;

    /// <summary>
    /// Removes the cached Rest Client for the given App Registration.
    /// The next call to GetRestClient will re-initialise and trigger re-authentication.
    /// </summary>
    procedure ClearSession(AppRegCode: Code[20])
    begin
        if RestClients.ContainsKey(AppRegCode) then
            RestClients.Remove(AppRegCode);
    end;

    /// <summary>
    /// Clears all cached Rest Client instances for the session.
    /// </summary>
    procedure ClearAllSessions()
    begin
        Clear(RestClients);
    end;

    /// <summary>
    /// Detects the home email domain of the current BC user.
    /// For Entra B2B guests (format: user_contoso.com#EXT#@host.onmicrosoft.com)
    /// extracts the home domain from the UPN prefix.
    /// For member accounts returns the domain from their email directly.
    /// </summary>
    procedure DetectHomeDomain(): Text
    var
        User: Record User;
        AuthEmail: Text;
        ExtPos: Integer;
        UnderscorePos: Integer;
        AtPos: Integer;
        Domain: Text;
        i: Integer;
    begin
        if not User.Get(UserSecurityId()) then
            exit('');

        AuthEmail := User."Authentication Email";
        if AuthEmail = '' then
            exit('');

        // Guest format: alice_contoso.com#EXT#@hosttenant.onmicrosoft.com
        ExtPos := StrPos(AuthEmail, '#EXT#');
        if ExtPos > 0 then begin
            // Extract prefix before #EXT#, then find last underscore which separates user from domain
            AuthEmail := CopyStr(AuthEmail, 1, ExtPos - 1);
            // Find last underscore - everything after it is the home domain
            UnderscorePos := 0;
            for i := 1 to StrLen(AuthEmail) do
                if AuthEmail[i] = '_' then
                    UnderscorePos := i;

            if UnderscorePos > 0 then begin
                Domain := CopyStr(AuthEmail, UnderscorePos + 1);
                // Domain is like 'contoso.com' - validate it looks like a domain
                if StrPos(Domain, '.') > 0 then
                    exit(Domain);
            end;
            exit('');
        end;

        // Member account - extract domain from email address
        AtPos := StrPos(AuthEmail, '@');
        if AtPos > 0 then
            exit(CopyStr(AuthEmail, AtPos + 1));

        exit('');
    end;

    /// <summary>
    /// Resolves the App Registration for the current user based on their home email domain.
    /// Returns the App Registration code.
    /// </summary>
    procedure ResolveAppRegForCurrentUser(var AppReg: Record "W365 App Registration"): Boolean
    var
        HomeDomain: Text;
    begin
        HomeDomain := DetectHomeDomain();
        exit(AppReg.ResolveForDomain(HomeDomain));
    end;
}
