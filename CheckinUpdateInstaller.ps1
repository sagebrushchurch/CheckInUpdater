$ProgressPreference = 'SilentlyContinue' # Suppress progress bar for downloads

$url = "https://check-ins.planningcenteronline.com/download/win"
$installerPath = "$env:TEMP\pc-check-ins-setup.exe"
#$localPath = "$env:LOCALAPPDATA\Programs\Check-Ins\Check-Ins.exe" #look locally first (user account)

$userPath = "$env:LOCALAPPDATA\Programs\Check-Ins\Check-Ins.exe"
$systemPath = "C:\Program Files\Check-Ins\Check-Ins.exe" 

$appName = "Check-Ins"

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
    
    # Function to check if the window is in fullscreen/kiosk mode and bring it to foreground
    # Only add the type if it doesn't already exist (prevents errors on re-run)
    if (-not ([System.Management.Automation.PSTypeName]'WindowHelper').Type) {
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
            
            [DllImport("user32.dll")]
            public static extern bool SetForegroundWindow(IntPtr hWnd);
            
            public struct RECT {
                public int Left;
                public int Top;
                public int Right;
                public int Bottom;
            }
            
            public const int GWL_STYLE = -16;
            public const int WS_CAPTION = 0x00C00000;
        }
"@
    }
    
    # Load System.Windows.Forms assembly once
    Add-Type -AssemblyName System.Windows.Forms
    
    try {
        # Get the Check-Ins process (select first if multiple exist)
        $checkInsProcess = Get-Process $appName -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($checkInsProcess) {
            # Give the window a moment to stabilize
            Start-Sleep -Milliseconds 500
            
            # Find the main window of the Check-Ins process
            $mainWindowHandle = $checkInsProcess.MainWindowHandle
            
            if ($mainWindowHandle -ne [IntPtr]::Zero) {
                # Get window rectangle
                $rect = New-Object WindowHelper+RECT
                $rectResult = [WindowHelper]::GetWindowRect($mainWindowHandle, [ref]$rect)
                
                if ($rectResult) {
                    # Get window style to check for title bar (WS_CAPTION includes WS_BORDER)
                    $style = [WindowHelper]::GetWindowLong($mainWindowHandle, [WindowHelper]::GWL_STYLE)
                    
                    # WS_CAPTION (0x00C00000) is present when the window has a title bar
                    # In kiosk/fullscreen mode, this style bit should NOT be set
                    $hasCaption = ($style -band [WindowHelper]::WS_CAPTION) -ne 0
                    
                    # Calculate window dimensions
                    $windowWidth = $rect.Right - $rect.Left
                    $windowHeight = $rect.Bottom - $rect.Top
                    
                    # Get screen dimensions
                    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                    
                    Write-Host "Window dimensions: $windowWidth x $windowHeight"
                    Write-Host "Screen dimensions: $($screen.Width) x $($screen.Height)"
                    Write-Host "Window has caption/title bar: $hasCaption"
                    Write-Host "Window style: 0x$($style.ToString('X8'))"
                    
                    # A window is in Kiosk Mode if it has no caption/title bar
                    # The size check is less reliable as windows can be maximized without being in kiosk mode
                    $isKioskMode = -not $hasCaption
                    
                    if (-not $isKioskMode) {
                        Write-Host "Window is not in Kiosk Mode. Activating Kiosk Mode..."
                        
                        # Bring the window to foreground before sending keys
                        [WindowHelper]::SetForegroundWindow($mainWindowHandle) | Out-Null
                        Start-Sleep -Milliseconds 300
                        
                        # Send Ctrl+Alt+Enter to toggle Kiosk Mode
                        # SendKeys syntax: ^ = Ctrl, % = Alt, {ENTER} = Enter key
                        [System.Windows.Forms.SendKeys]::SendWait("^%{ENTER}")
                        Write-Host "Kiosk Mode shortcut sent."
                    } else {
                        Write-Host "Window is already in Kiosk Mode. No action needed."
                    }
                } else {
                    Write-Host "Could not get window rectangle. Skipping kiosk mode check."
                }
            } else {
                Write-Host "Could not get window handle. The window may not be fully initialized yet."
            }
        } else {
            Write-Host "Check-Ins process not found after launch."
        }
    } catch {
        Write-Host "Error checking kiosk mode: $($_.Exception.Message)"
        Write-Host "Skipping kiosk mode activation to avoid issues."
    }
}
else {
    Write-Host "Current version $currentVersion is the most up-to-date version."
}

# Exit the script to close the PowerShell window
exit 0