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
            (Get-ChildItem @options).FullName | Sort-Object | ForEach-Object { $null = $files.Add( $_ ) }
        }
    }

    end {
        $recordCount = 0

        $files = $files | Sort-Object

        $traceTimer = New-Object System.Diagnostics.Stopwatch
        $traceTimer.Start()

        # Import first file
        $filePrevious = $files[0]
        $resultPreviousFile = New-Object -TypeName "System.Collections.ArrayList"
        #$resultPreviousFile = Import-LogData -File $filePrevious
        foreach($record in (Import-LogData -File $filePrevious)) {
            $null = $resultPreviousFile.Add($record)
        }
        $sessionIdName = Resolve-SessionIdName -LogType $resultPreviousFile[0].'Log-type'
        #$resultPreviousFile.count

        # Import remaining files
        $result = New-Object -TypeName "System.Collections.ArrayList"
        $jobList = New-Object -TypeName "System.Collections.ArrayList"
        for ($filecounter = 1; $filecounter -lt $files.Count; $filecounter++) {
            # import next file
            $fileCurrent = $files[$filecounter]
            $resultCurrentFile = New-Object -TypeName "System.Collections.ArrayList"
            foreach($record in (Import-LogData -File $fileCurrent)) {
                $null = $resultCurrentFile.Add($record)
            }
            #$resultCurrentFile = Import-LogData -File $fileCurrent

            if($resultCurrentFile[0].'Log-type' -ne $resultPreviousFile[0].'Log-type') {
                Stop-PSFFunction -Message "Incompatible logfile types ($($resultCurrentFile[0].'Log-type'), $($resultPreviousFile[0].'Log-type')) found! More then one type of logfile in folder '$($pathItem)'."
            }

            # loop through previous and current file to check on fragmented session records in both files (sessions over midnight)
            $overlapSessionIDs = Compare-Object -ReferenceObject $resultPreviousFile -DifferenceObject $resultCurrentFile -Property $sessionIdName -ExcludeDifferent -IncludeEqual
            if($overlapSessionIDs) {
                foreach ($overlapSessionId in $overlapSessionIDs.$sessionIdName) {
                    $overlapRecordCurrentFile = $resultCurrentFile | Where-Object $sessionIdName -like $overlapSessionId
                    $overlapRecordPreviousFile = $resultPreviousFile | Where-Object $sessionIdName -like $overlapSessionId

                    # merge records
                    $overlapRecordPreviousFileMerged = $overlapRecordPreviousFile
                    $overlapRecordPreviousFileMerged.Group = $overlapRecordPreviousFile.Group + $overlapRecordCurrentFile.Group


                    $resultCurrentFile.RemoveAt( $resultCurrentFile.IndexOf($overlapRecordCurrentFile) )

                    $resultPreviousFile.RemoveAt( $resultPreviousFile.IndexOf($overlapRecordPreviousFile) )
                    $resultPreviousFile.Add($overlapRecordPreviousFileMerged)
                }
            }

            # output result
            $recordCount = $recordCount + $resultPreviousFile.count
            $jobObject = Start-RSJob -Name "$($resultPreviousFile[0].LogFolder)\$($resultPreviousFile[0].LogFileName)" -FunctionsToImport Expand-LogRecord -ScriptBlock {
                Expand-LogRecord -InputObject $using:resultPreviousFile -sessionIdName $using:sessionIdName
            }
            $null = $jobList.Add($jobObject)

            # put current file records in variable for previous file to check for further record fragments
            $filePrevious = $fileCurrent
            $resultPreviousFile = $resultCurrentFile

            # progress status info
            if($files.count -lt 100) { $refreshInterval = 1 } else { $refreshInterval = [math]::Round($files.count / 100) }
            if(($filecounter % $refreshInterval) -eq 0) {
                Write-Progress -Activity "Import logfiles in $($resultPreviousFile[0].LogFolder)" -Status "$($resultPreviousFile[0].LogFileName) ($($filecounter) / $($files.count))" -PercentComplete ($filecounter/$files.count*100)

                $jobs = $jobList | Get-RSJob -State Completed -ErrorAction SilentlyContinue | Sort-Object ID
                if($jobs){
                    $jobs | Receive-RSJob | ForEach-Object { $null = $result.Add( $_ ) }
                    foreach ($job in $jobs) {
                        $jobList.RemoveAt( $jobList.IndexOf($job) )
                        $job | Remove-RSJob
                    }
                }
            }
        }
        $recordCount = $recordCount + $filePrevious.count
        do {
            $open = $jobObject | Get-RSJob | Where-Object State -NotLike "Completed"
            Start-Sleep -Milliseconds 100
        } while ($open)

        $jobObject | Get-RSJob | Sort-Object ID | Receive-RSJob | ForEach-Object { $null = $result.Add( $_ ) }
        Expand-LogRecord -InputObject $resultPreviousFile -sessionIdName $sessionIdName | ForEach-Object { $null = $result.Add( $_ ) }
        $jobObject | Get-RSJob | Remove-RSJob

        $result

        $traceTimer.Stop()
        Write-PSFMessage -Level Significant -Message "Duration on parsing $($files.count) file(s) with $($result.count) records: $($traceTimer.Elapsed)"
    }
}

