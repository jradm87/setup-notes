<#
.SYNOPSIS
    [01b] WinGet — valida; instala SOMENTE se ausente E necessário (PowerShell 7, Git ou VS Code faltando).
.NOTES
    Método oficial: provedor NuGet + módulo Microsoft.WinGet.Client + Repair-WinGetPackageManager.
    Tudo no escopo do usuário, sem elevação. Um WinGet existente nunca é atualizado.
    Não marca o PSGallery como confiável: -Force em Install-Module só evita a pergunta nesta execução.
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'winget'
$script:CurrentStep = 'WinGet'

$moduleName = 'Microsoft.WinGet.Client'
$minNuGet = [version]'2.8.5.201'
$windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'

$prevProgress = $ProgressPreference
$prevProtocol = [Net.ServicePointManager]::SecurityProtocol

try {
    Write-Info 'Verificando WinGet...'
    $winget = Get-FirstCommandPath 'winget'
    if ($winget) {
        $v = Get-ToolVersionText -FilePath $winget
        if ($v) {
            Write-Ok "WinGet $v encontrado em $winget"
            Write-Info 'Nenhuma instalação necessária.'
            return (New-StepResult -Component 'WinGet' -Status 'OK' -Message 'Já existente (não alterado)' -Version $v -Path $winget)
        }
        Write-Warn "winget encontrado em $winget, mas não respondeu. Nada será alterado. Veja docs\TROUBLESHOOTING.md."
        return (New-StepResult -Component 'WinGet' -Status 'WARNING' -Message 'winget existente não respondeu' -Path $winget)
    }

    Write-Info 'WinGet não encontrado.'
    $needs = @()
    if (-not (Find-PwshExecutable)) { $needs += 'PowerShell 7' }
    if (-not (Find-GitExecutable)) { $needs += 'Git' }
    if (-not (Find-CodeCli)) { $needs += 'VS Code' }
    if ($needs.Count -eq 0) {
        Write-Info 'PowerShell 7, Git e VS Code já existem: o WinGet não é necessário.'
        return (New-StepResult -Component 'WinGet' -Status 'SKIPPED' -Message 'Ausente, mas não necessário')
    }
    Write-Info "Necessário para instalar: $($needs -join ', ')"

    if ($DryRun) {
        Write-DryRun 'Instalaria, se ausente, o provedor NuGet (escopo usuário) e registraria o PSGallery padrão.'
        Write-DryRun "Instalaria o módulo $moduleName do PSGallery (escopo usuário)."
        Write-DryRun 'Executaria Repair-WinGetPackageManager (usuário atual, sem elevação).'
        return (New-StepResult -Component 'WinGet' -Status 'SKIPPED' -Message 'DRY-RUN: instalaria o WinGet')
    }

    $ProgressPreference = 'SilentlyContinue'
    # Windows PowerShell 5.1 em sistemas antigos pode não oferecer TLS 1.2. Vale só para esta etapa.
    if ($prevProtocol -ne [Net.SecurityProtocolType]::SystemDefault) {
        [Net.ServicePointManager]::SecurityProtocol = $prevProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    $nuget = @(Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge $minNuGet })
    if ($nuget.Count -eq 0) {
        Write-Info 'Instalando o provedor NuGet (escopo usuário)...' 'install'
        Install-PackageProvider -Name NuGet -MinimumVersion $minNuGet -Scope CurrentUser -Force | Out-Null
    } else {
        Write-Info 'Provedor NuGet já existe.'
    }

    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
        Write-Info 'Registrando o repositório padrão PSGallery...' 'install'
        Register-PSRepository -Default
    }

    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        Write-Info "Instalando o módulo $moduleName (escopo usuário)..." 'install'
        Install-Module -Name $moduleName -Repository PSGallery -Scope CurrentUser -Force
    } else {
        Write-Info "Módulo $moduleName já existe."
    }

    Import-Module -Name $moduleName
    Write-Info 'Instalando o WinGet (Repair-WinGetPackageManager)...' 'install'
    $repair = Repair-WinGetPackageManager
    Write-DevLog -Level INFO -Step 'WinGet' -Action 'repair' -Message "$repair"

    Update-SessionPathFromRegistry
    if ((Test-Path -LiteralPath $windowsApps) -and (@($env:Path -split ';') -notcontains $windowsApps)) {
        $env:Path = $env:Path.TrimEnd(';') + ';' + $windowsApps
    }

    $winget = Get-FirstCommandPath 'winget'
    $v = if ($winget) { Get-ToolVersionText -FilePath $winget } else { $null }
    if ($v) {
        Write-Ok "WinGet $v instalado em $winget" 'install'
        return (New-StepResult -Component 'WinGet' -Status 'OK' -Message 'Instalado' -Version $v -Path $winget -Changed $true)
    }
    Write-Fail 'Instalação não confirmada: winget não respondeu. Veja docs\TROUBLESHOOTING.md (WinGet ausente).'
    return (New-StepResult -Component 'WinGet' -Status 'FAILED' -Message 'Instalação não confirmada')
} catch {
    Write-Fail $_.Exception.Message
    return (New-StepResult -Component 'WinGet' -Status 'FAILED' -Message $_.Exception.Message)
} finally {
    $ProgressPreference = $prevProgress
    [Net.ServicePointManager]::SecurityProtocol = $prevProtocol
}
