#requires -Version 5.1
[CmdletBinding()]
param([string]$WorkspaceRoot = (Join-Path $env:USERPROFILE 'DevExamples'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Some tools write normal version messages to stderr in Windows PowerShell.
$PSNativeCommandUseErrorActionPreference = $false
$script:LogStarted = $false

function Invoke-Checked {
    param([string]$File, [string[]]$Arguments, [int[]]$AllowedCodes = @(0))
    Get-Command $File -ErrorAction Stop | Out-Null
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $File @Arguments 2>&1 | ForEach-Object { Write-Host "$_" }
        $result = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    if ($result -notin $AllowedCodes) { throw "$File failed (exit $result). See output above." }
}

function Add-UserPath {
    param([string[]]$Directories)
    $existing = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($Directories) + @($existing -split ';')
    $seen = @{}
    $unique = @($entries | Where-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { return $false }
        $key = $_.Trim().TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return $false }
        $seen[$key] = $true
        return $true
    })
    [Environment]::SetEnvironmentVariable('Path', ($unique -join ';'), 'User')
    $env:Path = ($Directories -join ';') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + ($unique -join ';')
}

function Write-Json {
    param([string]$Path, $Value)
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Install-PackageId {
    param([string]$Id)
    Write-Host "`nInstalling/checking $Id ..." -ForegroundColor Cyan
    # 0x8A15002B means no applicable upgrade; --no-upgrade preserves existing installs.
    Invoke-Checked 'winget.exe' @('install', '--id', $Id, '--exact', '--source', 'winget', '--silent', '--no-upgrade', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity') @(0, -1978335189)
}

function Find-ExistingFile {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    throw "Cannot find installed tool. Checked: $($Candidates -join ', ')"
}

try {
    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_IDENTIFIER -match 'ARM') {
        throw 'This script supports Windows x64 (Intel/AMD), not ARM64 or 32-bit Windows.'
    }
    if ([Environment]::OSVersion.Version.Build -lt 19041) { throw 'Windows 10 version 2004 or newer is required.' }
    $logDir = Join-Path $PSScriptRoot 'logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logPath = Join-Path $logDir ("setup-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $logPath | Out-Null
    $script:LogStarted = $true
    Write-Host "Log: $logPath"
    Write-Host 'Internet access is required. Accept Windows UAC prompts if shown.'
    Write-Host 'Package/source license agreements will be accepted automatically.'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Host 'Installing WinGet using the official Microsoft PowerShell module...'
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
        Import-Module Microsoft.WinGet.Client
        Repair-WinGetPackageManager -Latest -Force
        $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            throw 'Install/update App Installer from Microsoft Store, then run install.cmd again.'
        }
    }
    Invoke-Checked 'winget.exe' @('--version')
    Install-PackageId 'Microsoft.VisualStudioCode'
    Install-PackageId 'Python.Python.3.13'
    Install-PackageId 'EclipseAdoptium.Temurin.21.JDK'
    Install-PackageId 'MSYS2.MSYS2'

    # Discover custom installation directories from Windows' uninstall records.
    $apps = @(Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue)
    $msysCandidates = @('C:\msys64\usr\bin\bash.exe', "$env:LOCALAPPDATA\msys64\usr\bin\bash.exe")
    $codeCandidates = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd", "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd")
    $jdkCandidates = @()
    foreach ($app in $apps) {
        if (-not $app.PSObject.Properties['DisplayName'] -or -not $app.PSObject.Properties['InstallLocation']) { continue }
        if (-not $app.InstallLocation) { continue }
        if ($app.DisplayName -match 'MSYS2') { $msysCandidates += Join-Path $app.InstallLocation 'usr\bin\bash.exe' }
        if ($app.DisplayName -match 'Microsoft Visual Studio Code') { $codeCandidates += Join-Path $app.InstallLocation 'bin\code.cmd' }
        if ($app.DisplayName -match '(Temurin|Eclipse Adoptium)' -and $app.DisplayName -match '\b21\b' -and $app.DisplayName -match 'JDK') { $jdkCandidates += Join-Path $app.InstallLocation 'bin\javac.exe' }
    }
    $jdkCandidates += @(Get-ChildItem -Path "$env:ProgramFiles\Eclipse Adoptium\jdk-21*\bin\javac.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    $bash = Find-ExistingFile $msysCandidates
    $msysRoot = Split-Path (Split-Path (Split-Path $bash -Parent) -Parent) -Parent
    $code = Find-ExistingFile $codeCandidates
    $javac = Find-ExistingFile $jdkCandidates
    $javaHome = Split-Path (Split-Path $javac -Parent) -Parent
    $pythonCandidates = @("$env:LOCALAPPDATA\Programs\Python\Python313\python.exe", "$env:ProgramFiles\Python313\python.exe")
    foreach ($key in @('HKCU:\Software\Python\PythonCore\3.13\InstallPath', 'HKLM:\Software\Python\PythonCore\3.13\InstallPath')) {
        if (Test-Path $key) { $pythonCandidates += Join-Path (Get-Item $key).GetValue('') 'python.exe' }
    }
    $python = Find-ExistingFile $pythonCandidates

    Write-Host "`nUpdating MSYS2 and installing the C++ toolchain..." -ForegroundColor Cyan
    $env:MSYSTEM = 'UCRT64'
    $env:CHERE_INVOKING = '1'
    # Core updates can close the shell. Run pacman directly and use a new shell afterwards.
    Invoke-Checked $bash @('-lc', 'true')
    Invoke-Checked (Join-Path $msysRoot 'usr\bin\pacman.exe') @('-Syu', '--noconfirm')
    Invoke-Checked $bash @('-lc', 'pacman -Syu --noconfirm')
    Invoke-Checked $bash @('-lc', 'pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-gdb mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja')
    $cppBin = Join-Path $msysRoot 'ucrt64\bin'
    $gpp = Find-ExistingFile @( (Join-Path $cppBin 'g++.exe') )
    $gdb = Find-ExistingFile @( (Join-Path $cppBin 'gdb.exe') )
    [Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome, 'User')
    $env:JAVA_HOME = $javaHome
    Add-UserPath @($cppBin, (Join-Path $javaHome 'bin'), (Split-Path $python -Parent), (Join-Path (Split-Path $python -Parent) 'Scripts'), (Split-Path $code -Parent))

    foreach ($extension in @('ms-vscode.cpptools', 'ms-vscode.cmake-tools', 'ms-python.python', 'ms-python.vscode-pylance', 'ms-python.debugpy', 'vscjava.vscode-java-pack')) {
        Invoke-Checked $code @('--install-extension', $extension)
    }

    # Each run creates a new directory so personal examples/configuration are never overwritten.
    $project = Join-Path $WorkspaceRoot ("hello-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    foreach ($folder in @('cpp', 'python', 'java')) { New-Item -ItemType Directory -Path (Join-Path $project "$folder\.vscode") -Force | Out-Null }
    $cpp = Join-Path $project 'cpp'
    $py = Join-Path $project 'python'
    $java = Join-Path $project 'java'
    @'
#include <iostream>
int main() {
    std::cout << "Hello, C++!" << std::endl;
    return 0;
}
'@ | Set-Content -LiteralPath (Join-Path $cpp 'main.cpp') -Encoding ASCII
    'print("Hello, Python!")' | Set-Content -LiteralPath (Join-Path $py 'main.py') -Encoding ASCII
    @'
public class Main {
    public static void main(String[] args) {
        System.out.println("Hello, Java!");
    }
}
'@ | Set-Content -LiteralPath (Join-Path $java 'Main.java') -Encoding ASCII
    Invoke-Checked $python @('-m', 'venv', (Join-Path $py '.venv'))
    $venvPython = Join-Path $py '.venv\Scripts\python.exe'
    Invoke-Checked $venvPython @('-m', 'pip', '--version')

    Write-Json (Join-Path $cpp '.vscode\settings.json') @{'C_Cpp.default.compilerPath' = $gpp; 'C_Cpp.default.cppStandard' = 'c++17'; 'C_Cpp.default.intelliSenseMode' = 'windows-gcc-x64'}
    Write-Json (Join-Path $cpp '.vscode\tasks.json') @{version='2.0.0'; tasks=@(@{label='Build C++'; type='process'; command=$gpp; args=@('-g', '-std=c++17', '${workspaceFolder}/main.cpp', '-o', '${workspaceFolder}/main.exe'); options=@{cwd='${workspaceFolder}'}; problemMatcher=@('$gcc'); group=@{kind='build'; isDefault=$true}})}
    Write-Json (Join-Path $cpp '.vscode\launch.json') @{version='0.2.0'; configurations=@(@{name='Debug C++'; type='cppdbg'; request='launch'; program='${workspaceFolder}/main.exe'; cwd='${workspaceFolder}'; args=@(); stopAtEntry=$false; externalConsole=$false; MIMode='gdb'; miDebuggerPath=$gdb; preLaunchTask='Build C++'; environment=@(@{name='PATH'; value=($cppBin + ';${env:PATH}')})})}
    Write-Json (Join-Path $py '.vscode\settings.json') @{'python.defaultInterpreterPath'=$venvPython}
    Write-Json (Join-Path $py '.vscode\launch.json') @{version='0.2.0'; configurations=@(@{name='Debug Python'; type='debugpy'; request='launch'; program='${workspaceFolder}/main.py'; python=$venvPython; console='integratedTerminal'})}
    Write-Json (Join-Path $java '.vscode\settings.json') @{'java.jdt.ls.java.home'=$javaHome; 'java.configuration.runtimes'=@(@{name='JavaSE-21'; path=$javaHome; default=$true})}
    Write-Json (Join-Path $java '.vscode\launch.json') @{version='0.2.0'; configurations=@(@{name='Debug Java'; type='java'; request='launch'; mainClass='Main'})}
    $workspace = Join-Path $project 'DevExamples.code-workspace'
    Write-Json $workspace @{folders=@(@{path='cpp'}, @{path='python'}, @{path='java'}); settings=@{'terminal.integrated.env.windows'=@{PATH=($cppBin + ';' + (Join-Path $javaHome 'bin') + ';' + (Split-Path $python -Parent) + ';${env:PATH}'); JAVA_HOME=$javaHome}}}

    Write-Host "`nVerifying all three languages..." -ForegroundColor Cyan
    Invoke-Checked $gpp @('--version')
    Invoke-Checked $gdb @('--version')
    Invoke-Checked $gpp @('-g', '-std=c++17', (Join-Path $cpp 'main.cpp'), '-o', (Join-Path $cpp 'main.exe'))
    Invoke-Checked (Join-Path $cpp 'main.exe') @()
    Invoke-Checked $venvPython @((Join-Path $py 'main.py'))
    Invoke-Checked $javac @('-encoding', 'UTF-8', (Join-Path $java 'Main.java'))
    Invoke-Checked (Join-Path $javaHome 'bin\java.exe') @('-cp', $java, 'Main')
    Write-Host "`nSUCCESS. Workspace: $workspace" -ForegroundColor Green
    Write-Host 'Restart existing VS Code/terminal windows to refresh environment variables.'
    Write-Host 'Open the workspace and press F5 in main.cpp, main.py or Main.java.'
    Invoke-Checked $code @('--new-window', $workspace)
} catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($script:LogStarted) { Write-Host "Log: $logPath" }
    Write-Host 'Fix the reported error and run install.cmd again. Installed packages are retained.'
    exit 1
} finally {
    if ($script:LogStarted) { Stop-Transcript | Out-Null }
}
