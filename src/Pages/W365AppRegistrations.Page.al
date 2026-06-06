namespace Wingate365.GuestEmailAPI;

page 50112 "W365 App Registrations"
{
    Caption = 'App Registrations';
    PageType = List;
    SourceTable = "W365 App Registration";
    UsageCategory = None;
    ApplicationArea = All;
    CardPageId = "W365 App Registration Card";
    Editable = false;

    layout
    {
        area(content)
        {
            repeater(Registrations)
            {
                field("Code"; Rec."Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Short identifier for this app registration.';
                }
                field("Description"; Rec."Description")
                {
                    ApplicationArea = All;
                    ToolTip = 'Descriptive name for this app registration.';
                }
                field("App ID"; Rec."App ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'The Application (Client) ID from the Entra app registration.';
                }
                field("Tenant ID"; Rec."Tenant ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'The Tenant ID to authenticate against. Leave blank or set to common for multi-tenant.';
                }
                field("Domain Filter"; Rec."Domain Filter")
                {
                    ApplicationArea = All;
                    ToolTip = 'Users whose home email domain matches this value will use this registration. Leave blank on the default.';
                }
                field("Is Default"; Rec."Is Default")
                {
                    ApplicationArea = All;
                    ToolTip = 'The default registration is used when no domain filter matches.';
                }
                field("Client Secret Status"; Rec."Client Secret Status")
                {
                    ApplicationArea = All;
                    ToolTip = 'Shows whether a client secret has been stored for this registration.';
                }
            }
        }
    }

    actions
    {
        area(processing)
        {
            action(SetDefault)
            {
                ApplicationArea = All;
                Caption = 'Set as Default';
                Image = Default;
                ToolTip = 'Marks this registration as the fallback for users whose domain does not match any other registration.';

                trigger OnAction()
                begin
                    Rec.SetAsDefault();
                end;
            }
        }
        area(Promoted)
        {
            actionref(SetDefault_Promoted; SetDefault) { }
        }
    }
}
