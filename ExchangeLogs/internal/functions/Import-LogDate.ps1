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
    param (
        $File
    )

    # Get content from logfile
    $File = Get-ChildItem -Path $File -File -ErrorAction Stop
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
    if($sessionIdName) {
        $output = foreach ($group in ($records | Group-Object $sessionIdName)) {
            [PSCustomObject]@{
                "PSTypeName" = "ExchangeLog.$($metadataHash['Log-type'].Replace(' ','')).Record"
                $sessionIdName = $group.Name
                "Group" = $group.Group
            }
        }
    } else {
        $output = foreach ($record in $records) {
            $record.PSOBject.TypeNames.Insert(0, "ExchangeLog.$($metadataHash['Log-type'].Replace(' ','')).Record" )
            $record
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