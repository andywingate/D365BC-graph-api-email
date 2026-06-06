namespace Wingate365.GuestEmailAPI;

using System.RestClient;
using System.Security.AccessControl;
using Microsoft.Identity.Client;

/// <summary>
/// SingleInstance codeunit that holds initialised Rest Client instances for the BC session.
/// Uses the Client Credentials (app-only) OAuth flow - runs fully server-side, no browser
/// interaction required. The App Registration must have Mail.Send application permission
/// granted in Azure. Tokens are cached in-memory by the RestClientOAuth library for the
/// duration of their lifetime (typically 1 hour).
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
        ClientCredFlow: Codeunit "Client Credentials Flow KFM";
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

        // Build OAuth Client Application (client ID + secret + scope)
        OAuthClientApp.SetClientId(AppReg."App ID");
        ClientSecretAsSecret := ClientSecret;
        OAuthClientApp.SetClientSecret(ClientSecretAsSecret);
        OAuthClientApp.AddScope('https://graph.microsoft.com/.default');

        // Authority - tenant-specific (client credentials must use a specific tenant, not 'common')
        MicrosoftEntraID.SetTenantID(AppReg.GetAuthorityTenant());
        OAuthAuthority := MicrosoftEntraID;

        // Client Credentials flow - fully server-side, no browser interaction required.
        // Requires Mail.Send APPLICATION permission granted in Azure portal.
        ClientCredFlow.SetAuthority(OAuthAuthority);
        OAuthAuthorizationFlow := ClientCredFlow;

        // Initialise Http Authentication and Rest Client
        HttpAuthOAuth2.Initialize(OAuthClientApp, OAuthAuthorizationFlow);
        HttpAuthentication := HttpAuthOAuth2;
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
    /// Returns true and assigns the record to AppReg when a matching registration is found.
    /// Returns false if the home domain cannot be detected or no matching registration exists.
    /// </summary>
    procedure ResolveAppRegForCurrentUser(var AppReg: Record "W365 App Registration"): Boolean
    var
        HomeDomain: Text;
    begin
        HomeDomain := DetectHomeDomain();
        exit(AppReg.ResolveForDomain(HomeDomain));
    end;

    /// <summary>
    /// Decodes a BC Authentication Email to the user's real home email address.
    /// For B2B guests (format: alice_contoso.com#EXT#@host.onmicrosoft.com)
    /// returns alice@contoso.com. For member accounts returns the value unchanged.
    /// </summary>
    procedure ResolveHomeEmail(AuthEmail: Text): Text
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
            // Guest format: alice_contoso.com#EXT#@hosttenant.onmicrosoft.com
            // Prefix before #EXT# is: alice_contoso.com
            // Last underscore separates local part from home domain
            Prefix := CopyStr(AuthEmail, 1, ExtPos - 1);
            UnderscorePos := 0;
            for i := 1 to StrLen(Prefix) do
                if Prefix[i] = '_' then
                    UnderscorePos := i;
            if UnderscorePos > 0 then
                exit(CopyStr(Prefix, 1, UnderscorePos - 1) + '@' + CopyStr(Prefix, UnderscorePos + 1));
            exit(Prefix);
        end;

        // Member account - UPN is already their real email
        exit(AuthEmail);
    end;
}
