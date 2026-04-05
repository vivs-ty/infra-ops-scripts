$logtime = Get-Date -Format yyyyMMddhhmm
$ReportOutput = "C:\Scripts\Test\Logs\windows_update_status_$logtime.html"
$ServerList = Get-Content -Path "C:\Scripts\Test\ServerList.txt"

$Header = @"
<style>
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse; font-family: Verdana; font-size: 10pt;}
TH    {border-width: 1px; padding: 6px; border-style: solid; border-color: black; background-color: #6495ED; color: white;}
TD    {border-width: 1px; padding: 6px; border-style: solid; border-color: black;}
.warn {background-color: #FFD700;}
.crit {background-color: #FF6347; color: white;}
.ok   {background-color: #90EE90;}
</style>
"@

$TableHeader = @"
<table>
  <tr>
    <th>Server</th>
    <th>Pending Updates</th>
    <th>Critical</th>
    <th>Important</th>
    <th>Optional</th>
    <th>Reboot Required</th>
    <th>Last Update Check</th>
    <th>Update Source</th>
    <th>Status</th>
  </tr>
"@

$TableRows = ""

foreach ($ServerName in $ServerList)
{
    $ServerName = $ServerName.ToUpper()
    $Reachable = Test-Path "\\$ServerName\c$\" -ErrorAction SilentlyContinue

    if ($Reachable -eq $true)
    {
        Write-Host "*******------ Connected to $ServerName ------*******"

        try
        {
            $Data = Invoke-Command -ComputerName $ServerName -ErrorAction Stop -ScriptBlock {

                # Detect whether this machine is configured to use a WSUS server
                $WsusAuKey   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
                $UsesWsus    = (Get-ItemProperty -Path $WsusAuKey -Name UseWUServer -ErrorAction SilentlyContinue).UseWUServer -eq 1
                $UpdateSource = if ($UsesWsus) { "WSUS" } else { "Windows Update" }

                # ServiceID for the public Windows Update service (used as fallback when WSUS fails)
                $WU_SERVICE_ID = "9482f4b4-e343-43b6-b170-9a65bc822c77"

                $SearchResult  = $null
                $SearchError   = $null

                try {
                    $UpdateSession  = New-Object -ComObject Microsoft.Update.Session
                    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()

                    # On WSUS machines, attempt the search against the managed (WSUS) server first.
                    # ServerSelection values: 1 = ssDefault, 2 = ssManagedServer (WSUS), 3 = ssWindowsUpdate, 4 = ssOthers
                    if ($UsesWsus) {
                        $UpdateSearcher.ServerSelection = 2   # ssManagedServer (WSUS)
                    }

                    $SearchResult = $UpdateSearcher.Search("IsInstalled=0 and Type='Software'")
                }
                catch {
                    $SearchError = "Primary search failed ($UpdateSource): $($_.Exception.Message)"

                    # Fallback: query the public Windows Update service directly, bypassing WSUS
                    try {
                        $UpdateSession  = New-Object -ComObject Microsoft.Update.Session
                        $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
                        $UpdateSearcher.ServerSelection = 3   # ssOthers
                        $UpdateSearcher.ServiceID       = $WU_SERVICE_ID
                        $SearchResult  = $UpdateSearcher.Search("IsInstalled=0 and Type='Software'")
                        $UpdateSource  = "Windows Update (WSUS fallback)"
                    }
                    catch {
                        throw "WUA query failed on both WSUS and Windows Update fallback. Primary error: $SearchError. Fallback error: $($_.Exception.Message)"
                    }
                }

                $PendingTotal = $SearchResult.Updates.Count
                $Critical     = ($SearchResult.Updates | Where-Object { $_.MsrcSeverity -eq 'Critical' }).Count
                $Important    = ($SearchResult.Updates | Where-Object { $_.MsrcSeverity -eq 'Important' }).Count
                $Optional     = $PendingTotal - $Critical - $Important

                # Check reboot pending
                $RebootRequired = $false
                $WuRebootKey  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
                $CbsRebootKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
                if ((Test-Path $WuRebootKey) -or (Test-Path $CbsRebootKey)) {
                    $RebootRequired = $true
                }

                # Last update check time
                $LastCheck = $UpdateSearcher.GetTotalHistoryCount()
                $LastCheckTime = if ($LastCheck -gt 0) {
                    $UpdateSearcher.QueryHistory(0, 1)[0].Date.ToString("yyyy-MM-dd HH:mm")
                } else { "Unknown" }

                [PSCustomObject]@{
                    PendingTotal    = $PendingTotal
                    Critical        = $Critical
                    Important       = $Important
                    Optional        = $Optional
                    RebootRequired  = $RebootRequired
                    LastCheckTime   = $LastCheckTime
                    UpdateSource    = $UpdateSource
                }
            }

            $Status   = "OK"
            $CssClass = "ok"
            if ($Data.Critical -gt 0 -or $Data.RebootRequired) {
                $Status   = "CRITICAL"
                $CssClass = "crit"
            } elseif ($Data.PendingTotal -gt 0) {
                $Status   = "WARNING"
                $CssClass = "warn"
            }

            Write-Host "  Pending: $($Data.PendingTotal)  Critical: $($Data.Critical)  Reboot: $($Data.RebootRequired)  [$Status]"

            $TableRows += @"
  <tr class='$CssClass'>
    <td>$ServerName</td>
    <td>$($Data.PendingTotal)</td>
    <td>$($Data.Critical)</td>
    <td>$($Data.Important)</td>
    <td>$($Data.Optional)</td>
    <td>$($Data.RebootRequired)</td>
    <td>$($Data.LastCheckTime)</td>
    <td>$($Data.UpdateSource)</td>
    <td>$Status</td>
  </tr>
"@
        }
        catch
        {
            Write-Host "  ERROR collecting data from $ServerName : $_"
            $TableRows += @"
  <tr class='warn'>
    <td>$ServerName</td>
    <td colspan='7'>ERROR: Could not retrieve data — $_</td>
  </tr>
"@
        }
    }
    else
    {
        Write-Host "*******------ Unable to Connect $ServerName ------*******"
        $TableRows += @"
  <tr class='crit'>
    <td>$ServerName</td>
    <td colspan='7'>UNREACHABLE</td>
  </tr>
"@
    }
}

$FinalHtml = $TableHeader + $TableRows + "</table>"

ConvertTo-Html -Head $Header -Body $FinalHtml | Out-File $ReportOutput -Encoding utf8

Write-Host ""
Write-Host "Report saved to: $ReportOutput"

# Send email report
$Subject = "Windows Update Status Report | $logtime"
$Smtp    = "smtp.hosting.local"
$To      = "Email <viveshrokzz@yahoo.com>"
$From    = "Update Monitor <noreply@vivesh.net>"
$Body    = Get-Content -Path $ReportOutput | Out-String
Send-MailMessage -SmtpServer $Smtp -To $To -From $From -Subject $Subject -BodyAsHtml $Body
