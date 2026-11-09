<#
.SYNOPSIS
    [01] Inventário SOMENTE LEITURA do ambiente. Grava JSON em logs\.
.PARAMETER OutputName
    Nome do arquivo JSON em logs\ (ex.: inventory-before.json).
.NOTES
    Não instala, não altera PATH, não altera configurações. Não grava variáveis de ambiente
    além do PATH (que não contém segredos) nem conteúdo de arquivos .env.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$LogFile,
    [string]$OutputName = ('inventory-{0}.json' -f (Get-Date -Format 'yyyy-MM-dd-HHmmss'))
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'inventory'
$script:CurrentStep = 'Inventário'

function Get-ExeInfo {
    param([string]$Name, [string[]]$VersionArgs = @('--version'))
    $paths = @(Get-CommandPaths $Name)
    $items = @()
    foreach ($p in $paths) {
        $items += [ordered]@{ Path = $p; Version = (Get-ToolVersionText -FilePath $p -ArgumentList $VersionArgs) }
    }
    return [ordered]@{ Found = ($paths.Count -gt 0); Default = ($(if ($paths.Count) { $paths[0] } else { $null })); Instances = $items }
}

function Get-InventoryData {
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $displayVersion = $null; $ubr = $null
    if ($cv) {
        if ($cv.PSObject.Properties.Name -contains 'DisplayVersion') { $displayVersion = $cv.DisplayVersion }
        if ($cv.PSObject.Properties.Name -contains 'UBR') { $ubr = $cv.UBR }
    }

    $pwsh = Find-PwshExecutable
    $pyLauncher = Get-FirstCommandPath 'py'
    $pyList = $null
    if ($pyLauncher) { $pyList = (Invoke-NativeCommand -FilePath $pyLauncher -ArgumentList @('-0p') -Quiet).Output }

    $fnm = Get-FirstCommandPath 'fnm'
    $fnmList = $null
    if ($fnm) { $fnmList = (Invoke-NativeCommand -FilePath $fnm -ArgumentList @('list') -Quiet).Output }

    $code = Find-CodeCli
    $codeExt = @()
    if ($code) { $codeExt = @((Invoke-NativeCommand -FilePath $code -ArgumentList @('--list-extensions') -Quiet).Output | Where-Object { $_ }) }

    $ssh = Get-FirstCommandPath 'ssh'
    $sshVer = $null
    if ($ssh) { $sshVer = Get-ToolVersionText -FilePath $ssh -ArgumentList @('-V') }

    $sshCap = 'unknown (requer administrador para consultar)'
    if (Test-IsAdministrator) {
        try { $sshCap = (Get-WindowsCapability -Online -Name 'OpenSSH.Client*' -ErrorAction Stop | Select-Object -First 1).State.ToString() }
        catch { $sshCap = "erro: $($_.Exception.Message)" }
    }

    $winget = Get-FirstCommandPath 'winget'
    $wingetRelevant = @()
    if ($winget) {
        $wl = Invoke-NativeCommand -FilePath $winget -ArgumentList @('list', '--disable-interactivity') -Quiet -Utf8Output
        $wingetRelevant = @($wl.Output | Where-Object { $_ -match 'PowerShell|Git|Python|Node|fnm|nvm|\buv\b|Visual Studio Code|OpenSSH' } | ForEach-Object { ($_ -replace '\s{2,}', ' | ').Trim() })
    }

    $uv = Find-UvExecutable
    $managedPy = $null
    if ($uv) { $managedPy = Find-ManagedPython -UvExe $uv.Path }
    $node26 = Find-Node26

    return [ordered]@{
        Timestamp        = (Get-Date).ToString('o')
        ComputerArch     = $ctx.Arch
        Windows          = [ordered]@{ Caption = $os.Caption; Version = $os.Version; Build = $os.BuildNumber; DisplayVersion = $displayVersion; UBR = $ubr; OSArchitecture = $os.OSArchitecture }
        IsAdministrator  = (Test-IsAdministrator)
        CurrentPowerShell = [ordered]@{ Version = $PSVersionTable.PSVersion.ToString(); Edition = $PSVersionTable.PSEdition }
        PowerShell7      = [ordered]@{ Path = $pwsh; Version = $(if ($pwsh) { Get-ToolVersionText -FilePath $pwsh -ArgumentList @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()') } else { $null }) }
        ExecutionPolicy  = @(Get-ExecutionPolicy -List | ForEach-Object { [ordered]@{ Scope = $_.Scope.ToString(); Policy = $_.ExecutionPolicy.ToString() } })
        WinGet           = [ordered]@{ Path = $winget; Version = $(if ($winget) { Get-ToolVersionText -FilePath $winget } else { $null }); RelevantPackages = $wingetRelevant }
        Git              = Get-ExeInfo 'git'
        Python           = Get-ExeInfo 'python'
        PythonLauncher   = [ordered]@{ Path = $pyLauncher; Version = $(if ($pyLauncher) { Get-ToolVersionText -FilePath $pyLauncher } else { $null }); Installations = $pyList }
        Uv               = [ordered]@{ Path = $(if ($uv) { $uv.Path } else { $null }); Source = $(if ($uv) { $uv.Source } else { $null }); Version = $(if ($uv) { Get-ToolVersionText -FilePath $uv.Path } else { $null }) }
        ManagedPython    = [ordered]@{ Version = $ctx.Config.PythonVersion; Path = $managedPy }
        Node             = Get-ExeInfo 'node'
        Npm              = Get-ExeInfo 'npm.cmd'
        Fnm              = [ordered]@{ Path = $fnm; List = $fnmList }
        Node26Stack      = $(if ($node26) { [ordered]@{ Path = $node26.NodeExe; Version = $node26.Version; Source = $node26.Source } } else { $null })
        VSCode           = [ordered]@{ Cli = $code; Version = $(if ($code) { Get-ToolVersionText -FilePath $code } else { $null }); Extensions = $codeExt }
        OpenSSH          = [ordered]@{ Path = $ssh; Version = $sshVer; Capability = $sshCap }
        PathUser         = @(([Environment]::GetEnvironmentVariable('Path', 'User')) -split ';' | Where-Object { $_ })
        PathMachine      = @(([Environment]::GetEnvironmentVariable('Path', 'Machine')) -split ';' | Where-Object { $_ })
        DevStackRootExists = (Test-Path -LiteralPath $ctx.Paths.StackRoot)
    }
}

try {
    Write-Info 'Coletando inventário (somente leitura)...' 'inventory'
    $data = Get-InventoryData
    $outFile = Join-Path $ctx.Paths.LogDir $OutputName
    $json = ($data | ConvertTo-Json -Depth 8)
    Write-Utf8File -Path $outFile -Content (Protect-DevStackText $json)

    $pyDefault = if ($data.Python.Found) { $data.Python.Default } else { 'não encontrado' }
    $nodeDefault = if ($data.Node.Found) { $data.Node.Default } else { 'não encontrado' }
    Write-Info "Windows: $($data.Windows.Caption) $($data.Windows.DisplayVersion) build $($data.Windows.Build) ($($data.ComputerArch))"
    Write-Info "PowerShell atual: $($data.CurrentPowerShell.Version) | pwsh 7: $(if ($data.PowerShell7.Path) { $data.PowerShell7.Version } else { 'não encontrado' })"
    Write-Info "Python padrão: $pyDefault"
    Write-Info "Node padrão: $nodeDefault"
    Write-Ok "Inventário gravado em $outFile" 'inventory'
    New-StepResult -Component 'Inventário' -Status 'OK' -Message "Gravado em $OutputName" -Path $outFile
} catch {
    Write-Fail "Falha no inventário: $($_.Exception.Message)"
    New-StepResult -Component 'Inventário' -Status 'WARNING' -Message "Inventário incompleto: $($_.Exception.Message)"
}
