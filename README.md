![logo][]
# ExchangeLogs - Getting the insights

A PowerShell module for parsing exchange transport log files on further investigation.

Basically, the module only contains only one command:

    Get-ELExchangeLog

This command takes single logfile, hole folders or folder structures with logfiles, parse trough the files and put out an valid an flatten parseable object.
Anyboday, who tried to read native transport log files in exchange, will know, how much it is worth to have an single line/ single object which can be exported to a csv, xml or spit out into an database for later analytical processing.

## Usage
Basically, the intended usage is a construct of

    dir *logfolder* | Get-ELExchangeLog | Export-CSV

or somthing like

    $logRecords = dir *logfolder* | Get-ELExchangeLog
    $logRecords | ft
    $logRecords | ogv
    $logRecords | select-object * -ExcludeProperty LogText | Out-GridView

Due to mostly heavy data activity in the logfiles/ -folders, it is not recommended, to use Get-ELExchangeLog in a repetitive manner.
Better put the result into a variable an work with the results in the variable.

## Installation
Install the module from the PowerShell Gallery (systemwide):

    Install-Module ExchangeLogs

or install it only for your user:

    Install-Module ExchangeLogs -Scope CurrentUser

## Notes
All cmdlets are build with
- powershell regular verbs
- pipeling availabilties
- comprehensive logging on verbose and debug channel


[logo]: assets/ExchangeLog_128x128.png