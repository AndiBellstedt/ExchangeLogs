function Initialize-LogFile {
<#
    .SYNOPSIS
        Test for valid file and set PSF Logging provider

    .DESCRIPTION
        Test for valid file and create logfil directory if needed

    .PARAMETER LogFile
        Name of the LogType from the meta data line in a logfile

    .PARAMETER AlternateLogName
        An alternative name, if the provided logfile is only a directory, without filename

    .PARAMETER LogInstanceName
        The name of the Instance for the PSFramework logfile logging provider

    .EXAMPLE
        PS C:\> Initialize-LogFile -LogFile $LogFile -AlternateLogName $MyInvocation.MyCommand

        Test for valid file and create logfil directory if needed
#>
    [CmdletBinding()]
    param (
        $LogFile,

        $AlternateLogName,

        $LogInstanceName
    )

    if (Test-Path -Path $LogFile -IsValid) {
        if (Test-Path -Path $LogFile -PathType Container) {
            $LogFile = Join-Path -Path $LogFile -ChildPath $AlternateLogName
        }

        $logFilePath = Split-Path -Path $LogFile
        if (-not (Test-Path -Path $logFilePath -PathType Container)) {
            try {
                $null = New-Item -Path $logFilePath -ItemType Directory -Force -ErrorAction Stop
            } catch {
                Stop-PSFFunction -Message "Unable to create logfile folder '$($logFilePath)'" -ErrorAction Stop -Tag "ExchangeLogs"
                throw
            }
        }

        # enable logging provider to write logging information (only events with Warning, Critical, Output, Significant, VeryVerbose, Verbose, SomewhatVerbose, System)
        Set-PSFLoggingProvider -Name logfile -InstanceName $LogInstanceName -Enabled $true -FilePath $LogFile -IncludeTags "ExchangeLogs" -MinLevel 1 -MaxLevel 6

    } else {
        Stop-PSFFunction -Message "Invalid Logfile '$($LogFile)' specified." -ErrorAction Stop -Tag "ExchangeLogs"
        throw
    }
}
