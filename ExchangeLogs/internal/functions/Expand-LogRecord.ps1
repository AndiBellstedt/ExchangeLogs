function global:Expand-LogRecord {
#function Expand-LogRecord {
    <#
    .SYNOPSIS
        Expand the data from records group into a flat data record

    .DESCRIPTION
        Expand the data from records group into a flat data record

    .PARAMETER InputObject
        The dataset to expand

    .EXAMPLE
        PS C:\> Expand-LogRecord -InputObject $DataSet

        Expand the data from records group into a flat data record
#>
    [CmdletBinding()]
    param (
        $InputObject,

        [string]
        $sessionIdName
    )

    begin {

    }

    process {
        #$output = New-Object -TypeName "System.Collections.ArrayList"
        foreach ($record in $InputObject) {
            #$sessionIdName = Resolve-SessionIdName -LogType $record.metadataHash['Log-type']

            $groupData = $record.Group.data

            $serverName = ($record.Group)[0].'connector-id'.split("\")[0]

            $null = $record.Group | Where-Object data -Match "^220\s(?'ServerName'\S+)\sMicrosoft"
            if ($Matches['ServerName']) { $ServerNameHELO = $Matches['ServerName'] } else { $ServerNameHELO = "" }

            $ServerOptions = foreach ($item in $groupData) { if ($item -match "^250\s\s\S+\sHello\s\[\S+]\s(?'ServerOptions'(\S|\s)+)") { $Matches['ServerOptions'] } }
            if (-not $ServerOptions) { $ServerOptions = "" } else { $ServerOptions = [string]::Join(",", $ServerOptions) }

            [string]$clientNameHELO = ($record.Group | Where-Object data -like "EHLO *").data
            $clientNameHELO = $clientNameHELO.trim("EHLO ") | Select-Object -Unique
            if (-not $clientNameHELO) { $clientNameHELO = "" } else { $clientNameHELO = [string]::Join(",", $clientNameHELO) }

            [string]$mailFrom = foreach ($item in $groupData) { if ($item -match "^MAIL FROM:<(?'mailadress'\S+)>") { $Matches['mailadress'] } }
            if (-not $mailFrom) { $mailFrom = "" } else { $mailFrom = [string]::Join(",", $mailFrom.trim() ) }

            [string]$rcptTo = foreach ($item in $groupData) { if ($item -match "^RCPT TO:<(?'mailadress'\S+)>") { $Matches['mailadress'] } }
            if (-not $rcptTo) { $rcptTo = "" } else { $rcptTo = [string]::Join(",", $rcptTo.trim() ) }

            [string]$XOOrg = foreach ($item in $groupData) { if ($item -match "XOORG=(?'xoorg'\S+)") { $Matches['xoorg'] } }
            if (-not $XOOrg) { $XOOrg = "" } else { $XOOrg = [string]::Join(",", $XOOrg.trim() ) }

            [string]$SmtpId = foreach ($item in $groupData) { if ($item -match "^250\s2.6.0\s(?'SmtpId'\S+)") { $Matches['SmtpId'] } }
            if (-not $SmtpId) { $SmtpId = "" } else { $SmtpId = [string]::Join(",", $SmtpId.trim().trim(">").trim("<") ) }

            [timespan]$DeliveryDuration = [timespan]::new(0)
            [double]$deliveryBandwidth = 0
            [string]$RemoteServerHostName = ""
            [string]$InternalId = ""
            [string]$MailSize = ""
            if ($SmtpId) {
                [string[]]$RemoteServerHostName = foreach ($item in $groupData) { if ($item -match "^250\s2.6.0\s(?'SmtpId'\S+)") { $Matches['SmtpId'].split("@")[1] } }
                if (-not $RemoteServerHostName) { $RemoteServerHostName = "" } else { $RemoteServerHostName = [string]::Join(",", $RemoteServerHostName.trim().trim(">") ) }

                [string[]]$InternalId = foreach ($item in $groupData) { if ($item -match "^250\s2\.6\.0\s.*InternalId=(?'InternalId'\w+)") { $Matches['InternalId'] } }
                if (-not $InternalId) { $InternalId = "" } else { $InternalId = [string]::Join(",", $XOOrg.trim() ) }

                [string[]]$MailSize = foreach ($item in $groupData) { if ($item -match "\w+(?=\sbytes\sin\s)") { $Matches[0] } }
                if (-not $MailSize) { $MailSize = "" } else { $MailSize = [string]::Join(",", $MailSize.trim() ) }

                ForEach ($item in $groupData) {
                    if ($item -match "(?<=\sbytes\sin\s)(\d|\.)+") {
                        $DeliveryDuration = $DeliveryDuration + [timespan]::FromSeconds( [System.Convert]::ToDouble($Matches[0], [cultureinfo]::GetCultureInfo('en-us') ))
                    }
                }
                ForEach ($item in $groupData) {
                    if ($item -match "(?'duration'(\d*|,)+)(?=\sKB\/sec\sQueued\smail\sfor\sdelivery)") {
                        $deliveryBandwidth = $deliveryBandwidth + [double]::Parse($Matches['duration'])
                    }
                }
            }

            if ($record.Group | Where-Object data -like "Tarpit*") { $TarpitDetect = $true } else { $TarpitDetect = $false }
            $TarpitDuration = [timespan]::new(0)
            $TarpitMessage = ""
            if ($TarpitDetect) {
                $TarpitDuration = [timespan]::FromSeconds( (($record.Group | where-Object data -like "Tarpit*").data.replace("Tarpit for '", "") | ForEach-Object { $_.split("'")[0] -as [timespan] } | Measure-Object Seconds -Sum).Sum )
                $TarpitMessage = (($record.Group | Where-Object data -like "Tarpit*").data -split "(due\sto\s')")[-1].trim("'")
            }

            [string]$ConnectorID = $record.Group.'connector-id'[0]
            if ($ConnectorID) { $ConnectorName = $ConnectorID.split("\")[1] } else { $ConnectorName = "" }
            if ($ConnectorID) { $ConnectorNameWithoutServerName = $ConnectorName.replace($ServerName, "").trim() } else { $ConnectorNameWithoutServerName = "" }
            [string]$localEndpoint = $record.Group.'local-endpoint'[0]
            [string]$remoteEndpoint = $record.Group.'remote-endpoint'[0]

            if ($groupData -clike "AUTH *") { $AuthenticationEnabled = $true } else { $AuthenticationEnabled = $false }
            $AuthenticationType = ""
            $AuthenticationUser = ""
            $AuthenticationMessage = ""
            if ($AuthenticationEnabled) {
                $null = $record.Group | Where-Object data -Match "^AUTH\s(?'Method'\S+)"
                $AuthenticationType = $Matches['Method']
                $AuthenticationUser = ($record.Group | Where-Object context -like "authenticated").data

                $text = @( "235 2.7.0 Authentication successful", "504 5.7.4 Unrecognized authentication type", "535 5.7.3 Authentication unsuccessful" )
                [string]$AuthenticationMessage = ($record.Group | Where-Object data -in $text)[-1].data
            }

            # TLS records
            if ($groupData -CLike "STARTTLS") { $TlsEnabled = $true } else { $TlsEnabled = $false }
            $TlsCrypto = ""
            $TlsProtocol = ""
            $TlsAlgorithmEncryption = ""
            $TlsAlgorithmMacHash = ""
            $TlsAlgorithmKeyExchange = ""
            $TlsCertificateServer = ""
            $TlsCertificateClient = ""
            $TlsDomainCapabilities = ""
            $TlsStatus = ""
            $TlsDomain = ""
            if ($TlsEnabled) {
                [int]$_start = ( ($record.Group | Where-Object data -like "220 2.0.0 SMTP server ready").'sequence-number' )[0]
                [int]$_stop = ( ($record.Group | Where-Object data -like "250  * Hello *").'sequence-number' | ForEach-Object { [int]$_ } | Where-Object { $_ -ge $start } )[0]
                $TlsRecords = $record.Group | Where-Object event -eq '*' | Where-Object { $_.'sequence-number' -gt $_start -or $_.'sequence-number' -lt $_stop } | Where-Object { $_.data -like "" -or $_.data -like " CN=" -or $_.context -like "* certificate *" } | Where-Object { $_.context -like "tls*" -or $_.context -like "* certificate *" -or $_.context -like "Validated*" } | Select-Object 'sequence-number', data, context

                $TlsCrypto = ($TlsRecords | Where-Object context -like "TLS *").context
                if (-not $TlsCrypto) { $TlsCrypto = "" } else { $TlsCrypto = [string]::Join(",", $TlsCrypto) }

                $TlsProtocol = foreach ($item in $TlsRecords) { if ($item -match "(?<=\sprotocol\s)\S+") { $Matches[0] } }
                if (-not $TlsProtocol) { $TlsProtocol = "" } else { $TlsProtocol = [string]::Join(",", $TlsProtocol) }

                $TlsAlgorithmEncryption = foreach ($item in $TlsRecords) { if ($item -match "(?<=\sencryption\salgorithm\s)\S+") { $Matches[0] } }
                if (-not $TlsAlgorithmEncryption) { $TlsAlgorithmEncryption = "" } else { $TlsAlgorithmEncryption = [string]::Join(",", $TlsAlgorithmEncryption) }

                $TlsAlgorithmMacHash = foreach ($item in $TlsRecords) { if ($item -match "(?<=\shash\salgorithm\s)\S+") { $Matches[0] } }
                if (-not $TlsAlgorithmMacHash) { $TlsAlgorithmMacHash = "" } else { $TlsAlgorithmMacHash = [string]::Join(",", $TlsAlgorithmMacHash) }

                $TlsAlgorithmKeyExchange = foreach ($item in $TlsRecords) { if ($item -match "(?<=\sexchange\salgorithm\s)\S+") { $Matches[0] } }
                if (-not $TlsAlgorithmKeyExchange) { $TlsAlgorithmKeyExchange = "" } else { $TlsAlgorithmKeyExchange = [string]::Join(",", $TlsAlgorithmKeyExchange) }

                $TlsCertificateServer = foreach ($item in ($TlsRecords | where-Object context -Like "Sending certificat*").data) { ([string]$item).trim() }
                if (-not $TlsCertificateServer) { $TlsCertificateServer = "" } else { $TlsCertificateServer = [string]::Join(",", $TlsCertificateServer) }

                $TlsCertificateClient = foreach ($item in ($TlsRecords | where-Object context -Like "Remote certificat*").data) { ([string]$item).trim() }
                if (-not $TlsCertificateClient) { $TlsCertificateClient = "" } else { $TlsCertificateClient = [string]::Join(",", $TlsCertificateClient) }

                #if(($TlsRecords | Where-Object context -Like "*; Status='*").context -Match "(?<=TlsDomainCapabilities=')(?'TlsDomainCapabilities'\S+)'|(?<=Status=')(?'Status'\S+)'|(?<=Domain=')(?'Domain'\S+)'") {
                #}
                $TlsStatusRecord = ($TlsRecords | Where-Object context -Like "*; Status='*").context -Split "; "
                $TlsDomainCapabilities = ("" + (($TlsStatusRecord | Where-Object { $_ -like "TlsDomainCapabilities=*" }) -split "=")[1] ).trim("'")
                if (-not $TlsDomainCapabilities) { $TlsDomainCapabilities = "" } else { $TlsDomainCapabilities = [string]::Join(",", $TlsDomainCapabilities) }

                $TlsStatus = ("" + (($TlsStatusRecord | Where-Object { $_ -like "Status=*" }) -split "=")[1] ).trim("'")
                if (-not $TlsStatus) { $TlsStatus = "" } else { $TlsStatus = [string]::Join(",", $TlsStatus) }

                $TlsDomain = ("" + (($TlsStatusRecord | Where-Object { $_ -like "Domain=*" }) -split "=")[1] ).trim("'")
                if (-not $TlsDomain) { $TlsDomain = "" } else { $TlsDomain = [string]::Join(",", $TlsDomain) }
            }

            $logtext = ""
            foreach ($item in $record.Group) {
                if ($item.data.Length -gt 0) {
                    $logtext = $logtext + "$(if($logtext){"`n"})" + $item.event + " " + $item.data
                    if ($item.context.Length -gt 0) {
                        $logtext = $logtext + "$(if($logtext){"`n"})" + $item.event + " " + $item.context
                    }
                } else {
                    $logtext = $logtext + "$(if($logtext){"`n"})" + $item.event + " " + $item.context
                }
            }


            # construct output object
            $outputRecord = [PSCustomObject]@{
                "PSTypeName"                     = "ExchangeLog.$($record.metadataHash['Log-type'].Replace(' ','')).Record.Expanded"
                "LogFolder"                      = $File.Directory
                "LogFileName"                    = $File.Name
                $sessionIdName                   = $record.Name
                "DateStart"                      = ($record.Group | Sort-Object 'date-time')[0].'date-time' -as [datetime]
                "DateEnd"                        = ($record.Group | Sort-Object 'date-time')[-1].'date-time' -as [datetime]
                "SequenceCount"                  = $record.Group.count
                "ConnectorID"                    = $ConnectorID
                "ServerName"                     = $ServerName
                "ConnectorName"                  = $ConnectorName
                "ConnectorNameWithoutServerName" = $ConnectorNameWithoutServerName
                "LocalIP"                        = $localEndpoint.split(":")[0]
                "LocalPort"                      = $localEndpoint.split(":")[1]
                "RemoteIP"                       = $remoteEndpoint.split(":")[0]
                "RemotePort"                     = $remoteEndpoint.split(":")[1]
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
                "TlsCrypto"                      = $TlsCrypto
                "TlsProtocol"                    = $TlsProtocol
                "TlsAlgorithmEncryption"         = $TlsAlgorithmEncryption
                "TlsAlgorithmMacHash"            = $TlsAlgorithmMacHash
                "TlsAlgorithmKeyExchange"        = $TlsAlgorithmKeyExchange
                "TlsCertificateServer"           = $TlsCertificateServer
                "TlsCertificateClient"           = $TlsCertificateClient
                "TlsDomainCapabilities"          = $TlsDomainCapabilities
                "TlsStatus"                      = $TlsStatus
                "TlsDomain"                      = $TlsDomain
                "LogText"                        = $LogText
            }

            foreach ($key in $metadataHash.Keys) {
                $outputRecord | Add-Member -MemberType NoteProperty -Name $key -Value $metadataHash[$key] -Force
            }
            #$null = $output.Add( $outputRecord )
            $outputRecord
        }

    }

    end {

    }
}

#(Get-Command Expand-LogRecord).Visibility = "Private"