# TROUBLESHOOTING

O log de cada execução está em `logs\<script>-<timestamp>.log`. Cada comando externo aparece com a
linha de comando, o exit code e a saída (segredos mascarados).

## WinGet ausente

`winget` vem com o "Instalador de Aplicativo" (App Installer) da Microsoft Store, mas pode faltar em PCs novos.
- Confira com `winget --version`.
- O instalador resolve isso sozinho na etapa `01b-Install-WinGet.ps1`, quando PowerShell 7, Git ou VS Code estão ausentes.
- Se a etapa falhar, confira o acesso a `www.powershellgallery.com`, `github.com` e `cdn.winget.microsoft.com`, ou instale o **App Installer** pela Microsoft Store e abra um novo terminal.
- WinGet só é necessário para PowerShell 7, Git e VS Code **quando ausentes**. uv, Python e Node não dependem dele.
- Erro de termos de origem: rode `winget list` uma vez manualmente e aceite.

## PowerShell 7: erro `-2147009255` (`0x80073D19`)

- Significa que a implantação MSIX foi interrompida porque "um usuário foi desconectado". Pode aparecer em sessões remotas.
- A etapa 02 tenta automaticamente o instalador MSI. Ele pede elevação (UAC) e instala para a máquina toda.
- Sem permissão de administrador, a etapa fica FAILED. O restante da stack funciona, porque os scripts rodam no Windows PowerShell 5.1.

## Proxy / rede corporativa

- Proxy do sistema: `netsh winhttp show proxy`. O `Invoke-WebRequest` usa o proxy do IE/Windows.
- Para uv/npm/pip, defina na sessão **antes** de executar:
  `$env:HTTPS_PROXY = 'http://proxy:porta'` (não grave credenciais em arquivos do pacote).
- Inspeção TLS corporativa: o uv pode precisar de `$env:UV_NATIVE_TLS = '1'` e o npm de
  `$env:NODE_EXTRA_CA_CERTS = 'C:\caminho\ca.pem'`.
- Hosts usados: `nodejs.org`, `github.com` + `*.githubusercontent.com`, `pypi.org` +
  `files.pythonhosted.org`, `registry.npmjs.org`, `marketplace.visualstudio.com`.
- "SHA256 divergente": o arquivo é descartado. Geralmente o proxy alterou ou truncou o download.

## Permissão / elevação

- Não é preciso rodar como Administrador.
- O PowerShell 7 só pede UAC se o WinGet escolher o instalador MSI. Se o UAC for negado, a etapa fica FAILED e as outras continuam.
- OpenSSH Client ausente exige sessão elevada: abra o PowerShell como Administrador e rode só
  `.\scripts\08-Install-OpenSSH.ps1`.
- "Execução de scripts desabilitada": use `powershell -ExecutionPolicy Bypass -File ...` ou
  `Set-ExecutionPolicy -Scope Process Bypass` (só vale para a janela atual).
- Pacote vindo de ZIP baixado: `Get-ChildItem -Recurse | Unblock-File`.

## PATH

- Os scripts **não** alteram o PATH persistente. Para usar uv/Node 26: `.\Enter-DevStack.ps1`.
- Depois de instalar PowerShell 7/Git/VS Code via WinGet, **abra um novo terminal**.
- `Show-DevStackStatus.ps1` mostra os caminhos físicos e avisa se algum diretório da stack foi parar no PATH persistente.
- `Enter-DevStack` não funcionou? Ele precisa rodar **na mesma sessão** (`.\Enter-DevStack.ps1`),
  não via `powershell -File`, que cria outro processo.

## PowerShell

- Tudo é compatível com Windows PowerShell 5.1 e PowerShell 7.
- Caracteres acentuados estranhos: os `.ps1` são UTF-8 **com BOM**. Se um editor removeu o BOM,
  salve de novo como "UTF-8 with BOM".
- `pwsh` instalado mas "não reconhecido": abra um novo terminal (o PATH do sistema é lido na abertura).

## Node existente (fnm / v22)

- O Node padrão continua sendo o do fnm (`%APPDATA%\fnm\aliases\default`). O Node 26 fica em `DevStack\node`.
- Se a sessão já rodou `fnm env`/`fnm use`, o fnm pode pôr o diretório *multishell* dele **à frente**
  depois do `Enter-DevStack` (por exemplo, com `--use-on-cd` ao trocar de pasta). Confira com `Get-Command node`.
- "Diretório já existe mas não contém um Node funcional": uma extração anterior foi interrompida.
  Apague à mão `DevStack\node\node-v26.*` e rode de novo. O script nunca apaga diretórios existentes.

## Python existente

- `python` continua apontando para o 3.12 e `py` continua listando só o 3.12. Isso é intencional.
- Se `py -0p` passar a listar o 3.14, ele foi registrado por outro meio (por exemplo, um
  `uv python install` manual sem `--no-registry`). Desfaça com `uv python uninstall 3.14`
  (com o mesmo `UV_PYTHON_INSTALL_DIR`) e reinstale pelo script.
- O alias da Microsoft Store (`WindowsApps\python.exe`) é ignorado pelos scripts.

## uv

- Um uv existente no PATH é reaproveitado (não é atualizado). Versões muito antigas podem não ter
  `--no-registry`/`--no-bin`. Nesse caso, renomeie ou remova esse uv do PATH da
  sessão e rode a etapa 04 (ela instala a versão fixada em `DevStack\uv\bin`).
- Sem `Enter-DevStack`, um `uv` executado fora dele usa `%APPDATA%\uv\python` e **não** enxerga o
  Python 3.14 da stack. Isso também é intencional.

## VS Code

- VS Code 1.104 (instalado) é antigo. Se alguma extensão exigir versão mais nova, a instalação dela
  fica WARNING. O script **não** atualiza o VS Code; atualize manualmente se quiser.
- `self signed certificate in certificate chain`: inspeção TLS (ex.: Cloudflare WARP). A etapa 07 repete a instalação com `NODE_OPTIONS=--use-system-ca` só nesse comando.
- `code` não encontrado: confira se `...\Microsoft VS Code\bin` está no PATH ou abra um novo terminal.

## OpenSSH

- `ssh -V` escreve em stderr, o que é normal (os scripts tratam isso).
- Features on Demand bloqueadas por WSUS/GPO: peça à TI, ou use
  `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -Source <origem>`.

## Reinicialização necessária

- O resumo final informa **REINICIALIZAÇÃO NECESSÁRIA** quando o WinGet (exit `0x8A150109`/3010) ou o
  `Add-WindowsCapability` (`RestartNeeded`) indicam isso.
- **Nada reinicia automaticamente.** Reinicie quando for conveniente e rode `.\Test-DevStack.ps1`.

## Testes

- Porta 8000/5173 ocupada: o teste usa outra porta livre e registra um WARNING. Nenhum processo existente é encerrado.
- Timeout no dev server/uvicorn: rode com `-KeepTemp` e veja `uvicorn.err.log`/`vite.err.log` na pasta temporária.
- Antivírus atrasando o `npm install`: aumente `HttpTimeoutSeconds` em `config\DevStackConfig.psd1`.
