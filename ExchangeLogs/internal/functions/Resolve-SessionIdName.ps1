function Resolve-SessionIdName {
<#
    .SYNOPSIS
        Converts access tokens to readable objects

    .DESCRIPTION
        Converts access tokens to readable objects

    .PARAMETER LogType
        Name of the LogType from the meta data line in a logfile

    .EXAMPLE
        PS C:\> Resolve-SessionIdName -LogType "SMTP Receive Protocol Log"

        Returns the name of the grouping field for building record groups
#>
    [CmdletBinding()]
    param (
        $LogType
    )

    switch ($LogType) {
        {$_ -in "SMTP Receive Protocol Log", "SMTP Send Protocol Log"} { "session-Id" }
        {$_ -in "IMAP4 Log", "POP3 Log"} { "sessionId" }
        {$_ -in "Message Tracking Log"} { "message-id" }
        Default { Write-Warning "Unknown LogType"}
    }
}
