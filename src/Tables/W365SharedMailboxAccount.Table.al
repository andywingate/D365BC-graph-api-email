namespace Wingate365.GuestEmailAPI;

table 50115 "W365 Shared Mailbox Account"
{
    Caption = 'Shared Mailbox Account';
    DataClassification = SystemMetadata;
    DrillDownPageId = "W365 Shared Mailbox Accounts";
    LookupPageId = "W365 Shared Mailbox Accounts";

    fields
    {
        field(1; "Code"; Code[20])
        {
            Caption = 'Code';
            DataClassification = SystemMetadata;
            NotBlank = true;
        }
        field(2; "Display Name"; Text[100])
        {
            Caption = 'Display Name';
            DataClassification = SystemMetadata;
        }
        field(3; "Mailbox Email"; Text[250])
        {
            Caption = 'Mailbox Email';
            DataClassification = SystemMetadata;
            // The UPN or SMTP address of the shared mailbox, e.g. sales@contoso.com
        }
        field(4; "App Registration Code"; Code[20])
        {
            Caption = 'App Registration';
            DataClassification = SystemMetadata;
            TableRelation = "W365 App Registration"."Code";
        }
        field(5; "Description"; Text[250])
        {
            Caption = 'Description';
            DataClassification = SystemMetadata;
        }
    }

    keys
    {
        key(PK; "Code")
        {
            Clustered = true;
        }
    }

    /// <summary>
    /// Returns the Graph sendMail endpoint for this shared mailbox.
    /// Format: POST /v1.0/users/{mailboxEmail}/sendMail
    /// </summary>
    procedure GetSendMailEndpoint(): Text
    begin
        exit('https://graph.microsoft.com/v1.0/users/' + Rec."Mailbox Email" + '/sendMail');
    end;

    /// <summary>
    /// Returns the App Registration linked to this shared mailbox.
    /// Errors if not found.
    /// </summary>
    procedure GetAppRegistration(var AppReg: Record "W365 App Registration")
    var
        NotFoundErr: Label 'App Registration %1 not found for shared mailbox %2. Open the Shared Mailbox Account and check the App Registration field.', Comment = '%1 = app reg code, %2 = mailbox code';
    begin
        if not AppReg.Get(Rec."App Registration Code") then
            Error(NotFoundErr, Rec."App Registration Code", Rec."Code");
    end;
}
