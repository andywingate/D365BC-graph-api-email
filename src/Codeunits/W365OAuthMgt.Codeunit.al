namespace Wingate365.GuestEmailAPI;

codeunit 50106 "W365 OAuth Mgt"
{
    Access = Internal;

    // -------------------------------------------------------------------------
    // IsolatedStorage keys
    // -------------------------------------------------------------------------
    // 'W365_CS'    - client secret for W365 Email Setup (Text, DataScope::Company) - set by admin

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /// <summary>
    /// Stores the client secret in Company-scoped IsolatedStorage.
    /// Called from the Email Setup Card. The value is never read back to the UI.
    /// </summary>
    procedure SetClientSecret(ClientSecretValue: Text)
    begin
        IsolatedStorage.Set('W365_CS', ClientSecretValue, DataScope::Company);
    end;

    /// <summary>
    /// Returns true if a client secret has been configured (does not return the value).
    /// </summary>
    procedure HasClientSecret(): Boolean
    begin
        exit(IsolatedStorage.Contains('W365_CS', DataScope::Company));
    end;

    /// <summary>
    /// Clears the current user's delegated session, forcing re-authentication on the next send.
    /// Also clears the metadata token record so the admin view is up to date.
    /// </summary>
    procedure ClearTokens()
    var
        GraphSession: Codeunit "W365 Graph Session";
        UserToken: Record "W365 User Email Token";
        UserName: Code[50];
    begin
        // Clear all cached Auth Code Grant clients for this session.
        // The next send will trigger a fresh interactive sign-in popup.
        GraphSession.ClearAllGuestSessions();

        UserName := CopyStr(UserId(), 1, MaxStrLen(UserName));
        if UserToken.Get(UserName) then begin
            UserToken."Token Expiry" := 0DT;
            UserToken."Last Error" := '';
            UserToken.Modify();
        end;
    end;

    // -------------------------------------------------------------------------
    // Utilities
    // -------------------------------------------------------------------------

    internal procedure ExtractQueryParam(Url: Text; ParamName: Text): Text
    var
        SearchKey: Text;
        StartPos: Integer;
        Value: Text;
        AmpPos: Integer;
    begin
        SearchKey := ParamName + '=';
        StartPos := StrPos(Url, SearchKey);
        if StartPos = 0 then
            exit('');

        Value := CopyStr(Url, StartPos + StrLen(SearchKey));
        AmpPos := StrPos(Value, '&');
        if AmpPos > 0 then
            Value := CopyStr(Value, 1, AmpPos - 1);

        exit(Value);
    end;
}
