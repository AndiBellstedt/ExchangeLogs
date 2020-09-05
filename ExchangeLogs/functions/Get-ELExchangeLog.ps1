function Get-ELExchangeLog {
    <#
    .SYNOPSIS
        Get records from exchange logfiles

    .DESCRIPTION
        Get records from exchange logfiles like SMTP Receive / SMTP Send / IMAP / POP /...
        Files are parsed and grouped by sessions as possible.

    .PARAMETER Path
        The folder to gather logfiles

    .PARAMETER Recurse
        If specified, the path will be gathered recursive

    .PARAMETER Filter
        Filter to be applied for files to parse

    .PARAMETER LogType
        Specifies the type of logfile to work through. There are multiple types supported and usually the command does an autodectect.
        Use tab completion on the parameter to see the supported logfile types.

        Use this parameter of your workload expects an explicit type of log (for example "SMTPReceiveProtocolLog") and you want to ensure, that no other logfiles are processed.

    .EXAMPLE
        PS C:\> Get-ELExchangeLog -Path "C:\Logs\SMTPReceive"

        Return records from all files in the folder

    .EXAMPLE
        PS C:\> Get-ELExchangeLog -Path "C:\Logs\SMTPReceive" -Recursive

        Return records from all files in the current and all subfolders.
#>
    [CmdletBinding()]
    [Alias('gel')]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [String[]]
        $Path,

        [switch]
        $Recurse,

        [String]
        $Filter = "*.log",

        [ValidateSet("AutoDetect", "SMTPReceiveProtocolLog", "SMTPSendProtocolLog", "IMAP4Log", "POP3Log","MessageTrackingLog")]
        [string]
        $LogType = "AutoDetect"
    )

    begin {
        $files = New-Object -TypeName "System.Collections.ArrayList"
        $batchJobId = $([guid]::NewGuid().ToString())
        Write-PSFMessage -Level VeryVerbose -Message "Starting BatchId '$($batchJobId)' with LogType '$LogType'"
    }

    process {
        # get files from folder
        Write-PSFMessage -Level Verbose -Message "Gettings files$( if($Filter){" by filter '$($Filter)'"} ) in path '$path'"
        foreach ($pathItem in $Path) {
            $options = @{
                "Path"        = $pathItem
                "File"        = $true
                "ErrorAction" = "Stop"
            }
            if ($Recurse) { $options.Add("Recurse", $true) }
            try {
                $ChildItemList = Get-ChildItem @options | Where-Object Length -ne 0
                if ($Filter) {
                    $ChildItemList = $ChildItemList | Where-Object Name -like $Filter
                }
                ($ChildItemList).FullName | Sort-Object | ForEach-Object { [void]$files.Add( $_ ) }
            } catch {
                Stop-PSFFunction -Message "Error, path '$($pathItem)' not found"
            }
        }
    }

    end {
        if (-not $files) {
            Stop-PSFFunction -Message "No file found to parse! ($([string]::Join(", ", $Path)))"
            break
        }
        $recordCount = 0
        $files = $files | Sort-Object
        if ($files.count -lt 100) { $refreshInterval = 1 } else { $refreshInterval = [math]::Round($files.count / 100) }
        Write-PSFMessage -Level Verbose -Message "$($files.count) file$(if($files.count -gt 1){"s"}) to process."

        $traceTimer = New-Object System.Diagnostics.Stopwatch
        $traceTimer.Start()

        # Import first file
        if ($files.Count -gt 1) {
            $filePrevious = $files[0]
        } else {
            $filePrevious = $files
        }
        $resultPreviousFile = New-Object -TypeName "System.Collections.ArrayList"
        foreach ($record in (Import-LogData -File $filePrevious)) { [void]$resultPreviousFile.Add($record) }
        $sessionIdName = Resolve-SessionIdName -LogType $resultPreviousFile[0].'Log-type'

        # file validity check
        if($LogType -ne "AutoDetect") {
            if($LogType -notlike $resultPreviousFile[0].'Log-type'.Replace(" ", "")) {
                Stop-PSFFunction -Message "Invalid LogType detected/specified. Expect '$($LogType)', but found '$( $resultPreviousFile[0].'Log-type'.Replace(' ', '') )' in file '$($filePrevious)'."
                break
            }
        } else {
            $LogType = $resultPreviousFile[0].'Log-type'.Replace(" ", "")
        }
        if($LogType -notin (Get-PSFConfigValue -FullName 'ExchangeLogs.SupportedLogTypes')) {
            Stop-PSFFunction -Message "Invalid LogType detected. '$( $resultPreviousFile[0].'Log-type'.Replace(' ', '') )' from file '$($filePrevious)' is not a supported log type to process with this command."
            break
        }

        # Import remaining files
        Write-PSFMessage -Level Verbose -Message "Starting import on $($files.Count) remaining file(s)."
        for ($filecounter = 1; $filecounter -lt $files.Count; $filecounter++) {
            #region process
            # import next file
            $fileCurrent = $files[$filecounter]
            $resultCurrentFile = New-Object -TypeName "System.Collections.ArrayList"
            foreach ($record in (Import-LogData -File $fileCurrent)) { [void]$resultCurrentFile.Add($record) }

            if ($resultCurrentFile[0].'Log-type' -ne $resultPreviousFile[0].'Log-type') {
                Stop-PSFFunction -Message "Incompatible logfile types ($($resultCurrentFile[0].'Log-type'), $($resultPreviousFile[0].'Log-type')) found! More then one type of logfile in folder '$($pathItem)'."
                break
            }


            if ($sessionIdName) {
                # loop through previous and current file to check on fragmented session records in both files (sessions over midnight)
                Write-PSFMessage -Level VeryVerbose -Message "Checking for overlapping log records on identifier '$($sessionIdName)' in file '$($filePrevious)' and  '$($fileCurrent)'"
                $overlapSessionIDs = Compare-Object -ReferenceObject $resultPreviousFile[-1..-20] -DifferenceObject $resultCurrentFile[0..20] -Property $sessionIdName -ExcludeDifferent -IncludeEqual
                if ($overlapSessionIDs) {
                    foreach ($overlapSessionId in $overlapSessionIDs.$sessionIdName) {
                        Write-PSFMessage -Level VeryVerbose -Message "Found overlapping log record '$($overlapSessionId)'"

                        # get the record fragments from both logfiles
                        $overlapRecordCurrentFile = $resultCurrentFile | Where-Object $sessionIdName -like $overlapSessionId
                        $overlapRecordPreviousFile = $resultPreviousFile | Where-Object $sessionIdName -like $overlapSessionId

                        # merge records
                        $overlapRecordPreviousFileMerged = $overlapRecordPreviousFile
                        $overlapRecordPreviousFileMerged.Group = $overlapRecordPreviousFile.Group + $overlapRecordCurrentFile.Group

                        # remove overlapping records from current logfile
                        $resultCurrentFile.RemoveAt( $resultCurrentFile.IndexOf($overlapRecordCurrentFile) )

                        # remove overlapping records from previous logfile
                        $resultPreviousFile.RemoveAt( $resultPreviousFile.IndexOf($overlapRecordPreviousFile) )

                        # add merged record into  previous logfile
                        [void]$resultPreviousFile.Add($overlapRecordPreviousFileMerged)
                    }
                }
            }

            # invoke data transform processing in a runspace to parallize processing and continue to work through files
            $recordCount = $recordCount + $resultPreviousFile.count
            switch ($LogType) {
                {$_ -in @("SMTPReceiveProtocolLog", "SMTPSendProtocolLog")} {
                    $jobObject = Start-RSJob -Batch $batchJobId -Name "$($resultPreviousFile[0].LogFolder)\$($resultPreviousFile[0].LogFileName)" -FunctionsToImport Expand-LogRecordSmtp -Verbose:$false -ScriptBlock {
                        Expand-LogRecordSmtp -InputObject $using:resultPreviousFile -sessionIdName $using:sessionIdName
                    }
                }
                "IMAP4Log" {
                    #Write-PSFMessage -Level Host -Message "$($LogType) currently not supported."
                    $jobObject = Start-RSJob -Batch $batchJobId -Name "$($resultPreviousFile[0].LogFolder)\$($resultPreviousFile[0].LogFileName)" -FunctionsToImport Expand-LogRecordPopImap -Verbose:$false -ScriptBlock {
                        Expand-LogRecordPopImap -InputObject $using:resultPreviousFile -sessionIdName $using:sessionIdName
                    }
                }
                "POP3Log" {
                    #Write-PSFMessage -Level Host -Message "$($LogType) currently not supported."
                    $jobObject = Start-RSJob -Batch $batchJobId -Name "$($resultPreviousFile[0].LogFolder)\$($resultPreviousFile[0].LogFileName)" -FunctionsToImport Expand-LogRecordPopImap -Verbose:$false -ScriptBlock {
                        Expand-LogRecordPopImap -InputObject $using:resultPreviousFile -sessionIdName $using:sessionIdName
                    }
                }
                "MessageTrackingLog" {
                    Write-PSFMessage -Level Host -Message "$($LogType) currently not supported."
                }
                Default {
                    Write-PSFMessage -Level Warning -Message "Unknown LogType: $($LogType) | Probably developers mistake."
                }
            }
            Write-PSFMessage -Level Verbose -Message "Start runspace job '$($jobObject.Name)' (ID:$($jobObject.ID)) for processing $($resultPreviousFile.count) record(s)"

            # put current file records in variable for previous file to check for further record fragments
            $filePrevious = $fileCurrent
            $resultPreviousFile = $resultCurrentFile

            # progress status info & receive completed runspaces
            if (($filecounter % $refreshInterval) -eq 0 -or $filecounter -eq $files.count) {
                Write-PSFMessage -Level System -Message "Procesed $refreshInterval files... Going to update progress status"

                $jobs = Get-RSJob -Batch $batchJobId -ErrorAction SilentlyContinue -Verbose:$false | Sort-Object ID
                $jobsCompleted = $jobs | Where-Object State -Like "Completed"

                # output remaining data in completed runspace
                if ($jobsCompleted) {
                    Wait-JobCompleteWithOutput -Job $jobsCompleted
                    $recordsProcessed = Receive-RSJob -Job $jobsCompleted -Verbose:$false
                    foreach ($recordProcessed in $recordsProcessed) {
                        [void]$recordProcessed.psobject.TypeNames.Remove('Selected.RSJob')
                        $recordProcessed
                    }
                    Write-PSFMessage -Level VeryVerbose -Message "Receiving $($jobsCompleted.Count) completed runspace job(s) with $($recordsProcessed.count) processed records"
                    Remove-RSJob -Job $jobsCompleted -Verbose:$false
                }

                # status update
                Write-Progress -Activity "Import logfiles in $($resultPreviousFile[0].LogFolder) | Currently working runspaces: $($jobs.count - $jobsCompleted.count) | Records in processing: $($recordCount) | Time elapsed: $($traceTimer.Elapsed)" -Status "$($resultPreviousFile[0].LogFileName) ($($filecounter) / $($files.count))" -PercentComplete ($filecounter / $files.count * 100)
            }
            #endregion process
        }

        # processing last remaining file
        switch ($LogType) {
            {$_ -in @("SMTPReceiveProtocolLog", "SMTPSendProtocolLog")} {
                $jobObject = Start-RSJob -Batch $batchJobId -Name "$($resultPreviousFile[0].LogFolder)\$($resultPreviousFile[0].LogFileName)" -FunctionsToImport Expand-LogRecordSmtp -Verbose:$false -ScriptBlock {
                    Expand-LogRecordSmtp -InputObject $using:resultPreviousFile -sessionIdName $using:sessionIdName
                }
            }
            "IMAP4Log" {
                #Write-PSFMessage -Level Host -Message "$($LogType) currently not supported."
                $jobObject = Start-RSJob -Batch $batchJobId -Name "$($resultPreviousFile[0].LogFolder)\$($resultPreviousFile[0].LogFileName)" -FunctionsToImport Expand-LogRecordPopImap -Verbose:$false -ScriptBlock {
                    Expand-LogRecordPopImap -InputObject $using:resultPreviousFile -sessionIdName $using:sessionIdName
                }
            }
            "POP3Log" {
                #Write-PSFMessage -Level Host -Message "$($LogType) currently not supported."
                $jobObject = Start-RSJob -Batch $batchJobId -Name "$($resultPreviousFile[0].LogFolder)\$($resultPreviousFile[0].LogFileName)" -FunctionsToImport Expand-LogRecordPopImap -Verbose:$false -ScriptBlock {
                    Expand-LogRecordPopImap -InputObject $using:resultPreviousFile -sessionIdName $using:sessionIdName
                }
            }
            "MessageTrackingLog" {
                Write-PSFMessage -Level Host -Message "$($LogType) currently not supported."
            }
            Default {
                Write-PSFMessage -Level Warning -Message "Unknown LogType: $($LogType) | Probably developers mistake."
            }
        }

        $recordCount = $recordCount + $resultPreviousFile.count
        Write-PSFMessage -Level Verbose -Message "Start runspace job '$($jobObject.Name)' (ID:$($jobObject.ID)) for processing $($resultPreviousFile.count) record(s)"

        # waiting for completion of all runspaces
        Write-PSFMessage -Level Verbose -Message "Finished processing $($files.Count) file(s) with overall $($recordCount) record(s). Awaiting running runspaces to complete record processing."
        do {
            $jobs = Get-RSJob -Batch $batchJobId -Verbose:$false -ErrorAction SilentlyContinue | Sort-Object ID
            $jobsOpen = $jobs | Where-Object State -NotLike "Completed"
            $jobsCompleted = $jobs | Where-Object State -Like "Completed"

            [string]$_names = $jobsCompleted.Name | Split-Path -Leaf -ErrorAction SilentlyContinue
            if (-not $_names) { $_names = "" }
            Write-PSFMessage -Level VeryVerbose -Message "Awaiting runspaces to complete processing: $($jobsOpen.count)/$($jobs.count) ($([string]::Join(", ", $_names)))"

            Start-Sleep -Milliseconds 200
        } while ($jobsOpen)

        # output remaining data in runspace
        Wait-JobCompleteWithOutput -Job $jobs
        Write-PSFMessage -Level Verbose -Message "All runspaces completed. Gathering results"
        $recordsProcessed = Receive-RSJob -Job $jobs -Verbose:$false
        foreach ($recordProcessed in $recordsProcessed) {
            [void]$recordProcessed.psobject.TypeNames.Remove('Selected.RSJob')
            $recordProcessed
        }
        Remove-RSJob -Batch $batchJobId -Verbose:$false

        $traceTimer.Stop()
        Write-PSFMessage -Level Significant -Message "Duration on parsing $($files.count) file(s) with $($recordCount) records: $($traceTimer.Elapsed)"
    }
}

