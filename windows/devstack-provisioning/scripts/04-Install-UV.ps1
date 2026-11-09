<#
.SYNOPSIS
    [04] uv — usa o uv existente; se ausente, instala o binário oficial (GitHub astral-sh/uv)
    em StackRoot\uv\bin, com verificação SHA256 e SEM alterar o PATH.
.NOTES
    Equivale ao instalador oficial com UV_INSTALL_DIR=<StackRoot>\uv\bin e UV_NO_MODIFY_PATH=1,
    porém com verificação explícita de checksum. Nunca atualiza um uv existente (sem 'uv self update').
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'uv'
$script:CurrentStep = 'uv'
$allowedHosts = @('github.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com')

try {
    Write-Info 'Verificando uv...'
    $uv = Find-UvExecutable
    if ($uv) {
        $v = Get-ToolVersionText -FilePath $uv.Path
        if ($v) {
            $origin = if ($uv.Source -eq 'devstack') { 'instalação da stack' } else { 'instalação existente (será utilizada, não alterada)' }
            Write-Ok "Encontrado: $v em $($uv.Path) — $origin"
            Write-Info 'Nenhuma alteração necessária.'
            return (New-StepResult -Component 'uv' -Status 'OK' -Message "Já existente ($($uv.Source))" -Version $v -Path $uv.Path)
        }
        Write-Warn "uv em $($uv.Path) não respondeu a --version."
    }

    $ver = $ctx.Config.UvVersion
    $asset = "uv-$($ctx.UvTriple).zip"
    $base = '{0}/{1}' -f $ctx.Config.UvReleaseBaseUrl.TrimEnd('/'), $ver
    $zipUrl = "$base/$asset"
    $shaUrl = "$zipUrl.sha256"
    $targetDir = $ctx.Paths.UvBinDir
    Write-Info 'uv não encontrado.'
    Write-Info "Preparando instalação de uv $ver ($($ctx.Arch)) em $targetDir"

    if ($DryRun) {
        Write-DryRun "Baixaria $zipUrl"
        Write-DryRun "Validaria SHA256 com $shaUrl"
        Write-DryRun "Extrairia uv.exe/uvx.exe para $targetDir (PATH NÃO seria alterado)"
        return (New-StepResult -Component 'uv' -Status 'SKIPPED' -Message "DRY-RUN: instalaria uv $ver em $targetDir")
    }

    $shaText = Get-RemoteText -Uri $shaUrl -AllowedHosts $allowedHosts
    $expected = ($shaText.Trim() -split '\s+')[0]
    if ($expected -notmatch '^[0-9a-fA-F]{64}$') { throw "Checksum inválido obtido de $shaUrl" }

    $zip = Join-Path $ctx.Paths.DownloadDir $asset.Replace('.zip', "-$ver.zip")
    Invoke-VerifiedDownload -Uri $zipUrl -OutFile $zip -ExpectedSha256 $expected -AllowedHosts $allowedHosts | Out-Null

    $staging = Join-Path $ctx.Paths.StackRoot ('uv\.staging-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
        Expand-Archive -LiteralPath $zip -DestinationPath $staging
        if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir | Out-Null }
        $exes = @(Get-ChildItem -LiteralPath $staging -Recurse -File -Include 'uv.exe', 'uvx.exe', 'uvw.exe')
        if (-not ($exes | Where-Object Name -eq 'uv.exe')) { throw 'uv.exe não encontrado no pacote baixado.' }
        foreach ($e in $exes) {
            $dest = Join-Path $targetDir $e.Name
            if (Test-Path -LiteralPath $dest) { Write-Info "$($e.Name) já existe em $targetDir — mantido."; continue }
            Copy-Item -LiteralPath $e.FullName -Destination $dest
        }
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse }
    }

    $uvExe = Join-Path $targetDir 'uv.exe'
    $v = Get-ToolVersionText -FilePath $uvExe
    if (-not $v) { throw "uv instalado em $uvExe não respondeu a --version." }
    Write-Ok "$v instalado em $uvExe (PATH não alterado; use Enter-DevStack.ps1)" 'install'
    return (New-StepResult -Component 'uv' -Status 'OK' -Message 'Instalado (isolado)' -Version $v -Path $uvExe -Changed $true)
} catch {
    Write-Fail $_.Exception.Message
    return (New-StepResult -Component 'uv' -Status 'FAILED' -Message $_.Exception.Message)
}
