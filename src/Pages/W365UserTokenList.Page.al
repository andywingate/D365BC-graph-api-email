namespace Wingate365.GuestEmailAPI;

page 50104 "W365 User Token List"
{
    Caption = 'User Token Status';
    PageType = List;
    SourceTable = "W365 User Email Token";
    UsageCategory = Administration;
    ApplicationArea = All;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = true;

    layout
    {
        area(content)
        {
            repeater(TokenList)
            {
                field("User Name"; Rec."User Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'The BC user name.';
                }
                field("Token Expiry"; Rec."Token Expiry")
                {
                    ApplicationArea = All;
                    ToolTip = 'When the current access token expires. The app refreshes automatically before expiry.';
                }
                field("Last Error"; Rec."Last Error")
                {
                    ApplicationArea = All;
                    ToolTip = 'Last error recorded during token acquisition or refresh.';
                }
                field("Home Email"; Rec."Home Email")
                {
                    ApplicationArea = All;
                    ToolTip = 'The home email address resolved from Microsoft Graph for this user.';
                }
            }
        }
        area(factboxes)
        {
            systempart(Links; Links) { ApplicationArea = RecordLinks; }
            systempart(Notes; Notes) { ApplicationArea = Notes; }
        }
    }

    actions
    {
        area(processing)
        {
            action(ClearToken)
            {
                ApplicationArea = All;
                Caption = 'Clear Token';
                Image = Delete;
                ToolTip = 'Clears the stored token for the current user. They will need to re-authorise before sending email.';

                trigger OnAction()
                var
                    OAuthMgt: Codeunit "W365 OAuth Mgt";
                    ConfirmMsg: Label 'Clear the stored token for the current user? They will need to re-authorise before sending email.';
                begin
                    if Confirm(ConfirmMsg) then begin
                        OAuthMgt.ClearTokens();
                        CurrPage.Update(false);
                    end;
                end;
            }
        }
        area(navigation)
        {
            action(AppRegistrations)
            {
                ApplicationArea = All;
                Caption = 'App Registrations';
                Image = Setup;
                RunObject = Page "W365 App Registrations";
                ToolTip = 'View and manage the Entra app registrations.';
            }
        }
        area(Promoted)
        {
            actionref(ClearTokenRef; ClearToken) { }
        }
    }
}
