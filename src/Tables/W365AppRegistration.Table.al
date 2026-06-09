namespace Wingate365.GuestEmailAPI;

table 50111 "W365 App Registration"
{
    Caption = 'App Registration';
    DataClassification = SystemMetadata;
    DrillDownPageId = "W365 App Registrations";
    LookupPageId = "W365 App Registrations";

    fields
    {
        field(1; "Code"; Code[20])
        {
            Caption = 'Code';
            DataClassification = SystemMetadata;
            NotBlank = true;
        }
        field(2; "Description"; Text[100])
        {
            Caption = 'Description';
            DataClassification = SystemMetadata;
        }
        field(3; "App ID"; Text[100])
        {
            Caption = 'App (Client) ID';
            DataClassification = SystemMetadata;
        }
        field(4; "Tenant ID"; Text[100])
        {
            Caption = 'Tenant ID';
            DataClassification = SystemMetadata;
            // Blank or 'common' = multi-tenant. Set to a specific tenant GUID to restrict to one home tenant.
        }
        field(5; "Domain Filter"; Text[250])
        {
            Caption = 'Domain Filter';
            DataClassification = SystemMetadata;
            NotBlank = true;
            // Required. e.g. 'contoso.com'. Users whose home email domain matches this value
            // will authenticate using this registration. Must be unique across all registrations.
        }
        field(6; "Is Default"; Boolean)
        {
            Caption = 'Is Default';
            DataClassification = SystemMetadata;
            // Only one registration may be default. Enforced via SetAsDefault().
        }
        field(7; "Redirect URI"; Text[250])
        {
            Caption = 'Redirect URI';
            DataClassification = SystemMetadata;
        }
        field(8; "Client Secret Status"; Text[30])
        {
            Caption = 'Client Secret Status';
            DataClassification = SystemMetadata;
            Editable = false;
        }
    }

    keys
    {
        key(PK; "Code")
        {
            Clustered = true;
        }
        key(DomainFilter; "Domain Filter")
        {
        }
        key(IsDefault; "Is Default")
        {
        }
    }

    /// <summary>
    /// Returns the App Registration that should be used for a given user email domain.
    /// Returns true and assigns the matching record to Rec when an exact Domain Filter match is found.
    /// Returns false if no match is found.
    /// </summary>
    procedure ResolveForDomain(HomeDomain: Text): Boolean
    var
        AppReg: Record "W365 App Registration";
    begin
        if HomeDomain = '' then
            exit(false);

        AppReg.SetRange("Domain Filter", HomeDomain);
        if AppReg.FindFirst() then begin
            Rec := AppReg;
            exit(true);
        end;

        exit(false);
    end;

    /// <summary>
    /// Sets this registration as the default, clearing the flag on any other.
    /// </summary>
    procedure SetAsDefault()
    var
        OtherReg: Record "W365 App Registration";
    begin
        OtherReg.SetRange("Is Default", true);
        OtherReg.SetFilter("Code", '<>%1', Rec."Code");
        if OtherReg.FindSet(true) then
            repeat
                OtherReg."Is Default" := false;
                OtherReg.Modify();
            until OtherReg.Next() = 0;

        Rec."Is Default" := true;
        Rec.Modify();
    end;

    /// <summary>
    /// Stores the client secret for this registration in IsolatedStorage (encrypted, company scope).
    /// Keyed per App ID so multiple registrations can each have their own secret.
    /// </summary>
    procedure SetClientSecret(SecretValue: Text)
    var
        StorageKey: Text;
        ConfiguredLbl: Label 'Configured';
        AppIdRequiredErr: Label 'App (Client) ID is required before storing a client secret.';
    begin
        if Rec."App ID" = '' then
            Error(AppIdRequiredErr);

        StorageKey := 'W365_CS_' + Rec."App ID";
        IsolatedStorage.Set(StorageKey, SecretValue, DataScope::Company);
        Rec."Client Secret Status" := ConfiguredLbl;
        Rec.Modify();
    end;

    /// <summary>
    /// Retrieves the client secret for this registration from IsolatedStorage.
    /// Returns false if not found.
    /// </summary>
    procedure GetClientSecret(var SecretValue: Text): Boolean
    var
        StorageKey: Text;
    begin
        StorageKey := 'W365_CS_' + Rec."App ID";
        exit(IsolatedStorage.Get(StorageKey, DataScope::Company, SecretValue));
    end;

    /// <summary>
    /// Deletes the client secret for this registration from IsolatedStorage.
    /// </summary>
    procedure ClearClientSecret()
    var
        StorageKey: Text;
        NotConfiguredLbl: Label 'Not configured';
    begin
        StorageKey := 'W365_CS_' + Rec."App ID";
        if IsolatedStorage.Contains(StorageKey, DataScope::Company) then
            IsolatedStorage.Delete(StorageKey, DataScope::Company);
        Rec."Client Secret Status" := NotConfiguredLbl;
        Rec.Modify();
    end;

    /// <summary>
    /// Returns the authority tenant to use in the OAuth URL for Client Credentials.
    /// Used by the Shared Mailbox connector. Requires a specific tenant GUID.
    /// </summary>
    procedure GetAuthorityTenant(): Text
    var
        TenantRequiredErr: Label 'Tenant ID is required for Client Credentials authentication (Shared Mailbox connector). Enter the directory tenant GUID on this App Registration.';
    begin
        if Rec."Tenant ID" = '' then
            Error(TenantRequiredErr);

        exit(Rec."Tenant ID");
    end;

    /// <summary>
    /// Returns the authority tenant to use for the Authorization Code Grant (delegated) flow.
    /// Returns 'common' when Tenant ID is blank, enabling multi-tenant / B2B guest sign-in.
    /// Set Tenant ID to a specific GUID to restrict sign-in to a single home tenant.
    /// </summary>
    procedure GetDelegatedTenant(): Text
    begin
        if Rec."Tenant ID" = '' then
            exit('common');

        exit(Rec."Tenant ID");
    end;
}
