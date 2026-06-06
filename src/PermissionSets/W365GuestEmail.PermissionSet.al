namespace Wingate365.GuestEmailAPI;

permissionset 50109 "W365 Guest Email"
{
    Caption = 'Graph API Emailing';
    Assignable = true;

    Permissions =
        tabledata "W365 Email Setup" = R,
        tabledata "W365 User Email Token" = RIMD,
        tabledata "W365 App Registration" = RIMD,
        page "W365 Email Setup Card" = X,
        page "W365 User Token List" = X,
        page "W365 OAuth Consent" = X,
        page "W365 App Registrations" = X,
        page "W365 App Registration Card" = X,
        codeunit "W365 Graph Mail Mgt" = X,
        codeunit "W365 OAuth Mgt" = X,
        codeunit "W365 Guest Email Connector" = X;
}
