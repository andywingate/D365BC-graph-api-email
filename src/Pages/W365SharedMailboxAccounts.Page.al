namespace Wingate365.GuestEmailAPI;

page 50116 "W365 Shared Mailbox Accounts"
{
    Caption = 'Shared Mailbox Accounts';
    PageType = List;
    SourceTable = "W365 Shared Mailbox Account";
    UsageCategory = None;
    ApplicationArea = All;
    CardPageId = "W365 Shared Mailbox Card";
    Editable = false;

    layout
    {
        area(content)
        {
            repeater(Mailboxes)
            {
                field("Code"; Rec."Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Short identifier for this shared mailbox account.';
                }
                field("Display Name"; Rec."Display Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'Display name shown in Email Accounts.';
                }
                field("Mailbox Email"; Rec."Mailbox Email")
                {
                    ApplicationArea = All;
                    ToolTip = 'The UPN or SMTP address of the shared mailbox (e.g. sales@contoso.com).';
                }
                field("App Registration Code"; Rec."App Registration Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'The App Registration used to authenticate when sending from this mailbox.';
                }
                field("Description"; Rec."Description")
                {
                    ApplicationArea = All;
                    ToolTip = 'Optional description of this shared mailbox account.';
                }
            }
        }
    }
}
