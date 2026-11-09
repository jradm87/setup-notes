# INSTALLATION — passo a passo

O orquestrador `Install-DevStack.ps1` executa as etapas abaixo em ordem. Cada etapa também pode
ser executada isoladamente, por exemplo `.\scripts\06-Install-Node.ps1 -DryRun`.

Todas as etapas seguem o mesmo padrão:

1. detectar o estado atual;
2. se já estiver OK, registrar e **não fazer nada**;
3. se faltar algo, confirmar a origem oficial e instalar **somente o ausente**;
4. validar o resultado;
5. devolver OK / SKIPPED / WARNING / FAILED.

Se uma etapa falhar, as independentes continuam. As dependentes são marcadas SKIPPED:
Python depende de uv, o teste backend depende de uv + Python e o teste frontend depende de Node 26.

Sempre comece com:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-DevStack.ps1 -DryRun
```

---

## ETAPA 1 — Inventário (`01-Inventory.ps1`)

- **Objetivo:** registrar o estado da máquina antes de qualquer mudança.
- **O que é verificado:** Windows (versão/build/arquitetura), PowerShell 5.1/7, ExecutionPolicy,
  WinGet e pacotes relevantes, Git, todos os `python` do PATH, `py -0p`, uv, Node/npm/fnm,
  VS Code e extensões, OpenSSH (e a capability, se a sessão for admin), PATH do usuário e do sistema.
- **O que pode ser instalado:** nada.
- **O que NÃO é alterado:** nada. Variáveis de ambiente (exceto PATH) e arquivos `.env` não são lidos.
- **Saída:** `logs\inventory-before.json` (a cada execução) e `logs\inventory-baseline.json`
  (**só na primeira** execução, como referência do estado original).
- **Como validar:** abrir o JSON.
- **Possíveis erros:** `winget list` lento ou pedindo aceite de termos. O inventário segue sem essa parte.

## ETAPA 2 — PowerShell 7 (`02-Install-PowerShell.ps1`)

- **Objetivo:** ter `pwsh` 7 disponível.
- **O que é verificado:** `pwsh` no PATH, em `%ProgramFiles%\PowerShell\7` ou no atalho de `WindowsApps` (MSIX).
- **O que pode ser instalado:** `Microsoft.PowerShell`, só se ausente, depois de confirmar com
  `winget show --id Microsoft.PowerShell -e --source winget`. Comando:
  `winget install --id Microsoft.PowerShell -e --source winget --no-upgrade --accept-package-agreements --accept-source-agreements`
- **O que NÃO é alterado:** Windows PowerShell 5.1, ExecutionPolicy, perfis, `pwsh` existente (não é atualizado).
- **Elevação:** o WinGet escolhe o instalador. Nesta máquina foi o pacote MSIX (`C:\Program Files\WindowsApps`, com atalho em `%LOCALAPPDATA%\Microsoft\WindowsApps`), sem mudar o PATH. Se for o MSI, o Windows mostra o UAC.
- **Como validar:** em um **novo** terminal, `pwsh --version`.
- **Possíveis erros:** WinGet ausente, UAC negado, proxy. Ver TROUBLESHOOTING.
- Os scripts são compatíveis com 5.1, então o orquestrador **não** reinicia em `pwsh`.

## ETAPA 3 — Git (`03-Install-Git.ps1`)

- **Objetivo:** ter Git for Windows.
- **O que é verificado:** `git --version`.
- **O que pode ser instalado:** `Git.Git` via WinGet, **só se ausente**.
- **O que NÃO é alterado:** `user.name`, `user.email`, remotes, SSH, GitHub/GitLab, credential helper
  e o Git existente (não é atualizado).
- **Como validar:** `git --version`.
- **Possíveis erros:** WinGet ausente ou proxy.

## ETAPA 4 — uv (`04-Install-UV.ps1`)

- **Objetivo:** ter o gerenciador uv.
- **O que é verificado:** primeiro `%LOCALAPPDATA%\DevStack\uv\bin\uv.exe`, depois qualquer `uv` no PATH.
  Se houver um uv existente, ele é **usado como está**, sem `uv self update`.
- **O que pode ser instalado:** o ZIP oficial `uv-<arch>-pc-windows-msvc.zip` da release fixada
  (`UvVersion` no config), vindo de `github.com/astral-sh/uv/releases`. O SHA256 é conferido com o
  `.sha256` publicado e o conteúdo vai para `DevStack\uv\bin`.
  O efeito é igual ao do instalador oficial com `UV_INSTALL_DIR` + `UV_NO_MODIFY_PATH=1`, mas com
  verificação explícita de checksum.
- **O que NÃO é alterado:** PATH e qualquer uv existente.
- **Como validar:** `& "$env:LOCALAPPDATA\DevStack\uv\bin\uv.exe" --version`.
- **Possíveis erros:** GitHub bloqueado por proxy ou checksum divergente (o download é descartado).

## ETAPA 5 — Python 3.14 (`05-Install-Python.ps1`)

- **Objetivo:** ter Python 3.14 para **novos** projetos, sem mexer no Python global.
- **O que é verificado:** `uv python find 3.14`, com `UV_PYTHON_INSTALL_DIR=DevStack\python` e `UV_PYTHON_PREFERENCE=only-managed`.
- **O que pode ser instalado:** `uv python install 3.14 --no-bin --no-registry`.
  - `--no-bin`: não cria `python3.14.exe` em `~\.local\bin`, que **já está no PATH do usuário**.
  - `--no-registry`: não registra no Windows (PEP 514). Sem isso, o `py` passaria a usar o 3.14 por padrão.
  - Nunca usa `--default` nem `--force`.
- **O que NÃO é alterado:** `python.exe` padrão (hoje 3.12), Python Launcher, associações `.py`,
  outras versões e venvs existentes.
- **Como validar:** `.\Enter-DevStack.ps1`, depois `uv run --python 3.14 python --version`.
- **Uso em projetos:** `uv venv --python 3.14` / `uv init --python 3.14`.
- **Possíveis erros:** download do python-build-standalone bloqueado (GitHub) ou antivírus.

## ETAPA 6 — Node.js 26 (`06-Install-Node.ps1`)

- **Objetivo:** ter Node.js 26 LTS **lado a lado** com o Node atual.
- **O que é verificado:** Node 26 em `DevStack\node\node-v26.*-win-<arch>`, ou o `node` do PATH, se já for 26.
- **O que pode ser instalado:** o ZIP oficial `node-v<ver>-win-<arch>.zip` de `nodejs.org/dist`.
  A versão é conferida no `index.json` (precisa ser da major 26 e estar marcada como LTS) e o SHA256
  é conferido no `SHASUMS256.txt` oficial. A extração vai para `DevStack\node\node-v<ver>-win-<arch>`.
  Usa ZIP mesmo quando não existe Node nenhum, para não depender de MSI nem do PATH global.
- **O que NÃO é alterado:** o Node existente (nesta máquina, **v22 via fnm**), o fnm, o npm existente,
  o PATH persistente e o `.npmrc`. Nada é instalado globalmente.
- **Como validar:** `.\Enter-DevStack.ps1`, depois `node --version` (v26.x) e `npm --version`.
- **Possíveis erros:** proxy, checksum, diretório parcial já existente (o script **não** apaga; remova à mão).

## ETAPA 7 — VS Code (`07-Install-VSCode.ps1`)

- **Objetivo:** VS Code com as extensões da stack.
- **O que é verificado:** `code --version` e `code --list-extensions`.
- **O que pode ser instalado:**
  - VS Code (`Microsoft.VisualStudioCode`, escopo usuário), **só se ausente**;
  - **só as extensões ausentes**: `ms-python.python`, `ms-python.vscode-pylance`, `charliermarsh.ruff`,
    `dbaeumer.vscode-eslint`, `esbenp.prettier-vscode`, `ms-vscode.powershell`
    (`code --install-extension <id>`, sem `--force`). Em erro de certificado, repete com `NODE_OPTIONS=--use-system-ca` só nesse comando.
- **O que NÃO é alterado:** a versão do VS Code (não é atualizado), extensões existentes e `settings.json`.
- **Como validar:** `code --list-extensions`.
- **Possíveis erros:** VS Code antigo (1.104 aqui) sem versão compatível de alguma extensão (vira WARNING), proxy do marketplace.

## ETAPA 8 — OpenSSH Client (`08-Install-OpenSSH.ps1`)

- **Objetivo:** ter `ssh` disponível.
- **O que é verificado:** `ssh -V`.
- **O que pode ser instalado:** a capability `OpenSSH.Client~~~~0.0.1.0` (`Add-WindowsCapability`),
  só se ausente e **com sessão elevada**. Sem elevação, a etapa termina em WARNING com instrução.
- **O que NÃO é alterado:** OpenSSH Server (não é instalado), chaves, `ssh_config`, `known_hosts` e ssh-agent.
- **Possíveis erros:** WSUS/políticas bloqueando Features on Demand. Pode exigir reinicialização (é informado, nunca automático).

## ETAPA 9 — Testes (`09-Test-Backend.ps1`, `10-Test-Frontend.ps1`)

Rodam em `%TEMP%\devstack-tests\<nome-único>`, com um arquivo marcador. Só esse diretório é removido
(`-KeepTemp` mantém).

- **Backend:** `uv init --python 3.14`, `uv add fastapi[standard] pydantic-settings httpx`,
  `uv add --dev pytest ruff`, API `GET /health -> {"status":"ok"}`, `pytest`, `ruff check .` e
  uvicorn real em `127.0.0.1:8000` (ou outra porta livre). O PID do python do `.venv` é capturado
  e só essa árvore de processos é encerrada. `UV_PYTHON_DOWNLOADS=never` impede o teste de instalar Python.
- **Frontend:** com o `node.exe` do Node 26, `npm exec create-vite@9.3.4 app --template react-ts --no-interactive`,
  `npm install`, `prettier` local, `npm run lint`, `npm run build` (tsc + vite build) e
  `npm run dev` em `127.0.0.1:5173` (ou outra porta), com checagem HTTP 200. Só a árvore do PID iniciado é encerrada.
- **Nunca** usa `taskkill /IM python.exe` nem `taskkill /IM node.exe`.

## ETAPA 10 — Validação (`11-Validate.ps1`, também chamado por `Test-DevStack.ps1`)

- Confere versões e caminhos de cada ferramenta, sem instalar nada.
- Compara com `logs\inventory-baseline.json` para provar que o ambiente antigo foi preservado:
  `python` e `node` padrão, `py -0p` e nenhuma entrada removida do PATH.
- Grava `logs\inventory-after.json` (só na instalação real).
- Detalhes em [VALIDATION.md](VALIDATION.md).
