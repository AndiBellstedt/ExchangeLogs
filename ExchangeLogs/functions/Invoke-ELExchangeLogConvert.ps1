function Invoke-ELExchangeLogConvert {
    <#
    .SYNOPSIS
        Convert frunction to recursively process a folder structure and convert exchange logs to CSV files

    .DESCRIPTION
        This one is a utility function inside the ExchangeLogs module.
        It's intendet to parse through a folder structure (staging directory, filled by Invoke-ELCentralizeLogging), find all exchange logfiles (supported by the module) and convert the files into flatten and better read-/processable CSV files.

        The intented workflow provided by this function:
          - Parse through "Source" folder structure and find logfiles
          - convert logfiles to csv files and put them in the "Destination" folder. The folder structrue from source directory will be preserved and rebuild in destination folder
          - Processed files will be move to "Archive" folder. The folder structrue from source directory will be preserved and rebuild in archive folder.

        Requirements:
          - The users needs read/write permission on the central network share

        The workflow will be:
        - First, find all logs and centralize them into a staging-folder with 'Invoke-ELCentralizeLogging'
        - Second, process staging-folder with 'Invoke-ELExchangeLogConvert' and build read- and processable CSV files in a reporting-folder
        - Use other BI-/Analytical tools to process the CSV Files in the reporting folder

    .PARAMETER Source
        Path to folder where logfiles are stored for processing
        This one can also called 'staging directory'

    .PARAMETER Destination
        Path to store converted CSV files from exchange service logs
        This one can also called 'reporting directory'

        Default value: A folder "Reporting" next to the folder specified in source parameter

    .PARAMETER Archive
        Path fo archiving the processed exchange service log files out of the source directory
        This is only for archival reason.
        If no folder is specified, the logs in the source folder will be deleted!

        Default value: A folder "Archive" next to the folder specified in source parameter

    .PARAMETER Filter
        Name filter for files to be processed in the source directory

        Default value: *.log

    .PARAMETER MaxFileCount
        Amount of files processed in a processing cycle per directory.
        The higher the number, the more memory and time is consumed for processing.
        Assume usally at least 24 files per service (SMTP, IMAP, POP, ...) per exchange server

        Default value: 200

    .PARAMETER LogFile
        The logfile to archive processing information.

        Default value: -not specified-
        Recommended:   C:\Administration\Logs\Exchange\ExchangeLogConvert.log

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .EXAMPLE
        PS C:\> Invoke-ELExchangeLogConvert -Source "\\SRV01\Logs\Exchange\Staging" -Destination "\\SRV01\Logs\Exchange\Reporting" -Archive "\\SRV01\Logs\Exchange\Archive"


    .EXAMPLE
        PS C:\> Invoke-ELExchangeLogConvert -Source "\\$($env:USERDNSDOMAIN)\System\Logs\Exchange\Staging" -Destination "\\$($env:USERDNSDOMAIN)\System\Logs\Exchange\Reporting" -Archive "\\$($env:USERDNSDOMAIN)\system\Logs\Exchange\Archive" -MaxFileCount 1000 -Log "C:\Administration\Logs\Exchange\ExchangeLogConvert.log"

#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [String]
        $Source,

        [String]
        $Destination = "$(Split-Path -Path $Source)\Reporting",

        [String]
        $Archive = "$(Split-Path -Path $Source)\Archive",

        [String]
        $Filter = "*.log",

        [int]
        $MaxFileCount = 200,

        [String]
        $LogFile = "C:\Administration\Logs\Exchange\ExchangeLogConvert.log"
    )

    begin {}

    process {}

    end {
        #region Init and prerequisites
        if ($LogFile) { Initialize-LogFile -LogFile $LogFile -AlternateLogName $MyInvocation.MyCommand -LogInstanceName "ExchangeLogs" }
        Write-PSFMessage -Level Host -Message "----- Start script -----" -Tag "ExchangeLogs"


        # variables
        Write-PSFMessage -Level System -Message "Initialize variables" -Tag "ExchangeLogs"
        if ($Source.EndsWith("\")) { $Source = $Source.TrimEnd('\') }
        if ($Destination.EndsWith("\")) { $Destination = $Destination.TrimEnd('\') }
        if ($Archive.EndsWith("\")) { $Archive = $Archive.TrimEnd('\') }

        $dateStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"


        # check paths
        Write-PSFMessage -Level System -Message "Checking source-, destination- and archival-directory" -Tag "ExchangeLogs"
        # source
        try {
            $sourceDir = $Source | Get-Item -ErrorAction Stop
        } catch {
            Stop-PSFFunction -Message "Source directory not found! (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -ErrorAction Stop -Tag "ExchangeLogs"
            throw
        }
        # destination
        try {
            $destinationDir = $Destination | Get-Item -ErrorAction Stop
        } catch {
            Stop-PSFFunction -Message "Destination directory not found! (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -ErrorAction Stop -Tag "ExchangeLogs"
            throw
        }
        # archive
        try {
            $archiveDir = $Archive | Get-Item -ErrorAction Stop
        } catch {
            Stop-PSFFunction -Message "Archive directory not found! (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -ErrorAction Stop -Tag "ExchangeLogs"
            throw
        }


        #endregion Init and prerequisites



        #region recursing function
        function Invoke-SubDirectoryProcessing {
            [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
            param (
                $SourceDir,

                $DestinationDir,

                $ArchiveDir,

                $Filter,

                $LogFile,

                [string]
                $DateStamp,

                [int]
                $MaxFileCount,

                [String]
                $NamePart
            )

            $subDirectory = $SourceDir | Get-ChildItem -Directory
            foreach ($directory in $subDirectory) {
                Write-PSFMessage -Level Verbose -Message "Working on directory '$($directory.fullname)'" -Tag "ExchangeLogs"
                # variables
                $destPath = "$($DestinationDir)\$($directory.Name)"
                $archivePath = "$($ArchiveDir)\$($directory.Name)"
                if ($NamePart) { $NamePart = "$($NamePart)-$($directory.Name)" } else { $NamePart = $directory.Name }
                $tempFile = "$($env:TEMP)\ELExchangeLogConvert_$([guid]::NewGuid().tostring()).csv"


                # folder tests
                Write-PSFMessage -Level System -Message "Checking directory '$($destPath)' exists" -Tag "ExchangeLogs"
                if (-not (Test-Path -Path $destPath)) {
                    try {
                        $null = New-Item -Path $destPath -ItemType Directory -Force -ErrorAction Stop
                    } catch {
                        Stop-PSFFunction -Message "Error creating '$($destPath)' (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -ErrorAction Stop -Tag "ExchangeLogs"
                        throw
                    }
                }

                Write-PSFMessage -Level System -Message "Checking directory '$($archivePath)' exists" -Tag "ExchangeLogs"
                if (-not (Test-Path -Path $archivePath)) {
                    try {
                        $null = New-Item -Path $archivePath -ItemType Directory -Force -ErrorAction Stop
                    } catch {
                        Stop-PSFFunction -Message "Error creating '$($archivePath)' (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -ErrorAction Stop -Tag "ExchangeLogs"
                        throw
                    }
                }


                # file processing
                $filesToProcess = $directory | Get-ChildItem -Filter $Filter -File -Force | Select-Object -First $MaxFileCount
                if ($filesToProcess) {
                    Write-PSFMessage -Level Verbose -Message "$($filesToProcess.count) files to process in directory '$($directory.name)'" -Tag "ExchangeLogs"


                    # import and convert data from logfiles
                    Write-PSFMessage -Level System -Message "Start ExchangeLog conversion in temp file '$($tempFile)'" -Tag "ExchangeLogs"
                    try {
                        if ($pscmdlet.ShouldProcess("$($filesToProcess.count) files in $($directory) and save results to $($tempFile)", "Convert")) {
                            $filesToProcess | Get-ELExchangeLog -ErrorAction Stop | Export-Csv -Path $tempFile -Delimiter ";" -Encoding UTF8 -NoTypeInformation -Force -Append -ErrorAction Stop
                        }
                    } catch {
                        Stop-PSFFunction -Message "Error importing and converting data from folder '$($directory.fullname)' (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -ErrorAction Stop -Tag "ExchangeLogs"
                        throw
                    }
                    Write-PSFMessage -Level System -Message "Finsh conversion into temp file '$($tempFile)'" -Tag "ExchangeLogs"


                    # explort data to csv file
                    $exportFilePath = "$($destPath)\$($NamePart)_$($DateStamp).csv"
                    Write-PSFMessage -Level System -Message "Copy temp file to destination '$($exportFilePath)'" -Tag "ExchangeLogs"
                    try {
                        if (Test-Path -Path $exportFilePath) {
                            # unlikely, but possible
                            if ($pscmdlet.ShouldProcess("Content from '$($tempFile)' into existing file $($exportFilePath)", "Add")) {
                                Get-Content -Path $tempFile -ErrorAction Stop | Out-File -FilePath $exportFilePath -Encoding UTF8 -Append -ErrorAction Stop
                                $exportFile = Get-Item -Path $exportFilePath -ErrorAction Stop
                            }
                        } else {
                            # hopefully, the usual case
                            if ($pscmdlet.ShouldProcess("'$($tempFile)' to '$($exportFilePath)'", "Copy")) {
                                $exportFile = Copy-Item -Path $tempFile -Destination $exportFilePath -PassThru -ErrorAction Stop
                            }
                        }
                    } catch {
                        Stop-PSFFunction -Message "Error exporting data to csv file '$($exportFilePath)' (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -ErrorAction Stop -Tag "ExchangeLogs"
                        throw
                    }
                    Write-PSFMessage -Level Verbose -Message "Done with data export. Filesize: $($exportFile.Length / 1KB) KB, File: $($exportFile.FullName)" -Tag "ExchangeLogs"


                    # temp file cleanup
                    Write-PSFMessage -Level System -Message "Going to clean up '$($tempFile)'" -Tag "ExchangeLogs"
                    if ($pscmdlet.ShouldProcess("$($tempFile)", "Remove")) {
                        Remove-Item -Path $tempFile -Force -Confirm:$false -WhatIf:$false
                    }


                    # move processed data to archive
                    Write-PSFMessage -Level Verbose -Message "Moving processed files to '$($archivePath)'" -Tag "ExchangeLogs"
                    try {
                        if ($pscmdlet.ShouldProcess("$($filesToProcess.count) files from '$($destPath)' to '$($archivePath)'", "Move")) {
                            $filesToProcess | Move-Item -Destination $archivePath -Force -ErrorAction Stop
                        }
                    } catch {
                        Stop-PSFFunction -Message "Error moving files to archive directory '$($archivePath)'  (Message: $($_.exception.message))" -ErrorRecord $_ -Exception $_.exception -ErrorAction Stop -Tag "ExchangeLogs"
                        throw
                    }
                } else {
                    Write-PSFMessage -Level System -Message "No files to process in directory '$($directory.name)'" -Tag "ExchangeLogs"
                }


                # invoke recursion down the subdirectories
                Write-PSFMessage -Level System -Message "Calling recursive function for next directory" -Tag "ExchangeLogs"
                $paramsSubDirectoryProcessing = @{
                    "SourceDir"      = $directory
                    "DestinationDir" = $destPath
                    "ArchiveDir"     = $archivePath
                    "Filter"         = $Filter
                    "MaxFileCount"   = $MaxFileCount
                    "Log"            = $LogFile
                    "DateStamp"      = $DateStamp
                    "NamePart"       = $NamePart
                }
                if (Test-PSFParameterBinding -ParameterName "Whatif") { $paramsSubDirectoryProcessing.Add("Whatif", $true) }
                if (Test-PSFParameterBinding -ParameterName "Confirm") { $paramsSubDirectoryProcessing.Add("Confirm", $true) }
                Invoke-SubDirectoryProcessing @paramsSubDirectoryProcessing


                # trim name part
                if ($NamePart) { $NamePart = $NamePart.TrimEnd("-$($directory.Name)") }
            }
        }


        #endregion recursing function



        #region main script
        Write-PSFMessage -Level Host -Message "Start parsing '$($Source)' for log files to process." -Tag "ExchangeLogs"

        $paramsSubDirectoryProcessing = @{
            "SourceDir"      = $Source
            "DestinationDir" = $Destination
            "ArchiveDir"     = $Archive
            "Filter"         = $Filter
            "MaxFileCount"   = $MaxFileCount
            "Log"            = $LogFile
            "DateStamp"      = $DateStamp
            "NamePart"       = $NamePart
        }
        if (Test-PSFParameterBinding -ParameterName "Whatif") { $paramsSubDirectoryProcessing.Add("Whatif", $true) }
        if (Test-PSFParameterBinding -ParameterName "Confirm") { $paramsSubDirectoryProcessing.Add("Confirm", $true) }
        Invoke-SubDirectoryProcessing @paramsSubDirectoryProcessing

        Write-PSFMessage -Level Host -Message "*** Finishing script ***" -Tag "ExchangeLogs"
        #endregion main script
    }
}