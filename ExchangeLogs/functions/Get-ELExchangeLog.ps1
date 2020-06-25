function Get-ELExchangeLog {
<#
    .SYNOPSIS
        Get records from exchange logfiles

    .DESCRIPTION
        Get records from exchange logfiles like SMTP Receive / SMTP Send / IMAP / POP /...
        Files are parsed and grouped by sessions as possible.

    .PARAMETER Path
        The folder to gather logfiles

    .PARAMETER Recursive
        If specified, the path will be gathered recursive

    .PARAMETER Filter
        Filter to be applied for files to parse

    .EXAMPLE
        PS C:\> Get-ELExchangeLog -Path "C:\Logs\SMTPReceive"

        Return records from all files in the folder

    .EXAMPLE
        PS C:\> Get-ELExchangeLog -Path "C:\Logs\SMTPReceive" -Recursive

        Return records from all files in the current and all subfolders.
#>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [String[]]
        $Path = "C:\Administration\Logs\Exchange\SMTPReceive",

        [switch]
        $Recurse,

        [String]
        $Filter
    )

    begin {
        $files = New-Object -TypeName "System.Collections.ArrayList"
        #$cpuCount = ((Get-CimInstance -ClassName win32_processor -Property NumberOfLogicalProcessors).NumberOfLogicalProcessors | Measure-Object -Sum).Sum
    }

    process {
        # get files from folder
        Write-PSFMessage -Level Verbose -Message "Gettings files$( if($Filter){" by filter '$($Filter)'"} ) in path '$path'"
        foreach ($pathItem in $Path) {
            #if( (Get-Item -Path $pathItem).PSIsContainer -and (-not $Recurse)) { continue }
            $options = @{
                "Path" = $pathItem
                "File" = $true
            }
            if ($Recurse) { $options.Add("Recurse", $true) }
            if( $Filter ) { $options.Add("Filter", $Filter) }
            (Get-ChildItem @options).FullName | Sort-Object | ForEach-Object { [void]$files.Add( $_ ) }
        }
    }

    end {
        $recordCount = 0
        $files = $files | Sort-Object
        Write-PSFMessage -Level Verbose -Message "Got $($files.count) file$(if($files.count -gt 1){"s"}) to process."

        $traceTimer = New-Object System.Diagnostics.Stopwatch
        $traceTimer.Start()

        # Import first file
        if($files.Count -gt 1) {
            $filePrevious = $files[0]
        } else {
            $filePrevious = $files
        }
        $resultPreviousFile = New-Object -TypeName "System.Collections.ArrayList"
        foreach($record in (Import-LogData -File $filePrevious)) { [void]$resultPreviousFile.Add($record) }
        $sessionIdName = Resolve-SessionIdName -LogType $resultPreviousFile[0].'Log-type'

        # Import remaining files
        Write-PSFMessage -Level Verbose -Message "Starting import on $($files.Count) remaining file(s)."
        $result = New-Object -TypeName "System.Collections.ArrayList"
        $jobList = New-Object -TypeName "System.Collections.ArrayList"
        for ($filecounter = 1; $filecounter -lt $files.Count; $filecounter++) {
            #region process
            # import next file
            $fileCurrent = $files[$filecounter]
            $resultCurrentFile = New-Object -TypeName "System.Collections.ArrayList"
            foreach($record in (Import-LogData -File $fileCurrent)) { [void]$resultCurrentFile.Add($record) }

            if($resultCurrentFile[0].'Log-type' -ne $resultPreviousFile[0].'Log-type') {
                Stop-PSFFunction -Message "Incompatible logfile types ($($resultCurrentFile[0].'Log-type'), $($resultPreviousFile[0].'Log-type')) found! More then one type of logfile in folder '$($pathItem)'."
            }

            if($sessionIdName) {
                # loop through previous and current file to check on fragmented session records in both files (sessions over midnight)
                Write-PSFMessage -Level VeryVerbose -Message "Checking for overlapping log records on identifier '$($sessionIdName)' in file '$($filePrevious)' and  '$($fileCurrent)'"
                $overlapSessionIDs = Compare-Object -ReferenceObject $resultPreviousFile -DifferenceObject $resultCurrentFile -Property $sessionIdName -ExcludeDifferent -IncludeEqual
                if($overlapSessionIDs) {
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

            # output result
            $recordCount = $recordCount + $resultPreviousFile.count
            $jobObject = Start-RSJob -Name "$($resultPreviousFile[0].LogFolder)\$($resultPreviousFile[0].LogFileName)" -FunctionsToImport Expand-LogRecord -Verbose:$false -ScriptBlock {
                Expand-LogRecord -InputObject $using:resultPreviousFile -sessionIdName $using:sessionIdName
            }
            Write-PSFMessage -Level Verbose -Message "Start runspace job '$($jobObject.Name)' (ID:$($jobObject.ID)) for processing $($resultPreviousFile.count) record(s)"
            [void]$jobList.Add($jobObject)

            # put current file records in variable for previous file to check for further record fragments
            $filePrevious = $fileCurrent
            $resultPreviousFile = $resultCurrentFile

            # progress status info
            if($files.count -lt 100) { $refreshInterval = 1 } else { $refreshInterval = [math]::Round($files.count / 100) }
            if(($filecounter % $refreshInterval) -eq 0) {
                Write-PSFMessage -Level System -Message "Procesed $refreshInterval files... Going to update progress status"
                $jobs = Get-RSJob -State Completed -ErrorAction SilentlyContinue -Verbose:$false | Sort-Object ID
                if($jobs){
                    $recordsProcessed = $jobs | Receive-RSJob -Verbose:$false
                    $recordsProcessed | ForEach-Object {
                        [void]$_.psobject.TypeNames.Remove('Selected.RSJob')
                        $_
                        [void]$result.Add( $_ )
                    }
                    Write-PSFMessage -Level Verbose -Message "Receiving $($jobs.Count) completed runspace job(s) with $($recordsProcessed.count) processed records"
                    foreach ($job in $jobs) {
                        $jobList.RemoveAt( $jobList.IndexOf($job) )
                        $job | Remove-RSJob -Force -Verbose:$false
                    }
                }
                Write-Progress -Activity "Import logfiles in $($resultPreviousFile[0].LogFolder) | Currently working runspaces: $($jobList.count) | Records already processed: $($result.count) | Time elapsed: $($traceTimer.Elapsed)" -Status "$($resultPreviousFile[0].LogFileName) ($($filecounter) / $($files.count))" -PercentComplete ($filecounter/$files.count*100)
            }
            #endregion process
        }
        $recordCount = $recordCount + $resultPreviousFile.count

        # processing last remaining file
        $jobObject = Start-RSJob -Name "$($resultPreviousFile[0].LogFolder)\$($resultPreviousFile[0].LogFileName)" -FunctionsToImport Expand-LogRecord -Verbose:$false -ScriptBlock {
            Expand-LogRecord -InputObject $using:resultPreviousFile -sessionIdName $using:sessionIdName
        }
        Write-PSFMessage -Level Verbose -Message "Start runspace job '$($jobObject.Name)' (ID:$($jobObject.ID)) for processing $($resultPreviousFile.count) record(s)"
        [void]$jobList.Add($jobObject)

        # waiting for completion of all runspaces
        Write-PSFMessage -Level Verbose -Message "Finished processing $($files.Count) file(s) with overall $($recordCount) record(s). Awaiting $($jobList.count) running runspaces to complete record processing."
        do {
            $open = Get-RSJob -Verbose:$false | Where-Object State -NotLike "Completed"
            Start-Sleep -Milliseconds 100
        } while ($open)
        Start-Sleep -Milliseconds 200

        Write-PSFMessage -Level Verbose -Message "All runspaces completed. Gathering results"
        Get-RSJob -Verbose:$false | Sort-Object ID | Receive-RSJob -Verbose:$false | ForEach-Object {
            [void]$_.psobject.TypeNames.Remove('Selected.RSJob')
            $_
            [void]$result.Add( $_ )
        }

        Get-RSJob -Verbose:$false | Remove-RSJob -Verbose:$false

        #$result

        $traceTimer.Stop()
        Write-PSFMessage -Level Significant -Message "Duration on parsing $($files.count) file(s) with $($result.count) records: $($traceTimer.Elapsed)"
    }
}

