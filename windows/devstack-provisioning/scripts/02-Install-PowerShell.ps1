<#
.SYNOPSIS
    [02] PowerShell 7 — valida; instala via WinGet (Microsoft.PowerShell) SOMENTE se ausente.
.NOTES
    Nunca atualiza nem substitui um pwsh existente. Não remove o Windows PowerShell 5.1.
    Não altera ExecutionPolicy. O WinGet escolhe o instalador (MSIX ou MSI); o MSI pede elevação (UAC).
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'powershell'
$script:CurrentStep = 'PowerShell 7'
$pkg = $ctx.Config.WinGetPackages.PowerShell

function Get-PwshVersion([string]$Exe) {
    return Get-ToolVersionText -FilePath $Exe -ArgumentList @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()')
}

try {
    Write-Info 'Verificando PowerShell 7...'
    Write-Info "Sessão atual: PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    $pwsh = Find-PwshExecutable
    if ($pwsh) {
        $v = Get-PwshVersion $pwsh
        if ($v -and ([version]($v -replace '[^\d\.].*$', '')).Major -ge 7) {
            Write-Ok "PowerShell $v encontrado em $pwsh"
            Write-Info 'Nenhuma alteração necessária.'
            return (New-StepResult -Component 'PowerShell' -Status 'OK' -Message 'Já existente (não alterado)' -Version $v -Path $pwsh)
        }
        Write-Warn "pwsh encontrado em $pwsh, mas versão não identificada/menor que 7 ($v). Não será substituído."
        return (New-StepResult -Component 'PowerShell' -Status 'WARNING' -Message 'pwsh existente com versão inesperada; nada alterado' -Version "$v" -Path $pwsh)
    }

    Write-Info 'PowerShell 7 não encontrado.'
    if (-not (Test-WinGetAvailable)) {
        Write-Fail 'WinGet não disponível. Veja docs\TROUBLESHOOTING.md (WinGet ausente).'
        return (New-StepResult -Component 'PowerShell' -Status 'FAILED' -Message 'WinGet ausente')
    }
    $info = Confirm-WinGetPackage -Id $pkg.Id
    if (-not $info) {
        Write-Fail "Pacote $($pkg.Id) não confirmado via 'winget show'."
        return (New-StepResult -Component 'PowerShell' -Status 'FAILED' -Message "Pacote $($pkg.Id) não confirmado")
    }
    Write-Info "Pacote confirmado: $($info.Id) versão $($info.Version) (fonte winget)"

    if ($DryRun) {
        Write-DryRun "Instalaria PowerShell 7 ($($info.Id) $($info.Version)) via: winget install --id $($info.Id) -e --source winget --no-upgrade"
        Write-DryRun 'O WinGet escolheria o instalador (MSIX ou MSI); o MSI pediria elevação (UAC).'
        return (New-StepResult -Component 'PowerShell' -Status 'SKIPPED' -Message "DRY-RUN: instalaria $($info.Id) $($info.Version)")
    }

    if (-not (Test-IsAdministrator)) {
        Write-Info 'Sessão sem privilégio de administrador: se o WinGet escolher o instalador MSI, o Windows exibirá o UAC.'
    }
    Write-Info "Instalando $($info.Id)..." 'install'
    $res = Install-WinGetPackage -Id $pkg.Id -Scope $pkg.Scope
    Update-SessionPathFromRegistry
    $pwsh = Find-PwshExecutable
    if ($pwsh) {
        $v = Get-PwshVersion $pwsh
        Write-Ok "PowerShell $v instalado em $pwsh" 'install'
        Write-Info 'Windows PowerShell 5.1 permanece instalado e inalterado.'
        Write-Info 'Abra um NOVO terminal para que o pwsh apareça no PATH de outras sessões.'
        return (New-StepResult -Component 'PowerShell' -Status 'OK' -Message 'Instalado' -Version $v -Path $pwsh -Changed $true -RestartRequired $res.RestartRequired)
    }
    Write-Fail "Instalação não confirmada ($($res.Message))."
    return (New-StepResult -Component 'PowerShell' -Status 'FAILED' -Message "winget: $($res.Message)" -RestartRequired $res.RestartRequired)
} catch {
    Write-Fail $_.Exception.Message
    return (New-StepResult -Component 'PowerShell' -Status 'FAILED' -Message $_.Exception.Message)
}
