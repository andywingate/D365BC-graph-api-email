namespace Wingate365.GuestEmailAPI;

enum 50100 "W365 Consent Status"
{
    Caption = 'Consent Status';
    Extensible = false;

    value(0; None)
    {
        Caption = 'None';
    }
    value(1; Active)
    {
        Caption = 'Active';
    }
    value(2; Error)
    {
        Caption = 'Error';
    }
}
