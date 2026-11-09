<#
.SYNOPSIS
    [06] Node.js 26 LTS SIDE-BY-SIDE via ZIP oficial (nodejs.org), com verificação SHA256.
.NOTES
    - Se a stack já tem Node 26, ou o Node do PATH já é 26: nada a fazer.
    - Caso contrário (inclusive quando existe OUTRA versão, ex.: fnm/v22): extrai o ZIP em
      StackRoot\node\node-v<ver>-win-<arch>. Nunca usa MSI, nunca toca no Node existente,
      nunca altera PATH persistente, nunca atualiza npm.
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'node'
$script:CurrentStep = 'Node.js'
$major = [int]$ctx.Config.NodeMajorVersion
$comp = "Node $major"
$allowedHosts = @('nodejs.org')
$dist = $ctx.Config.NodeDistBaseUrl.TrimEnd('/')

function Resolve-NodeVersion {
    # Retorna objeto { Version; Lts } validado contra index.json oficial.
    $index = (Get-RemoteText -Uri "$dist/index.json" -AllowedHosts $allowedHosts) | ConvertFrom-Json
    $wanted = [string]$ctx.Config.NodeVersion
    if ($wanted) {
        $entry = @($index | Where-Object { $_.version -eq ('v' + $wanted.TrimStart('v')) }) | Select-Object -First 1
        if (-not $entry) { throw "Versão $wanted não encontrada em $dist/index.json" }
    } else {
        $entry = @($index | Where-Object { $_.version -like "v$major.*" -and $_.lts }) | Select-Object -First 1
        if (-not $entry) { throw "Nenhuma versão LTS da major $major encontrada em $dist/index.json" }
    }
    if ((Get-NodeMajor $entry.version) -ne $major) { throw "Versão $($entry.version) não pertence à major $major" }
    $fileKey = "win-$($ctx.Arch)-zip"
    if (@($entry.files) -notcontains $fileKey) { throw "Versão $($entry.version) não publica $fileKey" }
    return [pscustomobject]@{ Version = $entry.version.TrimStart('v'); Lts = $entry.lts }
}

try {
    Write-Info 'Verificando Node.js...'
    $pathNode = Get-FirstCommandPath 'node'
    if ($pathNode) {
        Write-Info "Node padrão (não será alterado): $(Get-ToolVersionText -FilePath $pathNode) em $pathNode"
        $npmDefault = Get-FirstCommandPath 'npm.cmd'
        if ($npmDefault) { Write-Info "npm padrão (não será alterado): $(Get-ToolVersionText -FilePath $npmDefault) em $npmDefault" }
    } else {
        Write-Info 'Nenhum Node no PATH.'
    }
    if (Get-FirstCommandPath 'fnm') { Write-Info 'fnm detectado: o Node 26 da stack NÃO será registrado no fnm.' }

    $n26 = Find-Node26
    if ($n26) {
        Write-Ok "Node $($n26.Version) encontrado em $($n26.NodeExe) ($($n26.Source))"
        Write-Info 'Nenhuma alteração necessária.'
        return (New-StepResult -Component $comp -Status 'OK' -Message "Já existente ($($n26.Source))" -Version $n26.Version -Path $n26.NodeExe)
    }

    Write-Info "Node $major não encontrado. Será preparado SIDE-BY-SIDE (ZIP oficial)."
    $rel = Resolve-NodeVersion
    $ltsName = if ($rel.Lts) { "LTS '$($rel.Lts)'" } else { 'NÃO-LTS' }
    if (-not $rel.Lts) { Write-Warn "Node $($rel.Version) não está marcado como LTS no index.json." }
    $dirName = Get-NodeDirName -Version $rel.Version
    $zipName = "$dirName.zip"
    $zipUrl = "$dist/v$($rel.Version)/$zipName"
    $shaUrl = "$dist/v$($rel.Version)/SHASUMS256.txt"
    $target = Join-Path $ctx.Paths.NodeRoot $dirName
    Write-Info "Versão: $($rel.Version) ($ltsName), arquitetura $($ctx.Arch)"

    if ($DryRun) {
        Write-DryRun "Baixaria $zipUrl"
        Write-DryRun "Validaria SHA256 com $shaUrl"
        Write-DryRun "Extrairia para $target"
        Write-DryRun 'Node/npm existentes e PATH persistente permaneceriam intactos.'
        return (New-StepResult -Component $comp -Status 'SKIPPED' -Message "DRY-RUN: instalaria Node $($rel.Version) side-by-side")
    }

    if (Test-Path -LiteralPath $target) {
        throw "Diretório $target já existe mas não contém um Node $major funcional. Verifique/remova-o manualmente (o script não apaga diretórios existentes)."
    }

    $sums = Get-RemoteText -Uri $shaUrl -AllowedHosts $allowedHosts
    $line = @($sums -split "`n" | Where-Object { $_ -match ('\s' + [regex]::Escape($zipName) + '\s*$') }) | Select-Object -First 1
    if (-not $line) { throw "Checksum de $zipName não encontrado em SHASUMS256.txt" }
    $expected = ($line.Trim() -split '\s+')[0]

    $zip = Join-Path $ctx.Paths.DownloadDir $zipName
    Invoke-VerifiedDownload -Uri $zipUrl -OutFile $zip -ExpectedSha256 $expected -AllowedHosts $allowedHosts | Out-Null

    if (-not (Test-Path -LiteralPath $ctx.Paths.NodeRoot)) { New-Item -ItemType Directory -Path $ctx.Paths.NodeRoot | Out-Null }
    $staging = Join-Path $ctx.Paths.NodeRoot ('.staging-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $staging | Out-Null
    try {
        Write-Info "Extraindo para área temporária $staging ..." 'install'
        Expand-Archive -LiteralPath $zip -DestinationPath $staging
        $inner = Join-Path $staging $dirName
        if (-not (Test-Path -LiteralPath (Join-Path $inner 'node.exe'))) { throw "Estrutura inesperada no ZIP (sem $dirName\node.exe)." }
        Move-Item -LiteralPath $inner -Destination $target
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse }
    }

    $n26 = Find-Node26
    if (-not $n26 -or $n26.Source -ne 'devstack') { throw "Node extraído em $target não foi validado." }
    $npmVer = $null
    if ($n26.NpmCli) { $npmVer = Get-ToolVersionText -FilePath $n26.NodeExe -ArgumentList @($n26.NpmCli, '--version') }
    Write-Ok "Node $($n26.Version) (npm $npmVer) instalado em $($n26.NodeDir)" 'install'
    Write-Info 'PATH persistente não alterado. Use .\Enter-DevStack.ps1 para priorizar o Node 26 na sessão.'
    return (New-StepResult -Component $comp -Status 'OK' -Message 'Instalado side-by-side' -Version $n26.Version -Path $n26.NodeExe -Changed $true)
} catch {
    Write-Fail $_.Exception.Message
    return (New-StepResult -Component $comp -Status 'FAILED' -Message $_.Exception.Message)
}
