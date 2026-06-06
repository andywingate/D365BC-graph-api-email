namespace Wingate365.GuestEmailAPI;

using System.Email;

enumextension 50100 "W365 Guest Email Connector" extends "Email Connector"
{
    value(50100; "W365 Guest Email")
    {
        Caption = 'Current User (Microsoft Graph)';
        Implementation = "Email Connector" = "W365 Guest Email Connector",
                         "Email Connector v4" = "W365 Guest Email Connector",
                         "Default Email Rate Limit" = "W365 Guest Email Connector";
    }
}
