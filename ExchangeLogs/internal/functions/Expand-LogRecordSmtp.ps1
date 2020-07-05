function global:Expand-LogRecordSmtp {
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

    .EXAMPLE
        PS C:\> Expand-LogRecordSmtp -InputObject $DataSet

        Expand the data from records group into a flat data record
#>
    [CmdletBinding()]
    param (
        $InputObject,

        [string]
        $SessionIdName = "session-Id",

        [switch]
        $ShowProgress
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
            $_startIndicator = $record.Group | Where-Object Event -eq "+"
            $_stopIndicator = $record.Group | Where-Object Event -eq "-"
            if((-not $_startIndicator) -or (-not $_stopIndicator)) {
                Write-PSFMessage -Level Warning -Message "Detect fragmented record! Missing previous logfile with partital records. Skip processing $($SessionIdName) '$($record.$SessionIdName)' in $($record.LogFolder)\$($record.LogFileName)"
                continue
            }

            # data text record in array, avoids parsing full data array
            $groupData = $record.Group.data

            # full text log
            $logtext = ""
            foreach ($item in $record.Group) {
                $logtext = $logtext + "$(if($logtext){"`n"})" + $item.event + " " + $item.data
                if ($item.context.Length -gt 0) {
                    $logtext = $logtext + " (context: " + $item.context + ")"
                }
            }

            # ServerName
            $serverName = $record.Group[0].'connector-id'.split("\")[0]

            # ServerNameHELO
            [string]$_serverNameHELO = $groupData | Where-Object { $_ -like "220 * Microsoft*" } | Select-Object -First 1
            [String]$serverNameHELO = $_serverNameHELO.TrimStart("220 ").Split(" ")[0]

            # ServerOptions
            $_serverOptions = foreach ($item in $groupData) { if ($item -match "^250\s\s\S+\sHello\s\[\S+]\s(?'ServerOptions'(\S|\s)+)") { $Matches['ServerOptions'] } }
            if ($_serverOptions) { [string]$serverOptions = [string]::Join(",", $_serverOptions) } else { [string]$serverOptions = "" }

            # ClientNameHELO
            $_clientNameHELO = foreach($item in ($groupData -like "EHLO *" | Select-Object -Unique)) { ([string]$item).trim("EHLO ") }
            if ($_clientNameHELO) { [string]$clientNameHELO = [string]::Join(",", $_clientNameHELO) } else { [string]$clientNameHELO = "" }

            # MailFrom
            [string[]]$_mailFrom = foreach ($item in $groupData) { if ($item -match "^MAIL FROM:<(?'mailadress'\S+)>") { $Matches['mailadress'] } }
            if ($_mailFrom) { [string]$mailFrom = [string]::Join(",", $_mailFrom.trim() ) } else { [string]$mailFrom = "" }

            # RcptTo
            [string[]]$_rcptTo = foreach ($item in $groupData) { if ($item -match "^RCPT TO:<(?'mailadress'\S+)>") { $Matches['mailadress'] } }
            if ($_rcptTo) { [string]$rcptTo = [string]::Join(",", $_rcptTo.trim() ) } else { [string]$rcptTo = "" }

            # XOOrg
            [string[]]$_xoorg = foreach ($item in $groupData) { if ($item -match "XOORG=(?'xoorg'\S+)") { $Matches['xoorg'] } }
            if ($_xoorg) { [string]$xoorg = [string]::Join(",", $_xoorg.trim() ) } else { [string]$xoorg = "" }

            $smtpIdLine = $groupData -match "^250\s2.6.0\s<(?'SmtpId'\S+)"
            [timespan]$deliveryDuration = [timespan]::new(0)
            [double]$deliveryBandwidth = 0
            [string]$remoteServerHostName = ""
            [string]$internalId = ""
            [int]$mailSize = 0
            if ($smtpIdLine) {
                [string[]]$_smtpIdRecords = foreach ($line in $smtpIdLine) { $line.trim("250 2.6.0 <").split(">")[0] }
                if ($_smtpIdRecords) { $SmtpId = [string]::Join(",", $_smtpIdRecords.trim() ) } else { [string]$smtpId = "" }

                [string[]]$_remoteServerHostName = foreach ($item in $_smtpIdRecords) { $item.split("@")[1] }
                if ($_remoteServerHostName) { [string]$remoteServerHostName = [string]::Join(",", $_remoteServerHostName ) } else { [string]$remoteServerHostName = "" }

                [string[]]$_internalId = $smtpIdLine | ForEach-Object { ($_ -split "InternalId=")[1].split(",")[0] }
                if ($_internalId) { [string]$internalId = [string]::Join(",", $_internalId.trim() ) } else { [string]$internalId = "" }

                if($smtpIdLine -like "bytes in") {
                    [string[]]$_mailSize = $smtpIdLine | ForEach-Object { ($_ -split " bytes in ")[0].split(" ")[-1] }
                    if ($_mailSize) {
                        #$mailSize = [string]::Join(",", $_mailSize.trim() )
                        $mailSize = ($_mailSize | Measure-Object -Sum).Sum
                    } else { [int]$mailSize = 0 }

                    ForEach ($item in $smtpIdLine) {
                        $deliveryDuration = $deliveryDuration + [timespan]::FromSeconds( [System.Convert]::ToDouble( (($item -split " bytes in ")[1].split(", ")[0]) , [cultureinfo]::GetCultureInfo('en-us') ))
                    }
                    ForEach ($item in $smtpIdLine) {
                        $deliveryBandwidth = $deliveryBandwidth + [double]::Parse( (($item.TrimEnd(" KB/sec Queued mail for delivery") -split ", ")[-1]) )
                        $deliveryBandwidth = [math]::Round( ($deliveryBandwidth / $smtpIdLine.count), 3 )
                    }
                }
            }

            if ($record.Group | Where-Object data -like "Tarpit*") { $tarpitDetect = $true } else { $tarpitDetect = $false }
            $tarpitDuration = [timespan]::new(0)
            $tarpitMessage = ""
            if ($tarpitDetect) {
                $tarpitDuration = [timespan]::FromSeconds( (($record.Group | where-Object data -like "Tarpit*").data.replace("Tarpit for '", "") | ForEach-Object { $_.split("'")[0] -as [timespan] } | Measure-Object Seconds -Sum).Sum )
                $tarpitMessage = (($record.Group | Where-Object data -like "Tarpit*").data -split "(due\sto\s')")[-1].trim("'")
            }

            [string]$connectorID = $record.Group[0].'connector-id'
            if ($connectorID) {
                if ($connectorID -match "\\") { $connectorName = $connectorID.split("\")[1] } else { $connectorName = $connectorID }
            } else {
                $connectorName = ""
            }
            if ($connectorID) { $connectorNameWithoutServerName = $connectorName.replace($serverName, "").trim() } else { $connectorNameWithoutServerName = "" }

            [string]$localEndpoint = $record.Group[-1].'local-endpoint'

            [string]$remoteEndpoint = $record.Group[-1].'remote-endpoint'

            if ($groupData -clike "AUTH *") { $authenticationEnabled = $true } else { $authenticationEnabled = $false }
            $authenticationType = ""
            $authenticationUser = ""
            $authenticationMessage = ""
            if ($authenticationEnabled) {
                $null = $record.Group | Where-Object data -Match "^AUTH\s(?'Method'\S+)"
                $authenticationType = $Matches['Method']
                $authenticationUser = ($record.Group | Where-Object context -like "authenticated").data

                $text = @( "235 2.7.0 Authentication successful", "504 5.7.4 Unrecognized authentication type", "535 5.7.3 Authentication unsuccessful" )
                [string]$authenticationMessage = ($record.Group | Where-Object data -in $text)[-1].data
            }

            # TLS records
            if ($groupData -clike " CN=*") { $tlsEnabled = $true } else { $tlsEnabled = $false }
            $tlsAlgorithmEncryption = ""
            $tlsAlgorithmKeyExchange = ""
            $tlsAlgorithmMacHash = ""
            $tlsCertificateRemote = ""
            $tlsCertificateRemoteIssuer = ""
            $tlsCertificateRemoteNotAfter = ""
            $tlsCertificateRemoteNotBefore = ""
            $tlsCertificateRemoteSAN = ""
            $tlsCertificateRemoteSerial = ""
            $tlsCertificateRemoteThumbprint = ""
            $TlsCertificateServer = ""
            $tlsCertificateServerIssuer = ""
            $tlsCertificateServerNotAfter = ""
            $tlsCertificateServerNotBefore = ""
            $tlsCertificateServerSAN = ""
            $tlsCertificateServerSerial = ""
            $tlsCertificateServerThumbprint = ""
            $tlsCrypto = ""
            $tlsDomain = ""
            $tlsDomainCapabilities = ""
            $tlsProtocol = ""
            $tlsStatus = ""
            $tlsStatusRecord = ""

            if ($tlsEnabled) {
                # gather TLS related records
                $tlsRecords = $record.Group | Where-Object { ($_.event -eq '*') -and ($_.context -like "Sending certificate*" -or $_.context -like "Remote certificate*" -or $_.context -like "TLS protocol*" -or $_.context -like "*TlsDomainCapabilities=*") } | Select-Object 'sequence-number', context, data
                if ($tlsRecords) {
                    # TLS Crypto string
                    $_tlsCrypto = $TlsRecords | Where-Object context -like "TLS *" | Select-Object -ExpandProperty context -Unique
                    if ($_tlsCrypto) { $tlsCrypto = [string]::Join(",", $_tlsCrypto) } else { $tlsCrypto = "" }
                    if ($tlsCrypto) {
                        # TLS protocol
                        $_tlsProtocol = foreach ($item in $tlsCrypto) {
                            ([string]$item).Replace('TLS protocol ', '').Split(" ")[0]
                        }
                        if ($_tlsProtocol) { $tlsProtocol = [string]::Join(",", $_tlsProtocol) } else { $tlsProtocol = "" }

                        # TLS Algorithm Encryption
                        $_tlsAlgorithmEncryption = foreach ($item in $tlsCrypto) {
                            ([string](([string]$item) -Split "encryption algorithm ")[1]).Split(" ")[0]
                        }
                        if ($_tlsAlgorithmEncryption) { $tlsAlgorithmEncryption = [string]::Join(",", $_tlsAlgorithmEncryption) } else { $tlsAlgorithmEncryption = "" }

                        # TLS Algorithm MacHash
                        $_tlsAlgorithmMacHash = foreach ($item in $tlsCrypto) {
                            ([string](([string]$item) -Split "hash algorithm ")[1]).Split(" ")[0]
                        }
                        if ($_tlsAlgorithmMacHash) { $tlsAlgorithmMacHash = [string]::Join(",", $_tlsAlgorithmMacHash) } else { $tlsAlgorithmMacHash = "" }

                        # TLS Algorithm KeyExchange
                        $_tlsAlgorithmKeyExchange = foreach ($item in $tlsCrypto) {
                            ([string](([string]$item) -Split "exchange algorithm ")[1]).Split(" ")[0]
                        }
                        if ($_tlsAlgorithmKeyExchange) { $tlsAlgorithmKeyExchange = [string]::Join(",", $_tlsAlgorithmKeyExchange) } else { $tlsAlgorithmKeyExchange = "" }
                    }

                    # TLS Server certificate
                    $_tlsCertificateServerRecord = $tlsRecords | where-Object context -Like "Sending certificat*" | Select-Object -First 1 -ExpandProperty data
                    if ($_tlsCertificateServerRecord) {
                        $_tlsCertificateServerRecord = $_tlsCertificateServerRecord.trim()
                        [string]$certText = $_tlsCertificateServerRecord

                        # TLS Server certificate - Subject alternate names
                        [String]$tlsCertificateServerSAN = $certText.split(" ")[-1]
                        $certText = $certText.TrimEnd($tlsCertificateServerSAN).TrimEnd()

                        # TLS Server certificate - Not after
                        [String]$_tlsCertificateServerNotAfter = $certText.split(" ")[-1]
                        $tlsCertificateServerNotAfter = [datetime]::Parse($_tlsCertificateServerNotAfter)
                        $certText = $certText.TrimEnd($_tlsCertificateServerNotAfter).TrimEnd()

                        # TLS Server certificate - Not before
                        [String]$_tlsCertificateServerNotBefore = $certText.split(" ")[-1]
                        $tlsCertificateServerNotBefore = [datetime]::Parse($_tlsCertificateServerNotBefore)
                        $certText = $certText.TrimEnd($_tlsCertificateServerNotBefore).TrimEnd()

                        # TLS Server certificate - Thumbprint
                        [String]$tlsCertificateServerThumbprint = $certText.split(" ")[-1]
                        $certText = $certText.TrimEnd($tlsCertificateServerThumbprint).TrimEnd()

                        # TLS Server certificate - Serial number
                        [String]$tlsCertificateServerSerial = $certText.split(" ")[-1]
                        $certText = $certText.TrimEnd($tlsCertificateServerSerial).TrimEnd()

                        # TLS Server certificate - Issuer name
                        [String]$tlsCertificateServerIssuer = "CN=" + ($certText -split (" CN="))[1]
                        $certText = $certText.TrimEnd($tlsCertificateServerIssuer).TrimEnd()

                        # TLS Server certificate - Subject
                        [String]$tlsCertificateServerIssuer = $certText
                    }
                    [String]$tlsCertificateServer = $_tlsCertificateServerRecord

                    # TLS Remote certificate
                    $_tlsCertificateRemoteRecord = $tlsRecords | where-Object context -Like "Remote certificat*" | Select-Object -First 1 -ExpandProperty data
                    if ($_tlsCertificateRemoteRecord) {
                        $_tlsCertificateRemoteRecord = $_tlsCertificateRemoteRecord.trim()
                        [string]$certText = $_tlsCertificateRemoteRecord

                        # TLS Remote certificate - Subject alternate names
                        [String]$tlsCertificateRemoteSAN = $certText.split(" ")[-1]
                        $certText = $certText.TrimEnd($tlsCertificateRemoteSAN).TrimEnd()

                        # TLS Remote certificate - Not after
                        [String]$_tlsCertificateRemoteNotAfter = $certText.split(" ")[-1]
                        $tlsCertificateRemoteNotAfter = [datetime]::Parse($_tlsCertificateRemoteNotAfter)
                        $certText = $certText.TrimEnd($_tlsCertificateRemoteNotAfter).TrimEnd()

                        # TLS Remote certificate - Not before
                        [String]$_tlsCertificateRemoteNotBefore = $certText.split(" ")[-1]
                        $tlsCertificateRemoteNotBefore = [datetime]::Parse($_tlsCertificateRemoteNotBefore)
                        $certText = $certText.TrimEnd($_tlsCertificateRemoteNotBefore).TrimEnd()

                        # TLS Remote certificate - Thumbprint
                        [String]$tlsCertificateRemoteThumbprint = $certText.split(" ")[-1]
                        $certText = $certText.TrimEnd($tlsCertificateRemoteThumbprint).TrimEnd()

                        # TLS Remote certificate - Serial number
                        [String]$tlsCertificateRemoteSerial = $certText.split(" ")[-1]
                        $certText = $certText.TrimEnd($tlsCertificateRemoteSerial).TrimEnd()

                        # TLS Remote certificate - Issuer name
                        [String]$tlsCertificateRemoteIssuer = "CN=" + ($certText -split (" CN="))[1]
                        $certText = $certText.TrimEnd($tlsCertificateRemoteIssuer).TrimEnd()

                        # TLS Remote certificate - Subject
                        [String]$tlsCertificateRemoteIssuer = $certText
                    }
                    [String]$tlsCertificateRemote = $_tlsCertificateRemoteRecord

                    # TLS Status Record
                    $_tlsStatusRecord = ($tlsRecords | Where-Object context -Like "*; Status='*").context -Split "; "
                    if ($_tlsStatusRecord) {
                        # TLS Status Record
                        [String]$tlsStatusRecord = [string]::Join("; ", $_tlsStatusRecord)

                        # TLS Domain Capabilities
                        $_tlsDomainCapabilities = ("" + (($_tlsStatusRecord | Where-Object { $_ -like "TlsDomainCapabilities=*" }) -split "=")[1] ).trim("'")
                        if ($_tlsDomainCapabilities) { $tlsDomainCapabilities = [string]::Join(",", $_tlsDomainCapabilities) } else { $tlsDomainCapabilities = "" }

                        # TLS Status
                        $_tlsStatus = ("" + (($_tlsStatusRecord | Where-Object { $_ -like "Status=*" }) -split "=")[1] ).trim("'")
                        if ($_tlsStatus) { $tlsStatus = [string]::Join(",", $_tlsStatus) } else { $tlsStatus = "" }

                        # TLS Domain
                        $_tlsDomain = ("" + (($_tlsStatusRecord | Where-Object { $_ -like "Domain=*" }) -split "=")[1] ).trim("'")
                        if ($_tlsDomain) { $tlsDomain = [string]::Join(",", $_tlsDomain) } else { $tlsDomain = "" }
                    } else {
                        [String]$_tlsStatusRecord = ""
                    }
                }
            }

            # construct output object
            $outputRecord = [PSCustomObject]@{
                "PSTypeName"                     = "ExchangeLog.$($record.metadataHash['Log-type'].Replace(' ','')).Record"
                "LogFolder"                      = $record.LogFolder
                "LogFileName"                    = $record.LogFileName
                $SessionIdName                   = $record.$SessionIdName
                "DateStart"                      = ($record.Group | Sort-Object 'date-time')[0].'date-time' -as [datetime]
                "DateEnd"                        = ($record.Group | Sort-Object 'date-time')[-1].'date-time' -as [datetime]
                "SequenceCount"                  = $record.Group.count
                "ConnectorID"                    = $ConnectorID
                "ServerName"                     = $ServerName
                "ConnectorName"                  = $ConnectorName
                "ConnectorNameWithoutServerName" = $ConnectorNameWithoutServerName
                "LocalIP"                        = $localEndpoint -replace ":$([string]$localEndpoint.split(":")[-1])", ""
                "LocalPort"                      = $localEndpoint.split(":")[-1]
                "RemoteIP"                       = $remoteEndpoint -replace ":$([string]$remoteEndpoint.split(":")[-1])", ""
                "RemotePort"                     = $remoteEndpoint.split(":")[-1]
                "ServerNameHELO"                 = $ServerNameHELO
                "ServerOptions"                  = $ServerOptions
                "ClientNameHELO"                 = $clientNameHELO
                "TlsEnabled"                     = $TlsEnabled
                "AuthenticationEnabled"          = $AuthenticationEnabled
                "AuthenticationType"             = $AuthenticationType
                "AuthenticationUser"             = $AuthenticationUser
                "AuthenticationMessage"          = $AuthenticationMessage
                "TarpitDetect"                   = $TarpitDetect
                "TarpitDuration"                 = $TarpitDuration
                "TarpitMessage"                  = $TarpitMessage
                "MailFrom"                       = $MailFrom
                "RcptTo"                         = $rcptTo
                "XOOrg"                          = $XOOrg
                "SmtpId"                         = $SmtpId
                "RemoteServerHostName"           = $RemoteServerHostName
                "InternalId"                     = $InternalId
                "MailSize"                       = $MailSize
                "DeliveryDuration"               = $DeliveryDuration
                "DeliveryBandwidth"              = $deliveryBandwidth
                "FinalizeMessage"                = $groupData[-2]
                "TlsProtocol"                    = $tlsProtocol
                "TlsAlgorithmEncryption"         = $tlsAlgorithmEncryption
                "TlsAlgorithmMacHash"            = $tlsAlgorithmMacHash
                "TlsAlgorithmKeyExchange"        = $tlsAlgorithmKeyExchange
                "TlsCertificateServer"           = $tlsCertificateServer
                "TlsCertificateServerIssuer"     = $tlsCertificateServerIssuer
                "TlsCertificateServerNotAfter"   = $tlsCertificateServerNotAfter
                "TlsCertificateServerNotBefore"  = $tlsCertificateServerNotBefore
                "TlsCertificateServerSAN"        = $tlsCertificateServerSAN
                "TlsCertificateServerSerial"     = $tlsCertificateServerSerial
                "TlsCertificateServerThumbprint" = $tlsCertificateServerThumbprint
                "TlsCertificateRemote"           = $tlsCertificateRemote
                "TlsCertificateRemoteIssuer"     = $tlsCertificateRemoteIssuer
                "TlsCertificateRemoteNotAfter"   = $tlsCertificateRemoteNotAfter
                "TlsCertificateRemoteNotBefore"  = $tlsCertificateRemoteNotBefore
                "TlsCertificateRemoteSAN"        = $tlsCertificateRemoteSAN
                "TlsCertificateRemoteSerial"     = $tlsCertificateRemoteSerial
                "TlsCertificateRemoteThumbprint" = $tlsCertificateRemoteThumbprint
                "TlsStatus"                      = $tlsStatus
                "TlsDomain"                      = $tlsDomain
                "TlsDomainCapabilities"          = $tlsDomainCapabilities
                "TlsCrypto"                      = $tlsCrypto
                "TlsStatusRecord"                = $tlsStatusRecord
                "LogText"                        = $logText
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

(Get-Command Expand-LogRecordSmtp).Visibility = "Private"