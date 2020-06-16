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
        [Alias('Directory')]
        [String[]]
        $Path = "C:\Administration\Logs\Exchange\SMTPReceive",

        [switch]
        $Recurse,

        [String]
        $Filter
    )
    begin {
    }

    process {
        $recordCount = 0
        foreach ($pathItem in $Path) {
            # get files from folder
            Write-PSFMessage -Level Verbose -Message "Working in path $pathItem"
            $files = Get-ChildItem -Path $pathItem -Recurse -File

            $traceTimer = New-Object System.Diagnostics.Stopwatch
            $traceTimer.Start()
            # Import first file
            $filePrevious = $files[0]
            $resultPreviousFile = Import-LogData -File $filePrevious.FullName
            $sessionIdName = Resolve-SessionIdName -LogType $resultPreviousFile[0].'Log-type'
            $result = for ($filecounter = 1; $filecounter -lt $files.Count; $filecounter++) {
                # import next file
                $fileCurrent = $files[$filecounter]
                $resultCurrentFile = Import-LogData -File $fileCurrent.FullName

                if($resultCurrentFile[0].'Log-type' -ne $resultPreviousFile[0].'Log-type') {
                    Stop-PSFFunction -Message "Incompatible logfile types ($($resultCurrentFile[0].'Log-type'), $($resultPreviousFile[0].'Log-type')) found! More then one type of logfile in folder '$($pathItem)'."
                }

                # loop through previous and current file to check on fragmented session records in both files (sessions over midnight)
                $resultPreviousFile = foreach($item in $resultPreviousFile) {
                    # find fragmented records from previous and current file
                    $overlaprecord = $resultCurrentFile | Where-Object $sessionIdName -like $item.$sessionIdName
                    if($overlaprecord) {
                        Write-Verbose "Overlapping record found with session id: $($item.$sessionIdName)"
                        $item.Group = $item.Group + $overlaprecord.Group
                    }

                    # remove record fragment from current logfile
                    $resultCurrentFile = $resultCurrentFile | Where-Object $sessionIdName -notin $item.$sessionIdName

                    # output merged record
                    $item
                }

                # output result
                $recordCount = $recordCount + $resultPreviousFile.count
                $resultPreviousFile

                # put current file records in variable for previous file to check for further record fragments
                $filePrevious = $fileCurrent
                $resultPreviousFile = $resultCurrentFile

                # progress status info
                if($files.count -lt 100) { $refreshInterval = 1 } else { $refreshInterval = [math]::Round($files.count / 100) }
                if(($filecounter % $refreshInterval) -eq 0) {
                    Write-Progress -Activity "Parsing logfiles in $($fileCurrent.Directory)" -Status "$($fileCurrent.Name) ($($filecounter) / $($files.count))" -PercentComplete ($filecounter/$files.count*100)
                }
            }
            $recordCount = $recordCount + $filePrevious.count
            $result
            $resultPreviousFile
        }
        $traceTimer.Stop()
        Write-PSFMessage -Level Significant -Message "Duration on parsing $($files.count) file(s): $($traceTimer.Elapsed)"
    }

    end {
    }

}

