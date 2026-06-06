namespace Wingate365.GuestEmailAPI;

page 50117 "W365 Shared Mailbox Card"
{
    Caption = 'Shared Mailbox Account';
    PageType = Card;
    SourceTable = "W365 Shared Mailbox Account";
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
                    ToolTip = 'Short identifier for this shared mailbox account (e.g. SALES or SUPPORT).';
                }
                field("Display Name"; Rec."Display Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'Display name shown in the Email Accounts page.';
                }
                field("Description"; Rec."Description")
                {
                    ApplicationArea = All;
                    ToolTip = 'Optional description.';
                }
            }
            group(MailboxDetails)
            {
                Caption = 'Mailbox';

                field("Mailbox Email"; Rec."Mailbox Email")
                {
                    ApplicationArea = All;
                    ToolTip = 'The UPN or SMTP address of the shared mailbox (e.g. sales@contoso.com). The sending user must have delegated Send As or Send on Behalf access to this mailbox in Exchange/M365.';
                }
                field("App Registration Code"; Rec."App Registration Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'The App Registration to use for OAuth authentication when sending from this mailbox. The registration must have Mail.Send.Shared delegated permission.';
                }
            }
        }
    }

    actions
    {
        area(processing)
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
            actionref(AppRegistrationsRef; AppRegistrations) { }
        }
    }
}
