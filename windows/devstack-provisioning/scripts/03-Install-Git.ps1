<#
.SYNOPSIS
    [03] Git for Windows — valida; instala via WinGet (Git.Git) SOMENTE se ausente.
.NOTES
    Nunca atualiza/reinstala. Não configura user.name, user.email, remotes, SSH,
    GitHub/GitLab nem credential helper.
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'git'
$script:CurrentStep = 'Git'
$pkg = $ctx.Config.WinGetPackages.Git

try {
    Write-Info 'Verificando Git...'
    $git = Find-GitExecutable
    if ($git) {
        $v = Get-ToolVersionText -FilePath $git
        if ($v) {
            Write-Ok "$v encontrado em $git"
            Write-Info 'Nenhuma instalação necessária.'
            return (New-StepResult -Component 'Git' -Status 'OK' -Message 'Já existente (não alterado)' -Version $v -Path $git)
        }
        Write-Warn "git encontrado em $git, mas 'git --version' falhou. Nada será alterado."
        return (New-StepResult -Component 'Git' -Status 'WARNING' -Message 'git existente não respondeu' -Path $git)
    }

    Write-Info 'Git não encontrado.'
    if (-not (Test-WinGetAvailable)) {
        Write-Fail 'WinGet não disponível.'
        return (New-StepResult -Component 'Git' -Status 'FAILED' -Message 'WinGet ausente')
    }
    $info = Confirm-WinGetPackage -Id $pkg.Id
    if (-not $info) { return (New-StepResult -Component 'Git' -Status 'FAILED' -Message "Pacote $($pkg.Id) não confirmado") }
    Write-Info "Pacote confirmado: $($info.Id) versão $($info.Version)"

    if ($DryRun) {
        Write-DryRun "Instalaria Git ($($info.Id) $($info.Version)) via winget --no-upgrade. Nenhuma configuração do Git seria feita."
        return (New-StepResult -Component 'Git' -Status 'SKIPPED' -Message "DRY-RUN: instalaria $($info.Id) $($info.Version)")
    }

    Write-Info "Instalando $($info.Id)..." 'install'
    $res = Install-WinGetPackage -Id $pkg.Id -Scope $pkg.Scope
    Update-SessionPathFromRegistry
    $git = Find-GitExecutable
    if ($git) {
        $v = Get-ToolVersionText -FilePath $git
        Write-Ok "$v instalado em $git" 'install'
        Write-Info 'Nenhuma configuração (user.name/email, remotes, credenciais) foi aplicada.'
        return (New-StepResult -Component 'Git' -Status 'OK' -Message 'Instalado' -Version $v -Path $git -Changed $true -RestartRequired $res.RestartRequired)
    }
    Write-Fail "Instalação não confirmada ($($res.Message))."
    return (New-StepResult -Component 'Git' -Status 'FAILED' -Message "winget: $($res.Message)")
} catch {
    Write-Fail $_.Exception.Message
    return (New-StepResult -Component 'Git' -Status 'FAILED' -Message $_.Exception.Message)
}
