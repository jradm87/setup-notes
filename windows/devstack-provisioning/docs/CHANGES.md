# CHANGES — alterações que cada script PODE fazer

Documento antecipado: lista **tudo** o que cada script pode alterar na máquina. Em `-DryRun`,
nenhum deles altera nada além de gravar logs em `logs\`.

| Script | Pode alterar | Condição | Escopo | Reversão |
|---|---|---|---|---|
| `01-Inventory.ps1` | Nada (só grava `logs\*.json`) | sempre | pacote | apagar o JSON |
| `01b-Install-WinGet.ps1` | Instala o provedor NuGet e o módulo `Microsoft.WinGet.Client` em `Documents\WindowsPowerShell` (ou `Documents\PowerShell`) e o WinGet (App Installer) para o usuário. Usa `-Force` só para evitar perguntas e apenas no que está ausente. Registra o PSGallery padrão se não existir, sem marcá-lo como confiável | só se o `winget` não existir **e** faltar PowerShell 7, Git ou VS Code | usuário | `Uninstall-Module Microsoft.WinGet.Client` e Aplicativos > Instalador de Aplicativo |
| `02-Install-PowerShell.ps1` | Instala o PowerShell 7. O WinGet escolhe o instalador: **MSIX** (`C:\Program Files\WindowsApps`, atalho em `%LOCALAPPDATA%\Microsoft\WindowsApps`, PATH inalterado; foi o caso nesta máquina) ou MSI (`%ProgramFiles%\PowerShell\7`, com entrada no PATH do sistema) | só se `pwsh` não existir | máquina (UAC) | Configurações > Aplicativos > PowerShell 7 |
| `03-Install-Git.ps1` | Instala o Git for Windows (PATH adicionado pelo instalador) | só se `git` não existir | máquina | Aplicativos > Git |
| `04-Install-UV.ps1` | Cria `%LOCALAPPDATA%\DevStack\uv\bin\{uv,uvx,uvw}.exe` e `DevStack\downloads\uv-*.zip` | só se não houver uv | usuário | apagar `DevStack\uv` |
| `05-Install-Python.ps1` | Cria `%LOCALAPPDATA%\DevStack\python\cpython-3.14.*` e o cache `DevStack\uv\cache`. **Sem** registro PEP 514 e **sem** shims em `~\.local\bin` | só se o 3.14 gerenciado não existir | usuário | apagar `DevStack\python` |
| `06-Install-Node.ps1` | Cria `%LOCALAPPDATA%\DevStack\node\node-v26.x-win-<arch>` e `DevStack\downloads\node-*.zip` | só se não houver Node 26 | usuário | apagar a pasta |
| `07-Install-VSCode.ps1` | Instala o VS Code (escopo usuário) se ausente. Instala **extensões ausentes** em `%USERPROFILE%\.vscode\extensions` | ausência | usuário | `code --uninstall-extension <id>` |
| `08-Install-OpenSSH.ps1` | `Add-WindowsCapability OpenSSH.Client` | só se `ssh` não existir **e** a sessão for admin | máquina | `Remove-WindowsCapability` |
| `09-Test-Backend.ps1` | Cria e remove `%TEMP%\devstack-tests\backend-*`. Popula `DevStack\uv\cache`. Abre e fecha uma porta local temporária | Test/Install sem `-SkipTests` | usuário | automático |
| `10-Test-Frontend.ps1` | Cria e remove `%TEMP%\devstack-tests\frontend-*`. Popula o **cache do npm** (`%LOCALAPPDATA%\npm-cache`, compartilhado, só cache) | idem | usuário | `npm cache verify` / automático |
| `11-Validate.ps1` | Nada (grava `logs\inventory-after.json` na instalação real) | sempre | pacote | — |
| `Enter-DevStack.ps1` | PATH e variáveis `UV_*`/`DEVSTACK_*` **do processo atual** | ao executar | sessão | `Exit-DevStack.ps1` ou fechar o terminal |
| `Exit-DevStack.ps1` | Restaura as variáveis acima | ao executar | sessão | — |
| `Show-DevStackStatus.ps1` | Nada | — | — | — |

## Alterações globais previstas nesta máquina (pelo inventário de 2026-11-07)

- **PowerShell 7**: instalado como pacote MSIX pelo WinGet, sem alterar o PATH.
- **6 extensões do VS Code** no perfil do usuário (hoje não há nenhuma).
- Tudo o mais fica em `%LOCALAPPDATA%\DevStack`, sem tocar no PATH persistente.

## Garantias (o que NUNCA é feito)

- `winget upgrade` (qualquer forma), `winget uninstall`, `--force`
- `npm install -g` (inclusive `npm install -g npm`), `pip install --upgrade` global
- `uv python install --default`, `uv self update`
- remoção ou reordenação de entradas do PATH persistente
- alteração de ExecutionPolicy persistente, perfis do PowerShell, `settings.json` do VS Code, `.gitconfig`, `.npmrc`, fnm
- `taskkill /IM`, `Stop-Process -Name`, nem encerrar processos que os scripts não iniciaram
- reinicialização automática
