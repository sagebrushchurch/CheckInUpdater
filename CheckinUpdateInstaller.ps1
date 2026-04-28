$ProgressPreference = 'SilentlyContinue' # Suppress progress bar for downloads

$url = "https://check-ins.planningcenteronline.com/download/win"
$installerPath = "$env:TEMP\pc-check-ins-setup.exe"
#$localPath = "$env:LOCALAPPDATA\Programs\Check-Ins\Check-Ins.exe" #look locally first (user account)

$userPath = "$env:LOCALAPPDATA\Programs\Check-Ins\Check-Ins.exe"
$systemPath = "C:\Program Files\Check-Ins\Check-Ins.exe" 

$appName = "Check-Ins"

Write-Host $localPath

$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

#goals is to get checkins to live in system wide location

#so now the problem is that Check-Ins can be found at two different paths depending on
#what version is on the device

#Get the current version of Check-Ins on this device - stored in $currentVersion
if (Get-Item $userPath -ErrorAction SilentlyContinue) { #look locally first (user account)
    $currentVersion = (Get-Item $userPath).VersionInfo.FileVersion
} else {
    #look system wide if not found in user account
    if(Get-Item $systemPath -ErrorAction SilentlyContinue) {
        $currentVersion = (Get-Item $systemPath).VersionInfo.FileVersion
    } else {
        $currentVersion = "0.0.0.0" # Force install if not found
    }
}
Write-Host "Current: $currentVersion"

#Find the latest version without downloading the whole file!

$request = Invoke-WebRequest -Uri $url -Method Head -MaximumRedirection 0 -ErrorAction SilentlyContinue -UseBasicParsing
$realUrl = $request.Headers.Location
if ($realUrl -match '(\d+\.\d+\.\d+)') {
    $remoteVersion = [version]$Matches[1]
    Write-Host "Latest version available online: $remoteVersion"
} else {
    Write-Host "Could not detect version from URL. Proceeding to download check."
    $remoteVersion = $null
}

#if remoteVersion is null (couldn't be detected) or remoteVersion is greater than currentVersion, then download and install update
if($null -eq $remoteVersion -or $remoteVersion -gt $currentVersion) {
    #Grab download from the internet only if version is actually newer
    Invoke-WebRequest -Uri $url -OutFile $installerPath -Headers $headers -UseBasicParsing

    $fileSize = (Get-Item $installerPath).Length /1MB
    Write-Host "Download successful! File size is $fileSize MB"

    #close the application if it is running
    $process = Get-Process $appName -ErrorAction SilentlyContinue
    if($process) {
        Stop-Process -Name $appName -Force
        Start-Sleep -Seconds 5
    } else {Write-Host "No need to close check ins because it is not active."}

    #check if Check-Ins is in user accout and if it is, uninstall it before installing new version to system wide location
    if(Test-Path $userPath) {
        #uninstall user version
        Write-Host "Uninstalling user version of Check-Ins..."
        $userUninstaller = Join-Path (Split-Path $userPath) "Uninstall Check-Ins.exe"
        if (Test-Path $userUninstaller) {
            Start-Process -FilePath $userUninstaller -ArgumentList "/S" -Wait
            Start-Sleep -Seconds 2
        }
    }

    #get version of installer we just downloaded
    $installerVersion = (Get-Item $installerPath).VersionInfo.FileVersion
    Write-Host "New version $installerVersion found. Updating..."

    #install update silently
    Start-Process -FilePath $installerPath -ArgumentList "/S", "/AllUsers" -Wait
    #reopen application
    Start-Process -FilePath $systemPath
    
    #Wait for the app to fully load before checking kiosk mode
    Start-Sleep -Seconds 6
    
    # Function to check if the window is in fullscreen/kiosk mode
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class WindowHelper {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
        
        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        
        [DllImport("user32.dll")]
        public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
        
        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
        
        public const int GWL_STYLE = -16;
        public const int WS_BORDER = 0x00800000;
        public const int WS_CAPTION = 0x00C00000;
    }
"@
    
    # Load System.Windows.Forms assembly once
    Add-Type -AssemblyName System.Windows.Forms
    
    # Get the Check-Ins process
    $checkInsProcess = Get-Process $appName -ErrorAction SilentlyContinue
    
    if ($checkInsProcess) {
        # Find the main window of the Check-Ins process
        $mainWindowHandle = $checkInsProcess.MainWindowHandle
        
        if ($mainWindowHandle -ne [IntPtr]::Zero) {
            # Get window rectangle
            $rect = New-Object WindowHelper+RECT
            [WindowHelper]::GetWindowRect($mainWindowHandle, [ref]$rect) | Out-Null
            
            # Get window style to check for borders/caption
            $style = [WindowHelper]::GetWindowLong($mainWindowHandle, [WindowHelper]::GWL_STYLE)
            $hasBorder = ($style -band [WindowHelper]::WS_BORDER) -ne 0
            $hasCaption = ($style -band [WindowHelper]::WS_CAPTION) -ne 0
            
            # Calculate window dimensions
            $windowWidth = $rect.Right - $rect.Left
            $windowHeight = $rect.Bottom - $rect.Top
            
            # Get screen dimensions
            $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            
            # Check if window is fullscreen (covers entire screen and has no border/caption)
            $isFullscreen = ($windowWidth -ge $screen.Width) -and 
                           ($windowHeight -ge $screen.Height) -and
                           ($rect.Left -le 0) -and ($rect.Top -le 0) -and
                           (-not $hasBorder) -and (-not $hasCaption)
            
            if (-not $isFullscreen) {
                Write-Host "Window is not in Kiosk Mode. Activating Kiosk Mode..."
                #Send Ctrl+Alt+Enter to toggle Kiosk Mode
                [System.Windows.Forms.SendKeys]::SendWait("^%{ENTER}")
            } else {
                Write-Host "Window is already in Kiosk Mode. No action needed."
            }
        } else {
            Write-Host "Could not get window handle. Sending Kiosk Mode shortcut anyway..."
            [System.Windows.Forms.SendKeys]::SendWait("^%{ENTER}")
        }
    } else {
        Write-Host "Check-Ins process not found after launch."
    }
}
else {
    Write-Host "Current version $currentVersion is the most up-to-date version."
}