function Wait-JobCompleteWithOutput {
<#
    .SYNOPSIS
        Waits until job(s) are completed and has delivered the output

    .DESCRIPTION
        Waits until job(s) are completed and has delivered the output

    .PARAMETER Job
        Job(s) to wait for

    .EXAMPLE
        PS C:\> Assert-RSJobCompleteWithOutput -Job $jobs

        Returns true when all jobs are finished
#>
    [CmdletBinding()]
    param (
        $Job
    )

    foreach ($item in $Job) {
        if($item.State -like "Completed" -and $item.HasMoreData -and -not $item.Output.Count) {
            Write-PSFMessage -Level Debug -Message "Runspace job '$($item.name)' is in state '$($item.state)' but did not delivered output data. Waiting for output"
            while (-not $item.Output) {
                # do nothing, check again. tooks usally arround 50-100ms
            }
        }
    }
}
