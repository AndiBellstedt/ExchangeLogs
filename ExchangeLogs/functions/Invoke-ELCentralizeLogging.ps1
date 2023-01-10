function Invoke-ELCentralizeLogging {
    <#
    .SYNOPSIS
        Copy function for centralizing log files out of exchange servers

    .DESCRIPTION
        This one is a utility function inside the ExchangeLogs module.
        It's intendet to create a centralized logging directory to gather logfiles (supported by the module) from all exchange servers into a single directory or fileshare and withing a folder structure eligible for further processing.

        The intented workflow provided by this function:
        - find a exchange server to connect on via active directory serviceconnectionpoitns
        - connect to exchange server
        - find all exchange servers and subsequently query logging path for supported services
        - copy the logfiles out of the exchange servers to a central logging share (usually a staging folder, due to further processing with Invoke-ELExchangeLogConvert. See more info in Invoke-ELExchangeLogConvert help.)
        - remembering last processed file, to reduce noise and load on next processing

        Requirements:
        - The executing user needs the permission to connect with powershell remoting into exchange server
            - Predefined roles like "Organization Management" or "Server Management" can be used
            - Find/ create a individual management role with Get-ManagementRole cmdlet
        - The executing user needs permission to access the administrative shares on the server
        - The users needs read/write permission on the central network share

        The workflow will be:
        - First, find all logs and centralize them into a staging-folder with 'Invoke-ELCentralizeLogging'
        - Second, process staging-folder with 'Invoke-ELExchangeLogConvert' and build read- and processable CSV files in a reporting-folder
        - Use other BI-/Analytical tools to process the CSV Files in the reporting folder

    .PARAMETER Destination
        The path to copy all logfiles from the exchange server(s) to.
        Can be a local directory, or a fileshare (recommended)

    .PARAMETER FilterServer
        Filter parameter to in-/exclude certain exchange server from processing.
        The filter is applied in a "like"-matching process, so wildcards and multiple values for inclusion are supportet.

        Default value: *

    .PARAMETER IncludeLog
        Filter parameter to specify the type of logs to query and process.
        This filter ofers a predefined set of values: "All", "HubTransport", "Frontendtransport", "IMAP4", "POP3"

        Multiple values are supported.
        Default value: All

    .PARAMETER DirectoryLastProcessedFile
        The folder where the function search for the information which file was processed as last file on the previous run.
        Should be a local directory, but can also be a share.

        Default value: C:\Administration\Logs\Exchange\CentralizedLogs

    .PARAMETER LogFile
        The logfile to archive processing information.

        Default value: -not specified-
        Recommended:   C:\Administration\Logs\Exchange\CentralizeExchangeLogs.log

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .EXAMPLE
        PS C:\> Invoke-ELCentralizeLogging -Destination "\\SRV01\Logs\Exchange\Staging"

        Gathers all exchange servers with all supported logs and copy it to the share "\\SRV01\Logs\Exchange\Staging".
        No log is written, there are basic output information on the console and extended logging information in the session via "Get-PSFMessage".

    .EXAMPLE
        PS C:\> Invoke-ELCentralizeLogging -Destination "\\$($env:USERDNSDOMAIN)\system\Logs\Exchange\Staging" -LogFile "C:\Administration\Logs\CentralizedLogs\CentralizeExchangeLogs.log"

        Gathers all exchange servers with all supported logs and copy it to the share "\\$($env:USERDNSDOMAIN)\System\Logs\Exchange\Staging". This one assumes, there is a DFS share "System" in your domain with a folder "logs".
        Script actions are written to a logfile 'C:\Administration\Logs\CentralizedLogs\CentralizeExchangeLogs.log' for informationtracking of the process state. This one is usally recommended for usage in scheduled tasks/ automation.

        Additonally, there are basic output information on the console and extended logging information in the session via "Get-PSFMessage".

    .EXAMPLE
        PS C:\> Invoke-ELCentralizeLogging -Destination "\\SRV01\Logs\Exchange\Staging" -DirectoryLastProcessedFile "C:\Administration\Logs\CentralizedLogs" -LogFile "C:\Administration\Logs\CentralizedLogs\CentralizeExchangeLogs.log" -FilterServer "Ex01", "Ex02" -IncludeLog "HubTransport", "Frontendtransport"

        Gathers only exchange server "Ex01" and "Ex02" and only SMTP logs (Hub and Frontend transport service) and copy it to the share "\\SRV01\Logs\Exchange\Staging".
        Last processed files will be remembered in directory "C:\Administration\Logs\CentralizedLogs". This is the default used directory, but it can be changed to anything else.
        Script actions are written to a logfile 'C:\Administration\Logs\CentralizedLogs\CentralizeExchangeLogs.log' for informationtracking of the process state. This one is usally recommended for usage in scheduled tasks/ automation.

        Additonally, there are basic output information on the console and extended logging information in the session via "Get-PSFMessage".

    .EXAMPLE
        PS C:\> Invoke-ELCentralizeLogging -Path "\\$($env:USERDNSDOMAIN)\system\Logs\Exchange\Staging" -LastFileDirectory "C:\Administration\Logs\CentralizedLogs"

        Same result as in previous examples but with alias "Path" and "LastFileDirectory" on parameters "Destination" and "DirectoryLastProcessedFile".
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [Alias("Path")]
        [String]
        $Destination,

        [string[]]
        $FilterServer = "*",

        [ValidateSet("All", "HubTransport", "Frontendtransport", "IMAP4", "POP3")]
        [string[]]
        $IncludeLog = "All",

        [Alias("LastFileDirectory")]
        [String]
        $DirectoryLastProcessedFile = "C:\Administration\Logs\Exchange\CentralizedLogs",

        [String]
        $LogFile
    )

    begin {}

    process {}

    end {
        #region Init and prerequisites
        if ($LogFile) { Initialize-LogFile -LogFile $LogFile -AlternateLogName $MyInvocation.MyCommand -LogInstanceName "ExchangeLogs" }
        Write-PSFMessage -Level Host -Message "----- Start script -----" -Tag "ExchangeLogs"

        # variables
        Write-PSFMessage -Level System -Message "Initialize variables" -Tag "ExchangeLogs"
        if ($DirectoryLastProcessedFile.EndsWith("\")) { $DirectoryLastProcessedFile = $DirectoryLastProcessedFile.TrimEnd("\") }
        if ($Destination.EndsWith("\")) { $Destination = $Destination.TrimEnd("\") }

        # find exchange server in active directory
        try {
            $adsiSearch = ([ADSISearcher]'(&(objectclass=serviceconnectionpoint)(|(keywords=77378F46-2C66-4aa9-A6A6-3E7A48B19596)(keywords="67661d7F-8FC4-4fa7-BFAC-E1D7794C1F68")))')
            $adsiSearch.SearchRoot = [adsi]"LDAP://CN=Services,CN=Configuration,$(([adsi]::new()).distinguishedName)"
            $exServerName = ($adsiSearch.FindOne()).Properties['Name']
        } catch {
            Stop-PSFFunction -Message "Unable to query active directory for exchange serviceconnectionpoint (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -Tag "ExchangeLogs"
            throw
        }
        Write-PSFMessage -Level System -Message "Found exchange server: $($exServerName)" -Tag "ExchangeLogs"


        # check directories
        Write-PSFMessage -Level System -Message "Check directory to memorize last processed file ($($DirectoryLastProcessedFile))" -Tag "ExchangeLogs"
        if (-not (Test-Path -Path $DirectoryLastProcessedFile)) {
            try {
                $null = New-Item -Path $DirectoryLastProcessedFile -ItemType Directory -Force -ErrorAction Stop
            } catch {
                Stop-PSFFunction -Message "Error creating directory to memorize last processed file '$($DirectoryLastProcessedFile)' (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception  -Tag "ExchangeLogs"
                throw
            }
        }

        Write-PSFMessage -Level System -Message "Check destination directory ($($Destination))" -Tag "ExchangeLogs"
        if (-not (Test-Path -Path $Destination)) {
            try {
                $null = New-Item -Path $Destination -ItemType Directory -Force -ErrorAction Stop
            } catch {
                Stop-PSFFunction -Message "Error creating destination directory '$($DirectoryLastProcessedFile)' (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -Tag "ExchangeLogs"
                throw
            }
        }


        # connect to exchange server
        Write-PSFMessage -Level Verbose -Message "Init exchange session" -Tag "ExchangeLogs"
        try {
            $exSession = New-PSSession -ConfigurationName Microsoft.Exchange -ErrorAction Stop -ConnectionUri "http://$($exServerName)/PowerShell/"
            $null = Import-PSSession $exSession -DisableNameChecking -ErrorAction Stop
        } catch {
            Stop-PSFFunction -Message "Error connecting exchange session '$($exServerName)' (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -Tag "ExchangeLogs"
            throw
        }
        Write-PSFMessage -Level Verbose -Message "Created $($exSession.count) sessions. Server:$($exServerName)" -Tag "ExchangeLogs"


        #endregion Init and prereqs



        #region Query Logdata from exchange
        # query log paths
        $exServer = Get-ExchangeServer
        $exServer = foreach ($filterItem in $FilterServer) {
            $exServer | Where-Object -Property Name -Like $filterItem
        }
        $exServer = $exServer | Sort-Object -Property Name -Unique
        Write-PSFMessage -Level Verbose -Message "Found $($exServer.count) exchange server" -Tag "ExchangeLogs"

        if ("All" -in $IncludeLog -or "HubTransport" -in $IncludeLog) {
            $logPathSmtpHub = Get-TransportService | Sort-Object -Property Name | Select-Object -Property Name, SendProtocolLogPath, ReceiveProtocolLogPath
            Write-PSFMessage -Level Verbose -Message "Found $($logPathSmtpHub.count) TransportService" -Tag "ExchangeLogs"
        }

        if ("All" -in $IncludeLog -or "Frontendtransport" -in $IncludeLog) {
            $logPathSmtpFrontEnd = Get-FrontEndTransportService | Sort-Object -Property Name | Select-Object -Property Name, SendProtocolLogPath, ReceiveProtocolLogPath
            Write-PSFMessage -Level Verbose -Message "Found $($logPathSmtpFrontEnd.count) FrontEndTransportService" -Tag "ExchangeLogs"
        }

        if ("All" -in $IncludeLog -or "IMAP4" -in $IncludeLog) {
            $logPathImap = $exServer | ForEach-Object { Get-ImapSettings -Server $_.name } | Sort-Object -Property Server | Select-Object -Property Server, LogFileLocation
            Write-PSFMessage -Level Verbose -Message "Found $($logPathImap.count) ImapSettings" -Tag "ExchangeLogs"
        }

        if ("All" -in $IncludeLog -or "POP3" -in $IncludeLog) {
            $logPathPop = $exServer | ForEach-Object { Get-PopSettings -Server $_.name } | Sort-Object -Property Server | Select-Object -Property Server, LogFileLocation
            Write-PSFMessage -Level Verbose -Message "Found $($logPathPop.count) PopSettings" -Tag "ExchangeLogs"
        }


        # build server/path list
        $sourcePaths = @()
        # SMTP Hub Transportservice
        foreach ($item in $logPathSmtpHub) {
            $sourcePaths += [PSCustomObject]@{
                "ComputerName" = $item.Name
                "Path"         = $item.SendProtocolLogPath
                "Type"         = "Transport-Hub"
            }
            $sourcePaths += [PSCustomObject]@{
                "ComputerName" = $item.Name
                "Path"         = $item.ReceiveProtocolLogPath
                "Type"         = "Transport-Hub"
            }
        }

        # SMTP Frontend Transportservice
        foreach ($item in $logPathSmtpFrontEnd) {
            $sourcePaths += [PSCustomObject]@{
                "ComputerName" = $item.Name
                "Path"         = $item.SendProtocolLogPath
                "Type"         = "Transport-FrontEnd"
            }
            $sourcePaths += [PSCustomObject]@{
                "ComputerName" = $item.Name
                "Path"         = $item.ReceiveProtocolLogPath
                "Type"         = "Transport-FrontEnd"
            }
        }

        # IMAP service
        foreach ($item in $logPathImap) {
            $sourcePaths += [PSCustomObject]@{
                "ComputerName" = $item.Server
                "Path"         = $item.LogFileLocation
                "Type"         = "ClientAccess"
            }
        }

        # POP3 service
        foreach ($item in $logPathPop) {
            $sourcePaths += [PSCustomObject]@{
                "ComputerName" = $item.Server
                "Path"         = $item.LogFileLocation
                "Type"         = "ClientAccess"
            }
        }
        $sourcePaths = $sourcePaths | Sort-Object ComputerName, Path
        Write-PSFMessage -Level Verbose -Message "$($sourcePaths.count) paths to process." -Tag "ExchangeLogs"


        #endregion Query Logdata from exchange



        #region process logfiles
        Write-PSFMessage -Level Host -Message "Start working through each server and each directory" -Tag "ExchangeLogs"


        # work through each server and each directory
        foreach ($server in $exServer.name) {
            Write-PSFMessage -Level Verbose -Message "Working with $($server)"
            $sourcePathInServer = $sourcePaths | Where-Object ComputerName -like $server

            foreach ($source in $sourcePathInServer) {
                # variables for directory
                $counter = 0
                $processedFiles = @()
                $lastFile = "$($DirectoryLastProcessedFile)\Last-$($source.Type)-$($source.Path.split("\")[-1])-$($server).xml"
                $destinationPath = "$($Destination)\$($source.Type)\$($source.Path.split("\")[-1])\$($server)"

                Write-PSFMessage -Level Verbose -Message "Processing: $($source) --to--> '$destinationPath'" -Tag "ExchangeLogs"

                # test and create destination directory
                Write-PSFMessage -Level VeryVerbose -Message "Check destination path '$($destinationPath)'" -Tag "ExchangeLogs"
                if (-not (Test-Path -Path $destinationPath)) {
                    try {
                        $null = New-Item -Path $destinationPath -ItemType Directory -Force
                    } catch {
                        Stop-PSFFunction -Message "Unable to create directory '$($destinationPath)' (Message: $($_.Exception.Message))" -ErrorRecord $_ -Exception $_.exception -Tag "ExchangeLogs"
                        throw
                    }
                }

                # gathering files
                $sourcePath = "\\$($server)\$($source.path.Replace(":","$"))"
                $sourceFiles = Get-ChildItem -Path $sourcePath | Sort-Object -Property Name
                Write-PSFMessage -Level VeryVerbose -Message "There are $($sourceFiles.count) files in $($source)" -Tag "ExchangeLogs"

                # enumerate files in source to getting an filterable order
                foreach ($file in $sourceFiles) {
                    $file | Add-Member -NotePropertyName "Order" -NotePropertyValue $counter -Force
                    $counter++
                }

                # if exist, query last processed file
                if (Test-Path -Path $LastFile) { $lastFileProcessed = Import-PSFClixml -Path $LastFile } else { $lastFileProcessed = $null }
                if ($lastFileProcessed) {
                    $sourceFileStartFilter = $sourceFiles | Where-Object Name -like $lastFileProcessed.Name
                    $sourceFiles = $sourceFiles | Where-Object order -gt $sourceFileStartFilter.Order
                }

                # ignore current logfile
                $sourceFiles = $sourceFiles[0 .. ($sourceFiles.count - 2)]
                Write-PSFMessage -Level VeryVerbose -Message "$($sourceFiles.count) files to process" -Tag "ExchangeLogs"


                # copy files to destination
                foreach ($file in $sourceFiles) {
                    Write-PSFMessage -Level Debug -Message "Copy $($file.Name)" -Tag "ExchangeLogs"
                    try {
                        if ($pscmdlet.ShouldProcess("$($file.FullName) to $($destinationPath)", "Copy")) {
                            Copy-Item -Path $file.FullName -Destination $destinationPath -ErrorAction Stop
                        }
                        $processedFiles += $file
                    } catch {
                        Stop-PSFFunction -Message "Unable to copy file $($file.name) to $($destinationPath). (Message: $($_.Exception.Message))" -ErrorRecord $_ -Exception $_.exception -Tag "ExchangeLogs"
                        throw
                    }
                }


                # export lastprocessed file for next run
                if ($processedFiles) {
                    Write-PSFMessage -Level Host -Message "Processed $($processedFiles.count) files and remembering LastFileProcessed: $($processedFiles[-1].FullName)" -Tag "ExchangeLogs"
                    if ($pscmdlet.ShouldProcess("Last processed file '$($processedFiles[-1].FullName)' to $($lastFile)", "Export")) {
                        $processedFiles[-1] | Export-PSFClixml -Path $lastFile
                    }
                } else {
                    Write-PSFMessage -Level Host -Message "No files processed from directory: $($sourcePath)" -Tag "ExchangeLogs"
                }
            }
        }
        #endregion process logfiles



        #region cleanup
        Write-PSFMessage -Level VeryVerbose -Message "Closing exchange session" -Tag "ExchangeLogs"
        $exSession | Remove-PSSession

        Write-PSFMessage -Level Host -Message "*** Finishing script ***" -Tag "ExchangeLogs"
        #endregion cleanup
    }
}