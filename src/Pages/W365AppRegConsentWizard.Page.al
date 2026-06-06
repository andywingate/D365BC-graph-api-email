namespace Wingate365.GuestEmailAPI;

/// <summary>
/// Guides an admin through creating an App Registration:
///   1. Enter App ID and Tenant ID
///   2. Click Grant Admin Consent - opens the Microsoft consent URL in the browser
///   3. Click Continue - record is created and the card opens for Code, Description,
///      Domain Filter, and Client Secret
/// </summary>
page 50120 "W365 App Reg Consent Wizard"
{
    Caption = 'Add App Registration';
    PageType = Card;
    SourceTable = "W365 App Registration";
    SourceTableTemporary = true;
    UsageCategory = None;
    ApplicationArea = All;

    layout
    {
        area(content)
        {
            group(Step1)
            {
                Caption = 'Step 1 - Entra App Details';

                field("App ID"; Rec."App ID")
                {
                    ApplicationArea = All;
                    Caption = 'App (Client) ID';
                    ToolTip = 'The Application (Client) ID from the Azure portal app registration overview. Must be a GUID.';
                    ShowMandatory = true;

                    trigger OnValidate()
                    var
                        NotGuidErr: Label 'App (Client) ID must be a valid GUID (e.g. deda566a-3ed3-4b8e-9238-e1eb3665c3f7).';
                        ParsedGuid: Guid;
                    begin
                        if Rec."App ID" <> '' then
                            if not Evaluate(ParsedGuid, Rec."App ID") then
                                Error(NotGuidErr);
                    end;
                }
                field("Tenant ID"; Rec."Tenant ID")
                {
                    ApplicationArea = All;
                    Caption = 'Tenant ID';
                    ToolTip = 'The Tenant ID (Directory ID) of the home tenant. Found on the Entra ID overview page in the Azure portal.';
                    ShowMandatory = true;
                }
                field("Redirect URI"; Rec."Redirect URI")
                {
                    ApplicationArea = All;
                    Caption = 'Redirect URI';
                    ToolTip = 'The redirect URI registered on the Entra app. Default: https://businesscentral.dynamics.com/OAuthLanding.htm';
                }
            }
            group(Step2)
            {
                Caption = 'Step 2 - Grant Admin Consent';

                group(ConsentInstructions)
                {
                    ShowCaption = false;

                    label(InstructionLbl)
                    {
                        ApplicationArea = All;
                        Caption = 'Click Grant Admin Consent below. A browser window will open asking you to sign in as a Global Administrator of the home tenant and approve the Mail.Send permission. Return here after approving.';
                        Style = StandardAccent;
                    }
                }
            }
        }
    }

    actions
    {
        area(processing)
        {
            action(GrantConsent)
            {
                ApplicationArea = All;
                Caption = 'Grant Admin Consent';
                Image = Approve;
                ToolTip = 'Opens the Microsoft admin consent page in your browser. Sign in as a Global Admin of the home tenant and click Accept.';
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    ConsentUrl: Text;
                    MissingFieldErr: Label 'Enter App (Client) ID and Tenant ID before granting consent.';
                    DefaultRedirectUri: Label 'https://businesscentral.dynamics.com/OAuthLanding.htm', Locked = true;
                    RedirectUri: Text;
                begin
                    if (Rec."App ID" = '') or (Rec."Tenant ID" = '') then
                        Error(MissingFieldErr);

                    RedirectUri := Rec."Redirect URI";
                    if RedirectUri = '' then
                        RedirectUri := DefaultRedirectUri;

                    ConsentUrl := 'https://login.microsoftonline.com/' + Rec."Tenant ID" +
                        '/adminconsent?client_id=' + Rec."App ID" +
                        '&redirect_uri=' + RedirectUri;

                    Hyperlink(ConsentUrl);
                end;
            }
            action(Continue)
            {
                ApplicationArea = All;
                Caption = 'Continue';
                Image = NextRecord;
                ToolTip = 'Save these details and open the App Registration card to complete setup (Code, Description, Domain Filter, and Client Secret).';
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    AppReg: Record "W365 App Registration";
                    MissingFieldErr: Label 'Enter App (Client) ID and Tenant ID before continuing.';
                    DefaultRedirectUri: Label 'https://businesscentral.dynamics.com/OAuthLanding.htm', Locked = true;
                begin
                    if (Rec."App ID" = '') or (Rec."Tenant ID" = '') then
                        Error(MissingFieldErr);

                    AppReg.Init();
                    AppReg."App ID" := Rec."App ID";
                    AppReg."Tenant ID" := Rec."Tenant ID";
                    AppReg."Redirect URI" := Rec."Redirect URI";
                    if AppReg."Redirect URI" = '' then
                        AppReg."Redirect URI" := DefaultRedirectUri;
                    AppReg.Insert();

                    Page.Run(Page::"W365 App Registration Card", AppReg);
                    CurrPage.Close();
                end;
            }
        }
    }

    trigger OnOpenPage()
    var
        DefaultRedirectUri: Label 'https://businesscentral.dynamics.com/OAuthLanding.htm', Locked = true;
    begin
        Rec.Init();
        Rec."Redirect URI" := DefaultRedirectUri;
        Rec.Insert();
    end;
}
