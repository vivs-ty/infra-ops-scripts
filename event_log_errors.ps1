$logtime = Get-Date -Format yyyyMMddhhmm
$ReportOutput = "C:\Scripts\Test\Logs\event_log_errors_$logtime.html"
$ServerList = Get-Content -Path "C:\Scripts\Test\ServerList.txt"

# Configuration
$HoursBack   = 24       # How many hours back to search
$MaxEvents   = 50       # Max events to pull per server
$EventLogs   = @("System", "Application")
$LevelFilter = @(1, 2)  # 1 = Critical, 2 = Error

$Header = @"
<style>
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse; font-family: Verdana; font-size: 9pt;}
TH    {border-width: 1px; padding: 6px; border-style: solid; border-color: black; background-color: #6495ED; color: white;}
TD    {border-width: 1px; padding: 6px; border-style: solid; border-color: black; vertical-align: top;}
.crit {background-color: #FF6347; color: white;}
.err  {background-color: #FFD700;}
</style>
"@

$TableHeader = @"
<table>
  <tr>
    <th>Server</th>
    <th>Log</th>
    <th>Time</th>
    <th>Level</th>
    <th>Source</th>
    <th>Event ID</th>
    <th>Message</th>
  </tr>
"@

$TableRows = ""
$StartTime = (Get-Date).AddHours(-$HoursBack)

foreach ($ServerName in $ServerList)
{
    $ServerName = $ServerName.ToUpper()
    $Reachable = Test-Path "\\$ServerName\c$\" -ErrorAction SilentlyContinue

    if ($Reachable -eq $true)
    {
        Write-Host "*******------ Connected to $ServerName ------*******"

        try
        {
            $AllEvents = Invoke-Command -ComputerName $ServerName -ErrorAction Stop -ArgumentList $EventLogs, $LevelFilter, $StartTime, $MaxEvents -ScriptBlock {
                param($Logs, $Levels, $Since, $Max)

                $Events = @()
                foreach ($LogName in $Logs)
                {
                    $FilterHash = @{
                        LogName   = $LogName
                        Level     = $Levels
                        StartTime = $Since
                    }
                    try {
                        $Events += Get-WinEvent -FilterHashtable $FilterHash -MaxEvents $Max -ErrorAction SilentlyContinue |
                            Select-Object -Property TimeCreated, LevelDisplayName, ProviderName, Id, Message,
                                @{N='LogName'; E={$LogName}}
                    } catch {}
                }
                $Events | Sort-Object TimeCreated -Descending
            }

            if ($AllEvents.Count -eq 0)
            {
                Write-Host "  No critical/error events found in the last $HoursBack hours."
                $TableRows += @"
  <tr>
    <td>$ServerName</td>
    <td colspan='6'><em>No critical or error events in the last $HoursBack hours.</em></td>
  </tr>
"@
            }
            else
            {
                Write-Host "  Found $($AllEvents.Count) event(s)."
                foreach ($Event in $AllEvents)
                {
                    $CssClass = if ($Event.LevelDisplayName -eq 'Critical') { 'crit' } else { 'err' }
                    $ShortMsg = ($Event.Message -replace '\r?\n', ' ').Substring(0, [Math]::Min(200, $Event.Message.Length)) + "..."
                    $TimeStr  = $Event.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")

                    $TableRows += @"
  <tr class='$CssClass'>
    <td>$ServerName</td>
    <td>$($Event.LogName)</td>
    <td>$TimeStr</td>
    <td>$($Event.LevelDisplayName)</td>
    <td>$($Event.ProviderName)</td>
    <td>$($Event.Id)</td>
    <td>$ShortMsg</td>
  </tr>
"@
                }
            }
        }
        catch
        {
            Write-Host "  ERROR collecting events from $ServerName : $_"
            $TableRows += @"
  <tr class='err'>
    <td>$ServerName</td>
    <td colspan='6'>ERROR: Could not retrieve events — $_</td>
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
    <td colspan='6'>UNREACHABLE</td>
  </tr>
"@
    }
}

$FinalHtml = "<h2>Event Log Errors &amp; Critical — Last $HoursBack Hours</h2>" + $TableHeader + $TableRows + "</table>"

ConvertTo-Html -Head $Header -Body $FinalHtml | Out-File $ReportOutput -Encoding utf8

Write-Host ""
Write-Host "Report saved to: $ReportOutput"

# Send email report
$Subject = "Event Log Error Report | $logtime"
$Smtp    = "smtp.hosting.local"
$To      = "Email <viveshrokzz@yahoo.com>"
$From    = "Event Monitor <noreply@vivesh.net>"
$Body    = Get-Content -Path $ReportOutput | Out-String
Send-MailMessage -SmtpServer $Smtp -To $To -From $From -Subject $Subject -BodyAsHtml $Body
