function Import-LogData {
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
    [OutputType([System.Collections.ArrayList])]
    param (
        $File
    )

    # Get content from logfile
    $File = Get-Item -Path $File -ErrorAction Stop
    Write-PSFMessage -Level Verbose -Message  "Get content from logfile: $($File.Fullname)"
    $content = $File | Get-Content

    # split metadata and logcontent (first lines fo logfile)
    $metadata = $content -match '^#.*' | Select-Object -First 7 -Unique
    $header = $metadata[-1].split(": ")[-1]
    $logcontent = $content -match '^\d.*'

    # query meta data informations into hashtable
    $metadataHash = [ordered]@{}
    foreach ($metadatarecord in ($metadata[0 .. ($metadata.Count - 2)])) {
        $_data = $metadatarecord.TrimStart("#") -Split ': '
        $metadataHash.Add($_data[0], $_data[1])
    }
    Write-PSFMessage -Level VeryVerbose -Message "Detect $($metadataHash['Log-type'])"

    # convert filecontent to csv data and group records if know/supportet logfile type
    $records = $logcontent | ConvertFrom-Csv -Delimiter "," -Header $header.Split(",")
    $sessionIdName = Resolve-SessionIdName -LogType $metadataHash['Log-type']
    $output = New-Object -TypeName "System.Collections.ArrayList"
    if ($sessionIdName) {
        Write-PSFMessage -Level VeryVerbose -Message "Going to group records by $($sessionIdName) from file '$($File.Fullname)'"
        foreach ($group in ($records | Group-Object $sessionIdName)) {
            $null = $output.Add(
                [PSCustomObject]@{
                    "PSTypeName"   = "ExchangeLog.$($metadataHash['Log-type'].Replace(' ','')).Group"
                    $sessionIdName = $group.Name
                    "Group"        = $group.Group
                    "Log-type"     = $metadataHash["Log-type"]
                    "metadataHash" = $metadataHash
                    "LogFileName"  = $File.Name
                    "LogFolder"    = $File.Directory
                }
            )
        }
    } else {
        foreach ($record in $records) {
            $record.PSOBject.TypeNames.Insert(0, "ExchangeLog.$($metadataHash['Log-type'].Replace(' ','')).Record" )
            $null = $output.Add( $record )
        }

        # add metadata info to record groups
        foreach ($key in $metadataHash.Keys) {
            $output | Add-Member -MemberType NoteProperty -Name $key -Value $metadataHash[$key] -Force
        }
        $output | Add-Member -MemberType NoteProperty -Name "LogFileName" -Value $File.Name -Force
        $output | Add-Member -MemberType NoteProperty -Name "LogFolder" -Value $File.Directory -Force
    }


    Write-PSFMessage -Level VeryVerbose -Message "Finished processing $($output.count) records from file '$($File.Name)'"

    # output data to the pipeline
    $output
}