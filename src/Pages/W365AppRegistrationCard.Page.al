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
                field("Is Default"; Rec."Is Default")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'The default registration is the fallback when no domain filter matches. Use Set as Default action to change this.';
                }
            }
            group(EntraApp)
            {
                Caption = 'Entra App Registration';

                field("App ID"; Rec."App ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'The Application (Client) ID from the Azure portal app registration overview.';
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
                    ToolTip = 'Users whose home email domain matches this value will authenticate using this registration. Example: contoso.com. Leave blank on the default registration.';
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
            action(SetAsDefault)
            {
                ApplicationArea = All;
                Caption = 'Set as Default';
                Image = Default;
                ToolTip = 'Makes this the fallback registration for users whose domain does not match any other.';

                trigger OnAction()
                begin
                    Rec.SetAsDefault();
                    CurrPage.Update(false);
                end;
            }
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
            actionref(SetAsDefault_Promoted; SetAsDefault) { }
            actionref(ClearClientSecret_Promoted; ClearClientSecret) { }
        }
    }

    var
        ClientSecretText: Text;
}
