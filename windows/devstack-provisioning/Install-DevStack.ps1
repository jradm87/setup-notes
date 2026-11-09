<#
.SYNOPSIS
    Orquestrador do provisionamento DevStack (aditivo, idempotente, não destrutivo).
.PARAMETER DryRun
    Simulação: nada é instalado, nenhum PATH/configuração é alterado. Só mostra o que faria.
.PARAMETER SkipTests
    Não executa os testes de backend/frontend (etapas 09 e 10).
.PARAMETER SkipVSCodeExtensions
    Não verifica/instala extensões do VS Code.
.PARAMETER KeepTemp
    Mantém os diretórios temporários dos testes (para depuração).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-DevStack.ps1 -DryRun
.NOTES
    Exit code: 0 = sem falhas | 1 = ao menos uma etapa FAILED | 2 = erro fatal do orquestrador.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipTests,
    [switch]$SkipVSCodeExtensions,
    [switch]$KeepTemp
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scripts = Join-Path $PSScriptRoot 'scripts'
. (Join-Path $scripts '00-Common.ps1')

try {
    $prefix = if ($DryRun) { 'install-dryrun' } else { 'install' }
    $ctx = Initialize-DevStackContext -LogPrefix $prefix
} catch {
    Write-Host "[FATAL] $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

$mode = if ($DryRun) { 'DRY-RUN (simulação, nada será alterado)' } else { 'INSTALAÇÃO REAL' }
Write-Host ''
Write-Host 'DevStack provisioning' -ForegroundColor Cyan
Write-Host "  Modo        : $mode"
Write-Host "  PowerShell  : $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
Write-Host "  Arquitetura : $($ctx.Arch)"
Write-Host "  Admin       : $(Test-IsAdministrator)"
Write-Host "  StackRoot   : $($ctx.Paths.StackRoot)"
Write-Host "  Log         : $($ctx.LogFile)"
Write-DevLog -Level INFO -Step 'orchestrator' -Action 'start' -Message "mode=$mode ps=$($PSVersionTable.PSVersion) admin=$(Test-IsAdministrator)"

$steps = @(
    @{ N = 1;  Title = 'Inventário inicial'; File = '01-Inventory.ps1';          DependsOn = @();          Extra = @{ OutputName = 'inventory-before.json' } }
    @{ N = 2;  Title = 'WinGet';             File = '01b-Install-WinGet.ps1';    DependsOn = @();          Extra = @{} }
    @{ N = 3;  Title = 'PowerShell 7';       File = '02-Install-PowerShell.ps1'; DependsOn = @();          Extra = @{} }
    @{ N = 4;  Title = 'Git';                File = '03-Install-Git.ps1';        DependsOn = @();          Extra = @{} }
    @{ N = 5;  Title = 'uv';                 File = '04-Install-UV.ps1';         DependsOn = @();          Extra = @{} }
    @{ N = 6;  Title = 'Python';             File = '05-Install-Python.ps1';     DependsOn = @('uv');      Extra = @{} }
    @{ N = 7;  Title = 'Node.js';            File = '06-Install-Node.ps1';       DependsOn = @();          Extra = @{} }
    @{ N = 8;  Title = 'VS Code';            File = '07-Install-VSCode.ps1';     DependsOn = @();          Extra = @{ SkipExtensions = [bool]$SkipVSCodeExtensions } }
    @{ N = 9;  Title = 'OpenSSH';            File = '08-Install-OpenSSH.ps1';    DependsOn = @();          Extra = @{} }
    @{ N = 10; Title = 'Teste backend';      File = '09-Test-Backend.ps1';       DependsOn = @('uv', "Python $($ctx.Config.PythonVersion)"); Extra = @{ KeepTemp = [bool]$KeepTemp }; Test = $true }
    @{ N = 11; Title = 'Teste frontend';     File = '10-Test-Frontend.ps1';      DependsOn = @("Node $($ctx.Config.NodeMajorVersion)"); Extra = @{ KeepTemp = [bool]$KeepTemp }; Test = $true }
    @{ N = 12; Title = 'Validação final';    File = '11-Validate.ps1';           DependsOn = @();          Extra = @{ WriteInventory = (-not $DryRun) } }
)
$total = $steps.Count
$all = New-Object System.Collections.Generic.List[object]
$validation = New-Object System.Collections.Generic.List[object]
$stepResults = New-Object System.Collections.Generic.List[object]

foreach ($s in $steps) {
    Write-StepHeader -Index $s.N -Total $total -Title $s.Title
    $isTest = $s.ContainsKey('Test') -and $s.Test

    if ($isTest -and $SkipTests) {
        Write-Info 'Ignorado (-SkipTests).'
        $stepResults.Add((New-StepResult -Component $s.Title -Status 'SKIPPED' -Message '-SkipTests'))
        continue
    }
    $failedDeps = @($s.DependsOn | Where-Object { $d = $_; @($all | Where-Object { $_.Component -eq $d -and $_.Status -eq 'FAILED' }).Count -gt 0 })
    if ($failedDeps.Count -gt 0) {
        Write-Warn "Ignorado: dependência com falha ($($failedDeps -join ', '))."
        $stepResults.Add((New-StepResult -Component $s.Title -Status 'SKIPPED' -Message "Dependência falhou: $($failedDeps -join ', ')"))
        continue
    }

    $path = Join-Path $scripts $s.File
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Fail "Script ausente: $path"
        $stepResults.Add((New-StepResult -Component $s.Title -Status 'FAILED' -Message 'Script ausente'))
        continue
    }
    $params = @{ LogFile = $ctx.LogFile; DryRun = [bool]$DryRun }
    foreach ($k in $s.Extra.Keys) { $params[$k] = $s.Extra[$k] }
    try {
        $out = @(& $path @params | Select-StepResult)
        if ($out.Count -eq 0) {
            $stepResults.Add((New-StepResult -Component $s.Title -Status 'WARNING' -Message 'Etapa não retornou resultado'))
        }
        if ($s.File -eq '11-Validate.ps1' -and $DryRun) {
            # Em DRY-RUN nada foi instalado: ausências são esperadas, não falhas.
            foreach ($r in @($out | Where-Object Status -eq 'FAILED')) {
                $r.Status = 'WARNING'
                $r.Message = "$($r.Message) (esperado em DRY-RUN)"
            }
        }
        foreach ($r in $out) { if ($s.File -eq '11-Validate.ps1') { $validation.Add($r) } else { $all.Add($r) } }
        $worst = 'OK'
        foreach ($st in @('SKIPPED', 'WARNING', 'FAILED')) { if (@($out | Where-Object Status -eq $st).Count) { $worst = $st } }
        if ($out.Count -gt 0) { $stepResults.Add([pscustomobject]@{ PSTypeName = 'DevStack.StepResult'; Component = $s.Title; Status = $worst; Message = (@($out | ForEach-Object { "$($_.Component)=$($_.Status)" }) -join ', '); Version = ''; Path = ''; Changed = [bool](@($out | Where-Object Changed).Count); RestartRequired = [bool](@($out | Where-Object RestartRequired).Count) }) }
    } catch {
        Write-Fail "Erro não tratado na etapa: $($_.Exception.Message)"
        $stepResults.Add((New-StepResult -Component $s.Title -Status 'FAILED' -Message $_.Exception.Message))
    }

    if ($s.N -eq 1) {
        $before = Join-Path $ctx.Paths.LogDir 'inventory-before.json'
        $baseline = Join-Path $ctx.Paths.LogDir 'inventory-baseline.json'
        if ((Test-Path -LiteralPath $before) -and -not (Test-Path -LiteralPath $baseline)) {
            Copy-Item -LiteralPath $before -Destination $baseline
            Write-Info 'Baseline original salvo em logs\inventory-baseline.json (gravado apenas na primeira execução).'
        }
    }
}

Write-ResultSummary -Results $stepResults.ToArray() -Title 'RESUMO POR ETAPA'
Write-ResultSummary -Results $all.ToArray() -Title 'RESUMO POR COMPONENTE'
if ($validation.Count -gt 0) { Write-ResultSummary -Results $validation.ToArray() -Title 'VALIDAÇÃO FINAL' }

$changed = @($all | Where-Object Changed)
$restart = @($all | Where-Object RestartRequired)
$failed = @($all | Where-Object Status -eq 'FAILED') + @($validation | Where-Object Status -eq 'FAILED') + @($stepResults | Where-Object Status -eq 'FAILED')

Write-Host ''
if ($DryRun) {
    Write-Host 'DRY-RUN concluído: nenhuma alteração foi feita.' -ForegroundColor Magenta
} elseif ($changed.Count -gt 0) {
    Write-Host "Componentes alterados nesta execução: $(@($changed | ForEach-Object Component) -join ', ')" -ForegroundColor Cyan
    Write-Host 'Abra um NOVO terminal para que instalações via WinGet apareçam no PATH.' -ForegroundColor Cyan
} else {
    Write-Host 'Nenhuma alteração foi necessária (ambiente já provisionado).' -ForegroundColor Green
}
if ($restart.Count -gt 0) {
    Write-Host "REINICIALIZAÇÃO NECESSÁRIA (não será feita automaticamente): $(@($restart | ForEach-Object Component) -join ', ')" -ForegroundColor Yellow
}
Write-Host "Log: $($ctx.LogFile)"
Write-Host 'Para usar a nova stack nesta sessão: .\Enter-DevStack.ps1'

if ($failed.Count -gt 0) {
    Write-Host 'Resultado: FAILED' -ForegroundColor Red
    Write-DevLog -Level FAIL -Step 'orchestrator' -Action 'end' -Result 'FAILED'
    exit 1
}
Write-Host 'Resultado: OK' -ForegroundColor Green
Write-DevLog -Level OK -Step 'orchestrator' -Action 'end' -Result 'OK'
exit 0
