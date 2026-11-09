<#
.SYNOPSIS
    Valida a stack (NÃO instala nada) e executa os testes FastAPI e React/Vite.
.PARAMETER SkipBackend
    Não executa o teste FastAPI.
.PARAMETER SkipFrontend
    Não executa o teste React/Vite.
.PARAMETER KeepTemp
    Mantém os projetos temporários para inspeção.
.NOTES
    Exit code: 0 = PASS | 1 = FAIL (ao menos um componente FAILED) | 2 = erro fatal.
    Os testes baixam pacotes de PyPI/npm para diretórios temporários (não instalam nada globalmente).
#>
[CmdletBinding()]
param([switch]$SkipBackend, [switch]$SkipFrontend, [switch]$KeepTemp)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scripts = Join-Path $PSScriptRoot 'scripts'
. (Join-Path $scripts '00-Common.ps1')
try { $ctx = Initialize-DevStackContext -LogPrefix 'test' } catch { Write-Host "[FATAL] $($_.Exception.Message)" -ForegroundColor Red; exit 2 }

$results = New-Object System.Collections.Generic.List[object]
function Invoke-Part([int]$i, [string]$title, [string]$file, [hashtable]$extra = @{}) {
    Write-StepHeader -Index $i -Total 3 -Title $title
    try {
        $p = @{ LogFile = $ctx.LogFile }
        foreach ($k in $extra.Keys) { $p[$k] = $extra[$k] }
        foreach ($r in @(& (Join-Path $scripts $file) @p | Select-StepResult)) { $results.Add($r) }
    } catch {
        Write-Fail $_.Exception.Message
        $results.Add((New-StepResult -Component $title -Status 'FAILED' -Message $_.Exception.Message))
    }
}

Invoke-Part 1 'Ferramentas' '11-Validate.ps1'

$pyComp = "Python $($ctx.Config.PythonVersion)"
$nodeComp = "Node $($ctx.Config.NodeMajorVersion)"
function Test-Failed([string]$c) { return [bool](@($results | Where-Object { $_.Component -eq $c -and $_.Status -eq 'FAILED' }).Count) }

if ($SkipBackend) {
    foreach ($n in 'FastAPI', 'pytest', 'Ruff') { $results.Add((New-StepResult -Component $n -Status 'SKIPPED' -Message '-SkipBackend')) }
} elseif ((Test-Failed 'uv') -or (Test-Failed $pyComp)) {
    foreach ($n in 'FastAPI', 'pytest', 'Ruff') { $results.Add((New-StepResult -Component $n -Status 'FAILED' -Message "Pré-requisito ausente (uv/$pyComp)")) }
} else {
    Invoke-Part 2 'Teste backend' '09-Test-Backend.ps1' @{ KeepTemp = [bool]$KeepTemp }
}

if ($SkipFrontend) {
    foreach ($n in 'React/Vite', 'Frontend build') { $results.Add((New-StepResult -Component $n -Status 'SKIPPED' -Message '-SkipFrontend')) }
} elseif (Test-Failed $nodeComp) {
    foreach ($n in 'React/Vite', 'Frontend build') { $results.Add((New-StepResult -Component $n -Status 'FAILED' -Message "Pré-requisito ausente ($nodeComp)")) }
} else {
    Invoke-Part 3 'Teste frontend' '10-Test-Frontend.ps1' @{ KeepTemp = [bool]$KeepTemp }
}

Write-ResultSummary -Results $results.ToArray() -Title 'RESULTADO DA VALIDAÇÃO'
$failed = @($results | Where-Object Status -eq 'FAILED')
Write-Host ''
Write-Host 'Resultado geral:'
if ($failed.Count -gt 0) {
    Write-Host 'FAIL' -ForegroundColor Red
    Write-Host "Componentes com falha: $(@($failed | ForEach-Object Component) -join ', ')"
    Write-Host "Log: $($ctx.LogFile)"
    exit 1
}
Write-Host 'PASS' -ForegroundColor Green
Write-Host "Log: $($ctx.LogFile)"
exit 0
