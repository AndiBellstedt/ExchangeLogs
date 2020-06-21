function Import-LogData_noTyped_bad {
    <#
    .SYNOPSIS
        Get csv content from logfile output grouped records

    .DESCRIPTION
        Get csv content from logfile output grouped records

    .PARAMETER File
        The file to gather data

    .EXAMPLE
        PS C:\> Import-LogData -File RECV2020061300-1.LOG

        Return the csv records as grouped records by SessionID
#>
    [CmdletBinding()]
    param (
        $File
    )

    # Get content from logfile
    $File = Get-Item -Path $File -ErrorAction Stop
    Write-Verbose "Get content from logfile: $($File.Fullname)"
    $content = $File | Get-Content

    # split metadata and logcontent (first lines fo logfile)
    $metadata = $content -match '^#.*'
    $header = $metadata[-1].split(": ")[-1]
    $logcontent = $content -notmatch $header

    # query meta data informations into hashtable
    $metadataHash = [ordered]@{}
    foreach ($metadatarecord in ($metadata[0 .. ($metadata.Count - 2)])) {
        $_data = $metadatarecord.TrimStart("#") -Split ': '
        $metadataHash.Add($_data[0], $_data[1])
    }

    # convert filecontent to csv data and group records if know/supportet logfile type
    $records = $logcontent | ConvertFrom-Csv -Delimiter "," -Header $header.Split(",")
    $sessionIdName = Resolve-SessionIdName -LogType $metadataHash['Log-type']
    $output = New-Object -TypeName "System.Collections.ArrayList"
    if ($sessionIdName) {
        #$group = ($records | Group-Object $sessionIdName | sort count -Descending)[0]
        foreach ($group in ($records | Group-Object $sessionIdName)) {
            #$Error.Clear()
            $groupData = $group.Group.data

            [int]$_start = [int](($group.Group | Where-Object data -like "220 2.0.0 SMTP server ready").'sequence-number') | Select-Object -First 1
            [int]$_stop = ($group.Group | Where-Object data -like "250  * Hello *").'sequence-number' | ForEach-Object { [int]$_ } | Where-Object { $_ -ge $start } | Select-Object -First 1
            $TlsRecords = $group.Group | Where-Object event -eq '*' | Where-Object { $_.'sequence-number' -gt $_start -or $_.'sequence-number' -lt $_stop } | Where-Object { $_.data -like "" -or $_.data -like " CN=" -or $_.context -like "* certificate *" } | Where-Object { $_.context -like "tls*" -or $_.context -like "* certificate *" -or $_.context -like "Validated*" } | Select-Object 'sequence-number', data, context
            Remove-Variable -Name "_start", "_stop"

            $serverName = $group.Group.'connector-id'[0].split("\")[0]
            [string]$clientNameHELO = ($group.Group | Where-Object data -like "EHLO *").data
            $clientNameHELO = $clientNameHELO.trim("EHLO ") | Select-Object -Unique

            [string]$mailFrom = ($group.Group.data | ForEach-Object { if ($_ -match "^MAIL FROM:<(?'mailadress'\S+)>") { $Matches['mailadress'] } })
            [string]$rcptTo = ($group.Group.data | ForEach-Object { if ($_ -match "^RCPT TO:<(?'mailadress'\S+)>") { $Matches['mailadress'] } })
            [string]$XOOrg = $group.Group.data | ForEach-Object { if ($_ -match "XOORG=(?'xoorg'\S+)") { $Matches['xoorg'] } }
            [string]$SmtpId = $group.Group.data | ForEach-Object { if ($_ -match "^250\s2.6.0\s(?'SmtpId'\S+)") { $Matches['SmtpId'] } }
            [string]$RemoteServerHostName = $group.Group.data | ForEach-Object { if ($_ -match "^250\s2.6.0\s(?'SmtpId'\S+)") { $Matches['SmtpId'].split("@")[1] } }
            [string]$InternalId = $group.Group.data | ForEach-Object { if ($_ -match "^250\s2\.6\.0\s.*InternalId=(?'InternalId'\w+)") { $Matches['InternalId'] } }
            [string]$MailSize = $group.Group.data | ForEach-Object { if ($_ -match "\w+(?=\sbytes\sin\s)") { $Matches[0] } }

            $TarpitDetect = (. {if ($group.Group | Where-Object data -like "Tarpit*") { $true } else { $false } })

            $outputRecord = [PSCustomObject]@{
                "PSTypeName"                     = "ExchangeLog.$($metadataHash['Log-type'].Replace(' ','')).FullRecord"
                $sessionIdName                   = $group.Name
                "DateStart"                      = ($group.Group | Sort-Object 'date-time')[0].'date-time' -as [datetime]
                "DateEnd"                        = ($group.Group | Sort-Object 'date-time')[-1].'date-time' -as [datetime]
                "SequenceCount"                  = $group.Group.count
                "ConnectorID"                    = $group.Group.'connector-id'[0]
                "ServerName"                     = $ServerName
                "ConnectorName"                  = $group.Group.'connector-id'[0].split("\")[1]
                "ConnectorNameWithoutServerName" = $group.Group.'connector-id'[0].split("\")[1].replace($ServerName, "").trim()
                "LocalIP"                        = $group.Group.'local-endpoint'[0].split(":")[0]
                "LocalPort"                      = $group.Group.'local-endpoint'[0].split(":")[1]
                "RemoteIP"                       = $group.Group.'remote-endpoint'[0].split(":")[0]
                "RemotePort"                     = $group.Group.'remote-endpoint'[0].split(":")[1]
                "ServerNameHELO"                 = (.{ $null = $group.Group | Where-Object data -Match "^220\s(?'ServerName'\S+)\sMicrosoft"; $Matches['ServerName'] })
                "ServerOptions"                  = (.{ $null = $group.Group.data -match "^250\s\s(?'ServerName'\S+)\sHello\s\[\S+]\s(?'ServerOptions'(\S|\s)+)"; [string]::Join(",", [string]$Matches['ServerOptions']) })
                "ClientNameHELO"                 = [string]::Join(",", $clientNameHELO)
                "TlsEnabled"                     = (.{ if ($group.Group | Where-Object data -CLike "STARTTLS") { $true } else { $false } })
                "AuthenticationEnabled"          = (.{ if ($group.Group.data -clike "AUTH *") { $true } else { $false } })
                "AuthenticationType"             = (.{
                        if ($group.AuthenticationEnabled) {
                            $null = $group.Group | Where-Object data -Match "^AUTH\s(?'Method'\S+)"
                            $Matches['Method']
                        }
                    })
                "AuthenticationUser"             = (. {
                        if ($group.AuthenticationEnabled) {
                            ($group.Group | Where-Object context -like "authenticated").data
                        }
                    })
                "AuthenticationMessage"          = (. {
                        if ($group.AuthenticationEnabled) {
                            $text = @( "235 2.7.0 Authentication successful", "504 5.7.4 Unrecognized authentication type", "535 5.7.3 Authentication unsuccessful" )
                            [array]$authMsg = $group.Group | Where-Object data -in $text | select-Object -Last 1
                            if ($authMsg) {
                                $authMsg.data
                            }
                        }
                    })
                "TarpitDetect"                   = $TarpitDetect
                "TarpitDuration"                 = (. {
                        if ($TarpitDetect) {
                            [timespan]::FromSeconds( (($group.Group | where-Object data -like "Tarpit*").data.replace("Tarpit for '", "") | ForEach-Object { $_.split("'")[0] -as [timespan] } | Measure-Object Seconds -Sum).Sum )
                        }
                    })
                "TarpitMessage"                  = (. {
                        if ($TarpitDetect) {
                            (($group.Group | Where-Object data -like "Tarpit*").data -split "(due\sto\s')")[-1].trim("'")
                        }
                    })
                "MailFrom"                       = [string]::Join(",", $mailFrom.trim() )
                "RcptTo"                         = [string]::Join(",", $rcptTo.trim() )
                "XOOrg"                          = [string]::Join(",", $XOOrg.trim() )
                "SmtpId"                         = [string]::Join(",", $SmtpId.trim(">").trim("<") )
                "RemoteServerHostName"           = [string]::Join(",", $RemoteServerHostName.trim(">") )
                "InternalId"                     = [string]::Join(",", $InternalId )
                "MailSize"                       = [string]::Join(",", $MailSize )
                "DeliveryDuration"               = (. {
                        $duration = [timespan]::new(0)
                        $group.Group.data | ForEach-Object { if ($_ -match "(?<=\sbytes\sin\s)(\d|\.)+") { $duration = $duration + [timespan]::FromSeconds( [System.Convert]::ToDouble($Matches[0], [cultureinfo]::GetCultureInfo('en-us') )) } }
                        $duration
                    })
                "DeliveryBandwidth"              = (. {
                        $bandwidth = 0
                        $group.Group.data | ForEach-Object { if ($_ -match "(?'duration'(\d*|,)+)(?=\sKB\/sec\sQueued\smail\sfor\sdelivery)") { $bandwidth = $bandwidth + [double]::Parse($Matches['duration']) } }
                        $bandwidth
                    })
                "FinalizeMessage"                = ($group.Group | Where-Object event -NotLike "-")[-1].data
                "TlsCrypto"                      = ($TlsRecords | Where-Object context -like "TLS *").context
                "TlsProtocol"                    = (.{if($TlsRecords) { [string]::Join(",", ($TlsRecords | ForEach-Object { if ($_ -match "(?<=\sprotocol\s)\S+") { $Matches[0] } }) ) }})
                "TlsAlgorithmEncryption"         = (.{if($TlsRecords) { [string]::Join(",", ($TlsRecords | ForEach-Object { if ($_ -match "(?<=\sencryption\salgorithm\s)\S+") { $Matches[0] } }) ) }})
                "TlsAlgorithmMacHash"            = (.{if($TlsRecords) { [string]::Join(",", ($TlsRecords | ForEach-Object { if ($_ -match "(?<=\shash\salgorithm\s)\S+") { $Matches[0] } }) ) }})
                "TlsAlgorithmKeyExchange"        = (.{if($TlsRecords) { [string]::Join(",", ($TlsRecords | ForEach-Object { if ($_ -match "(?<=\sexchange\salgorithm\s)\S+") { $Matches[0] } }) ) }})
                "TlsCertificateServer"           = ($TlsRecords | where-Object context -Like "Sending certificat*").data | ForEach-Object { ([string]$_).trim() }
                "TlsCertificateClient"           = ($TlsRecords | where-Object context -Like "Remote certificat*").data | ForEach-Object { ([string]$_).trim() }
                "TlsDomainCapabilities"          = [string]::Join(",", ( ([string](((($TlsRecords | Where-Object context -Like "*; Status='*").context -Split "; ") | Where-Object { $_ -like "TlsDomainCapabilities=*" }) -split "=")).trim("'") ))
                "TlsStatus"                      = [string]::Join(",", ( ([string](((($TlsRecords | Where-Object context -Like "*; Status='*").context -Split "; ") | Where-Object { $_ -like "Status=*" }) -split "=")).trim("'") ))
                "TlsDomain"                      = [string]::Join(",", ( ([string](((($TlsRecords | Where-Object context -Like "*; Status='*").context -Split "; ") | Where-Object { $_ -like "Domain=*" }) -split "=")).trim("'") ))
                "LogText"                        = (. {
                        $logtext = ""
                        foreach ($item in $group.Group) {
                            if ($item.data.Length -gt 0) {
                                $logtext = $logtext + "$(if($logtext){"`n"})" + $item.event + " " + $item.data
                                if ($item.context.Length -gt 0) {
                                    $logtext = $logtext + "$(if($logtext){"`n"})" + $item.event + " " + $item.context
                                }
                            } else {
                                $logtext = $logtext + "$(if($logtext){"`n"})" + $item.event + " " + $item.context
                            }
                        }
                        $logtext
                    })
            }

            #if($Error.count -gt 0) { throw 1 }
            $null = $output.Add( $outputRecord )
        }
    } else {
        foreach ($record in $records) {
            $record.PSOBject.TypeNames.Insert(0, "ExchangeLog.$($metadataHash['Log-type'].Replace(' ','')).Record" )
            $null = $output.Add( $record )
        }
    }

    # add metadata info to record groups
    foreach ($key in $metadataHash.Keys) {
        $output | Add-Member -MemberType NoteProperty -Name $key -Value $metadataHash[$key] -Force
    }
    $output | Add-Member -MemberType NoteProperty -Name "LogFileName" -Value $File.Name -Force
    $output | Add-Member -MemberType NoteProperty -Name "LogFolder" -Value $File.Directory -Force
    Write-Verbose "Finished logfile $($File.Name). Found $($output.count) recors"

    # output data to the pipeline
    $output
}