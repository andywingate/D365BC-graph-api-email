namespace Wingate365.GuestEmailAPI;

page 50113 "W365 App Registration Card"
{
    Caption = 'App Registration';
    PageType = Card;
    SourceTable = "W365 App Registration";
    UsageCategory = None;
    ApplicationArea = All;

    layout
    {
        area(content)
        {
            group(General)
            {
                Caption = 'General';

                field("Code"; Rec."Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Short identifier for this app registration (e.g. CONTOSO or DEFAULT).';
                }
                field("Description"; Rec."Description")
                {
                    ApplicationArea = All;
                    ToolTip = 'Descriptive name for this registration.';
                }
            }
            group(EntraApp)
            {
                Caption = 'Entra App Registration';

                field("App ID"; Rec."App ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'The Application (Client) ID from the Azure portal app registration overview. Must be a GUID, e.g. deda566a-3ed3-4b8e-9238-e1eb3665c3f7.';

                    trigger OnValidate()
                    var
                        NotGuidErr: Label 'App (Client) ID must be a valid GUID (e.g. deda566a-3ed3-4b8e-9238-e1eb3665c3f7). The value entered looks incorrect - check that browser autofill has not replaced this field.';
                        ParsedGuid: Guid;
                    begin
                        if Rec."App ID" = '' then
                            exit;
                        if not Evaluate(ParsedGuid, Rec."App ID") then
                            Error(NotGuidErr);
                    end;
                }
                field("Tenant ID"; Rec."Tenant ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'The Tenant ID to authenticate against. Leave blank or enter common for multi-tenant. Enter a specific GUID to restrict to one home tenant.';
                }
                field("Redirect URI"; Rec."Redirect URI")
                {
                    ApplicationArea = All;
                    ToolTip = 'The redirect URI registered on the Entra app. Recommended: https://businesscentral.dynamics.com/OAuthLanding.htm';
                }
                field("Domain Filter"; Rec."Domain Filter")
                {
                    ApplicationArea = All;
                    ToolTip = 'The home email domain of users who will use this registration. Example: contoso.com. Must be unique across all registrations.';
                    ShowMandatory = true;

                    trigger OnValidate()
                    var
                        OtherReg: Record "W365 App Registration";
                        DuplicateErr: Label 'Domain Filter %1 is already used by App Registration %2. Each registration must have a unique domain.', Comment = '%1 = domain, %2 = code';
                        BlankErr: Label 'Domain Filter is required. Enter the home email domain for users of this registration (e.g. contoso.com).';
                    begin
                        if Rec."Domain Filter" = '' then
                            Error(BlankErr);
                        OtherReg.SetRange("Domain Filter", Rec."Domain Filter");
                        OtherReg.SetFilter("Code", '<>%1', Rec."Code");
                        if OtherReg.FindFirst() then
                            Error(DuplicateErr, Rec."Domain Filter", OtherReg."Code");
                    end;
                }
            }
            group(ClientSecretGroup)
            {
                Caption = 'Client Secret';

                field("Client Secret Status"; Rec."Client Secret Status")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Shows whether a client secret has been stored. Use Set Client Secret to configure it.';
                }
                field(ClientSecretInput; ClientSecretText)
                {
                    ApplicationArea = All;
                    Caption = 'Enter New Client Secret';
                    ExtendedDatatype = Masked;
                    ToolTip = 'Paste the client secret value here and press Tab or Enter. The value is stored encrypted and cannot be read back.';

                    trigger OnValidate()
                    var
                        SecretSavedMsg: Label 'Client secret saved.';
                    begin
                        if ClientSecretText <> '' then begin
                            Rec.SetClientSecret(ClientSecretText);
                            ClientSecretText := '';
                            Message(SecretSavedMsg);
                        end;
                    end;
                }
            }
        }
    }

    actions
    {
        area(processing)
        {
            action(TestConnection)
            {
                ApplicationArea = All;
                Caption = 'Test Connection';
                Image = TestReport;
                ToolTip = 'Verifies that the App ID, Tenant ID, and Client Secret are valid by acquiring a token and calling Microsoft Graph.';

                trigger OnAction()
                var
                    GraphMailMgt: Codeunit "W365 Graph Mail Mgt";
                    ErrorText: Text;
                    SuccessMsg: Label 'Connection successful. Microsoft Graph authenticated correctly using the Client Credentials flow.';
                    FailMsg: Label 'Connection failed: %1';
                begin
                    if GraphMailMgt.TestAppRegConnection(Rec."Code", ErrorText) then
                        Message(SuccessMsg)
                    else
                        Message(FailMsg, ErrorText);
                end;
            }
            action(ClearClientSecret)
            {
                ApplicationArea = All;
                Caption = 'Clear Client Secret';
                Image = Delete;
                ToolTip = 'Removes the stored client secret for this registration.';

                trigger OnAction()
                var
                    ConfirmMsg: Label 'Are you sure you want to clear the stored client secret for this registration?';
                begin
                    if Confirm(ConfirmMsg) then begin
                        Rec.ClearClientSecret();
                        CurrPage.Update(false);
                    end;
                end;
            }
        }
        area(Promoted)
        {
            actionref(TestConnection_Promoted; TestConnection) { }
            actionref(ClearClientSecret_Promoted; ClearClientSecret) { }
        }
    }

    var
        ClientSecretText: Text;
}
