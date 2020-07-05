function global:Expand-LogRecordPopImap {
    <#
    .SYNOPSIS
        Expand the data from records group into a flat data record

    .DESCRIPTION
        Expand the data from records group into a flat data record

    .PARAMETER InputObject
        The dataset to expand

    .PARAMETER SessionIdName
        The name of the session grouping attribute

    .PARAMETER ShowProgress
        If specified, progress information on record processing is showed

    .PARAMETER IncludeActivityContextData
        Include full exchange internals in POP3 log expansion process.
        There is a lot of internal system information in the logfiles, with unneccessary content for statistical output.
        Suppressing this data is reducing the log footage.

    .EXAMPLE
        PS C:\> Expand-LogRecordPop -InputObject $DataSet

        Expand the data from records group into a flat data record
#>
    [CmdletBinding()]
    param (
        $InputObject,

        [string]
        $SessionIdName = "sessionId",

        [switch]
        $ShowProgress,

        [switch]
        $IncludeActivityContextData
    )

    begin {
        $Error.Clear()
    }

    process {
        if ($ShowProgress) {
            $i = 0
            if ($InputObject.count -lt 100) { $refreshInterval = 1 } else { $refreshInterval = [math]::Round($InputObject.count / 100) }
        }

        foreach ($record in $InputObject) {
            # assure qualified session in log
            $_startIndicator = $record.Group[0] | Where-Object command -like "OpenSession"
            if (-not $_startIndicator) {
                Write-PSFMessage -Level Warning -Message "Detect fragmented record! Missing previous logfile with partital records. Skip processing $($SessionIdName) '$($record.$SessionIdName)' in $($record.LogFolder)\$($record.LogFileName)"
                continue
            }

            # data text record in array, avoids parsing full data array
            $commands = $record.Group.command
            $context = $record.Group.context #| Select-Object -Unique

            # full text log
            $logLines = New-Object -TypeName "System.Collections.ArrayList"
            foreach ($item in $record.Group) {
                $logline = $item.seqNumber + " " + $item.command
                if ($item.parameters.Length -gt 0) {
                    $logline = $logline + " | parameters: " + $item.parameters
                }
                if ($item.context.Length -gt 0) {
                    if (-not $IncludeActivityContextData) {
                        if ($item.context -like "*;ActivityContextData=*") {
                            $logline = $logline + ([string]::Join(";", ($item.context.Split(";") -notlike "*ActivityContextData=*")))
                        } else {
                            $logline = $logline + " | context: " + $item.context
                        }
                    } else {
                        $logline = $logline + " | context: " + $item.context
                    }
                }
                $null = $logLines.add($logLine)
            }
            if ($logLines) {
                $logText = [string]::Join("`n", ($logLines | ForEach-Object { $_ }) )
            } else {
                $logtext = ""
            }

            # LocalEndpoint
            [string]$localEndpoint = $record.Group[-1].sIP

            # RemoteEndpoint
            [string]$remoteEndpoint = $record.Group[-1].cIp


            # Errors
            #Log-type - IMAP4 Log
            $errMsgs = $context | Where-Object { $_ -like 'R="*' -or $_ -like 'ErrMsg=*' }
            if ($errMsgs) {
                $hasError = $true
                $errorMessage = foreach ($errMsg in $errMsgs) {
                    if($errMsg.StartsWith("ErrMsg=")) {
                        $errMsg -replace "ErrMsg="
                    } elseif($errMsg.StartsWith("R=")) {
                        $_msg = $errMsg.split(";") | Where-Object { $_ -like "R=*" }
                        if($_msg) {
                            (([string]($errMsg.split(";")[0] -replace "R=").Trim('"')) -replace "z NO ") -replace "-ERR "
                        } else {
                            $errMsg
                        }
                    } else {
                        $errMsg
                    }
                }
                if ($errorMessage.count -gt 1) {
                    $errorMessage = [string]::Join(" | ", $errorMessage)
                }
            } else {
                $hasError = $false
                $errorMessage = ""
            }

            # IsProxysession
            $proxycontext = $context -like "*Proxy:*"
            if ("proxy" -in $commands) {
                $isProxysession = $true
                $proxyServer = $record.Group | Where-Object { $_.command -like "proxy" } | Select-Object -ExpandProperty parameters
                $proxyStatus = ""
            } elseif ($proxycontext) {
                $isProxysession = $true
                $proxycontext = ((($proxycontext -split "Msg=") | Where-Object { $_ -like "*Proxy:*" }) -split '"' | Where-Object { $_ -like "*Proxy:*" }) -replace "Proxy:"
                $proxyServer = ($proxycontext -split ";")[0]
                $proxyStatus = ($proxycontext -split ";")[1]
            } else {
                $isProxysession = $false
                $proxyServer = ""
                $proxyStatus = ""
            }

            # Authentication
            if ("auth" -in $commands -or "user" -in $commands -or "authenticate" -in $commands -or "login" -in $commands) { $authenticationEnabled = $true } else { $authenticationEnabled = $false }
            if ($authenticationEnabled) {
                $userName = $record.Group | Where-Object { $_.command -like "auth" -or $_.command -like "user" -or $_.command -like "authenticate" -or $_.command -like "login" } | Select-Object -ExpandProperty User -Unique
                if ($userName.count -gt 1) {
                    $userName = [string]::Join(", ", $userName)
                }
            } else {
                $userName = ""
            }

            if ($authenticationEnabled -and ("auth" -in $commands -or "pass" -in $commands -or "authenticate" -in $commands -or "login" -in $commands)) {
                $authDetails = ((($record.Group | Where-Object { $_.command -like "auth" -or $_.command -like "pass" -or $_.command -like "authenticate" -or $_.command -like "login"}).context -split ";")[1] -replace 'Msg="').TrimEnd('"') -Split ", "
                $authHash = @{
                    "RecipientType"                = ($authDetails | Where-Object { $_ -like "RecipientType: *" }) -replace "RecipientType: "
                    "RecipientTypeDetails"         = ($authDetails | Where-Object { $_ -like "RecipientTypeDetails: *" }) -replace "RecipientTypeDetails: "
                    "DisplayName"                  = ($authDetails | Where-Object { $_ -like "Selected Mailbox: Display Name: *" }) -replace "Selected Mailbox: Display Name: "
                    "MailboxGuid"                  = ($authDetails | Where-Object { $_ -like "Mailbox Guid: *" }) -replace "Mailbox Guid: "
                    "DatabaseGuid"                 = ($authDetails | Where-Object { $_ -like "Database: *" }) -replace "Database: "
                    "ServerFqdn"                   = ($authDetails | Where-Object { $_ -like "Location: ServerFqdn: *" }) -replace "Location: ServerFqdn: "
                    "ServerVersion"                = ($authDetails | Where-Object { $_ -like "ServerVersion: *" }) -replace "ServerVersion: "
                    "DatabaseName"                 = ($authDetails | Where-Object { $_ -like "DatabaseName: *" }) -replace "DatabaseName: "
                    "HomePublicFolderDatabaseGuid" = ($authDetails | Where-Object { $_ -like "HomePublicFolderDatabaseGuid: *" }) -replace "HomePublicFolderDatabaseGuid: "
                }
            } else {
                $authDetails = ""
                $authHash = @{}
            }

            # Statistics
            $stats = (($record.Group | Where-Object { $_.command -like "stat" }).Context -split ";") | Where-Object { $_ -like "Rows=*" -or $_ -like "TotalSize=*" }
            if ($stats) {
                $rows = ($stats -like "Rows=*") -replace "Rows="
                if ($rows) { $rows = [int]::Parse($rows) } else { [int]$rows = 0 }
                $totalSize = ($stats -like "TotalSize=*") -replace "TotalSize="
                if ($totalSize) { $totalSize = $totalSize = [int]::Parse($totalSize) } else { [int]$totalSize = 0 }
            } else {
                $rows = 0
                $totalSize = 0
            }

            $budgetinfo = ((([array]$context -like "*Budget=*") | Select-Object -Last 1) -split 'Budget="')[-1]
            if ($budgetinfo) {
                $budgetDetails = $budgetinfo.TrimEnd('"') -Split ","
                $budgetHash = @{
                    "OwnerSID"         = (($budgetDetails | Where-Object { $_ -like "Owner:Sid~*" }) -split "~")[1]
                    "Conn"             = [int](($budgetDetails | Where-Object { $_ -like "Conn:*" }) -replace "Conn:")
                    "MaxConn"          = ($budgetDetails | Where-Object { $_ -like "MaxConn:*" }) -replace "MaxConn:"
                    "MaxBurst"         = ($budgetDetails | Where-Object { $_ -like "MaxBurst:*" }) -replace "MaxBurst:"
                    "Balance"          = ($budgetDetails | Where-Object { $_ -like "Balance:*" }) -replace "Balance:"
                    "Cutoff"           = ($budgetDetails | Where-Object { $_ -like "Cutoff:*" }) -replace "Cutoff:"
                    "RechargeRate"     = ($budgetDetails | Where-Object { $_ -like "RechargeRate:*" }) -replace "RechargeRate:"
                    "Policy"           = ($budgetDetails | Where-Object { $_ -like "Policy:*" }) -replace "Policy:"
                    "IsServiceAccount" = [bool]::Parse( (($budgetDetails | Where-Object { $_ -like "IsServiceAccount:*" }) -replace "IsServiceAccount:") )
                    "LiveTime"         = [timespan]::Parse( (($budgetDetails | Where-Object { $_ -like "LiveTime:*" }) -replace "LiveTime:") )
                }
            } else {
                $budgetDetails = ""
                $budgetHash = @{}
            }

            $stls = ($record.group.command | Where-Object { $_ -like "stls" -or $_ -like "starttls"}).count
            $auth = ($record.group.command | Where-Object { $_ -like "auth" -or $_ -like "authenticate"}).count
            $user = ($record.group.command | Where-Object { $_ -like "user" -or $_ -like "login"}).count
            $pass = ($record.group.command | Where-Object { $_ -like "pass" }).count
            $stat = ($record.group.command | Where-Object { $_ -like "stat*"}).count
            $uidl = ($record.group.command | Where-Object { $_ -like "uidl" }).count
            $list = ($record.group.command | Where-Object { $_ -like "list" }).count
            $retr = ($record.group.command | Where-Object { $_ -like "retr" }).count
            $dele = ($record.group.command | Where-Object { $_ -like "dele" }).count

            # construct output object
            $outputRecord = [PSCustomObject]@{
                "PSTypeName"                   = "ExchangeLog.$($record.metadataHash['Log-type'].Replace(' ','')).Record"
                "LogFolder"                    = $record.LogFolder
                "LogFileName"                  = $record.LogFileName
                $SessionIdName                 = $record.$SessionIdName
                "DateStart"                    = ($record.Group | Sort-Object 'dateTime')[0].'dateTime' -as [datetime]
                "DateEnd"                      = ($record.Group | Sort-Object 'dateTime')[-1].'dateTime' -as [datetime]
                "SequenceCount"                = $record.Group.count
                "LocalIP"                      = $localEndpoint -replace ":$([string]$localEndpoint.split(":")[-1])", ""
                "LocalPort"                    = $localEndpoint.split(":")[-1]
                "RemoteIP"                     = $remoteEndpoint -replace ":$([string]$remoteEndpoint.split(":")[-1])", ""
                "RemotePort"                   = $remoteEndpoint.split(":")[-1]
                "AuthenticationEnabled"        = $authenticationEnabled
                "User"                         = $userName
                "RecipientType"                = (. { if ($authDetails) { $authHash["RecipientType"               ] } })
                "RecipientTypeDetails"         = (. { if ($authDetails) { $authHash["RecipientTypeDetails"        ] } })
                "DisplayName"                  = (. { if ($authDetails) { $authHash["DisplayName"                 ] } })
                "MailboxGuid"                  = (. { if ($authDetails) { $authHash["MailboxGuid"                 ] } })
                "DatabaseGuid"                 = (. { if ($authDetails) { $authHash["DatabaseGuid"                ] } })
                "ServerFqdn"                   = (. { if ($authDetails) { $authHash["ServerFqdn"                  ] } })
                "ServerVersion"                = (. { if ($authDetails) { $authHash["ServerVersion"               ] } })
                "DatabaseName"                 = (. { if ($authDetails) { $authHash["DatabaseName"                ] } })
                "HomePublicFolderDatabaseGuid" = (. { if ($authDetails) { $authHash["HomePublicFolderDatabaseGuid"] } })
                "OwnerSID"                     = (. { if ($budgetDetails) { $budgetHash["OwnerSID"] } })
                "ConnectionCount"              = (. { if ($budgetDetails) { $budgetHash["Conn"] } })
                "ConnectionMax"                = (. { if ($budgetDetails) { $budgetHash["MaxConn"] } })
                "MaxBurst"                     = (. { if ($budgetDetails) { $budgetHash["MaxBurst"] } })
                "Balance"                      = (. { if ($budgetDetails) { $budgetHash["Balance"] } })
                "Cutoff"                       = (. { if ($budgetDetails) { $budgetHash["Cutoff"] } })
                "RechargeRate"                 = (. { if ($budgetDetails) { $budgetHash["RechargeRate"] } })
                "Policy"                       = (. { if ($budgetDetails) { $budgetHash["Policy"] } })
                "IsServiceAccount"             = (. { if ($budgetDetails) { $budgetHash["IsServiceAccount"] } })
                "LiveTime"                     = (. { if ($budgetDetails) { $budgetHash["LiveTime"] } })
                "TotalObjects"                 = $rows
                "TotalSize"                    = $totalSize
                "HasError"                     = $hasError
                "ErrorMessage"                 = $errorMessage
                "IsProxysession"               = $isProxysession
                "ProxyServer"                  = $proxyServer
                "ProxyStatus"                  = $proxyStatus
                "CmdCountStls"                 = $stls
                "CmdCountAuth"                 = $auth
                "CmdCountUser"                 = $user
                "CmdCountPass"                 = $pass
                "CmdCountStat"                 = $stat
                "CmdCountUidl"                 = $uidl
                "CmdCountList"                 = $list
                "CmdCountRetr"                 = $retr
                "CmdCountDele"                 = $dele
                "LogText"                      = $logText
            }

            # add metadata attributes
            foreach ($key in $record.metadataHash.Keys) {
                if ($key -like "Date") {
                    $value = $record.metadataHash[$key] -as [datetime]
                } else {
                    $value = $record.metadataHash[$key]
                }
                $outputRecord | Add-Member -MemberType NoteProperty -Name $key -Value $value -Force
            }

            # output data
            $outputRecord

            # report  in detail if errors occur (for debugging because the processing in operating in runspaces)
            if ($Error) {
                Write-Warning "Error detected while processing $($outputRecord.LogFolder)\$($outputRecord.LogFileName) with $($record.$SessionIdName)"
                $Error.Clear()
            }

            # output progress of switch is set (only debugging purpose)
            if ($ShowProgress) {
                if (($i % $refreshInterval) -eq 0) {
                    Write-Progress -Activity "Process logfile record " -Status "$($record.LogFileName) - $($SessionIdName): $($record.$SessionIdName) ($($i) / $($InputObject.count))" -PercentComplete ($i / $InputObject.count * 100)
                }
                $i = $i + 1
            }
        }
    }

    end {
    }
}

(Get-Command Expand-LogRecordPopImap).Visibility = "Private"
