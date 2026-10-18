# Show a Windows toast notification.
#
# Used to confirm a long-running job finished without watching the terminal.
# Falls back to msg.exe if the WinRT toast API is unavailable.
#
# Usage:
#   powershell -File tool\notify.ps1 -Title "Done" -Message "Pushed to GitHub"

param(
  [Parameter(Mandatory = $true)][string]$Title,
  [Parameter(Mandatory = $true)][string]$Message
)

$ErrorActionPreference = 'Stop'

function Show-Toast {
  param([string]$ToastTitle, [string]$ToastBody)

  try {
    # Load the WinRT projection for the notification APIs.
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null

    $template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
    $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)

    $textNodes = $xml.GetElementsByTagName('text')
    $textNodes.Item(0).AppendChild($xml.CreateTextNode($ToastTitle)) | Out-Null
    $textNodes.Item(1).AppendChild($xml.CreateTextNode($ToastBody)) | Out-Null

    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    # PowerShell has no registered AppUserModelID, so borrow the shell's AUMID.
    # Without this the toast is silently dropped.
    $aumid = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show($toast)
    return $true
  } catch {
    Write-Verbose "toast unavailable: $($_.Exception.Message)"
    return $false
  }
}

if (Show-Toast -ToastTitle $Title -ToastBody $Message) {
  Write-Host "toast shown: $Title"
  exit 0
}

# Fallback: msg.exe writes to every session of the given user.
& "$env:SystemRoot\System32\msg.exe" $env:USERNAME "$Title`n$Message" | Out-Null
Write-Host "toast API unavailable; used msg.exe"
