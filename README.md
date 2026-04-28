Planning Center Check-Ins: Auto-Updater & Migrator
This project provides a robust solution for managing Planning Center Check-Ins installations on Windows. It automates the process of checking for updates, migrating "User-level" installs to "System-wide" installs, and scheduling these checks to run automatically every day.

🚀 Key Features
Version Detection: Smartly identifies the current version by checking both User (AppData) and System (Program Files) paths.

User-to-System Migration: Automatically detects if Check-Ins is installed in a user's local profile and migrates it to a System-wide location (C:\Program Files) for consistency across all user accounts.

Silent Updates: Downloads and installs the latest version from Planning Center servers without user intervention or pop-up prompts.

Automated Scheduling: Includes a batch script to set up a Windows Scheduled Task, ensuring the app stays updated without manual effort.

📂 File Overview
1. CheckinUpdateInstaller.ps1
The core PowerShell script that handles the logic.

Checks if the local version is older than the latest online version.

Closes the application if it is currently running.

Uninstalls existing "User-level" versions to prevent duplicate installs.

Forces a System-wide installation using the /AllUsers flag.

Restarts the application from the new System path after a successful update.

Automatically ensures Kiosk Mode (full-screen) is enabled by detecting the current window state and only toggling if needed.

2. CheckinUpdateTaskCreator.bat
A helper utility to automate the deployment of the updater.

Creates a Windows Scheduled Task named CheckInUpdater.

Schedules the update to run daily at 5:00 AM.

Configures the task to run with Highest Privileges (Admin rights) and includes a 5-minute timeout to ensure the process doesn't hang.

🛠 Installation & Setup
Prerequisites
Windows 10/11

Administrator Privileges (Required to write to C:\Program Files and create Scheduled Tasks).

Setup Instructions
Download both CheckinUpdateInstaller.ps1 and CheckinUpdateTaskCreator.bat to the same folder on your computer (e.g., C:\Scripts\CheckIns).

Right-click CheckinUpdateTaskCreator.bat and select Run as Administrator.

The console will confirm: Task created successfully!.

⚙️ How It Works (Technical Logic)
The script follows a specific hierarchy to ensure the app is always in the right place:

Locate App: It looks for Check-Ins.exe in $env:LOCALAPPDATA. If found, it marks it for migration.

Compare: It performs a HEAD request to Planning Center's download URL to find the latest version number without downloading the full installer first.

Clean Up: If a User-level install is found, it runs the uninstaller silently (/S) before proceeding.

Install: It runs the new installer with the /S and /AllUsers arguments, which forces the software into C:\Program Files\Check-Ins.

📝 Troubleshooting
Script won't run: Ensure your PowerShell Execution Policy allows scripts. You can set this by running Set-ExecutionPolicy RemoteSigned in an Admin PowerShell window.

Installer Pop-ups: If you see a prompt asking for an installation path, ensure you are running the script as an Administrator. The /AllUsers flag requires elevated permissions to skip that prompt.

Task Not Running: Open Task Scheduler and look for CheckInUpdater to verify the "Last Run Result" or to trigger the task manually for testing.