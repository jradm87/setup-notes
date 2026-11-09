<!--
COMO USAR: copie este arquivo para a raiz do projeto com o nome CLAUDE.md.
O Claude Code lê esse arquivo sozinho ao abrir a pasta. Pré-requisito: Install-DevStack.ps1 já executado nesta máquina.
-->

# Instruções do projeto: ambiente DevStack

Você está ajudando um dev low-code a criar uma aplicação web em uma estação Windows.
O desenvolvimento é local, em Windows nativo. **A aplicação será migrada para containers Linux depois**,
então as tecnologias e regras abaixo são obrigatórias, não sugestões.

Fale com o dev em português simples. Explique o que vai fazer antes de mudanças grandes, e só pergunte
o que for decisão de negócio. Decisões técnicas cobertas aqui já estão tomadas.

## Stack obrigatória

| Parte | Tecnologia |
|---|---|
| API | Python 3.14, FastAPI, Pydantic, pydantic-settings, httpx |
| Testes e qualidade da API | pytest, Ruff |
| Gerenciador Python | uv (nunca pip, Poetry, Pipenv ou conda) |
| Front | React, TypeScript, Vite |
| Qualidade do front | ESLint, Prettier |
| Gerenciador Node | npm do Node 26 (nunca Yarn, pnpm ou Bun) |

Não troque nem acrescente framework (Django, Flask, Next.js, Vue etc.) sem o dev pedir.
Se o pedido não couber nesta stack, explique o motivo e proponha uma solução dentro dela.

## Ambiente: como executar comandos

A stack fica isolada em `%LOCALAPPDATA%\DevStack` e **não está no PATH**. O `node` e o `python` padrão
da máquina são de outros projetos (versões antigas): nunca use esses.

O estado do shell não persiste entre comandos. Por isso, **comece todo comando de `uv`, `node`, `npm` ou `npx`
com este bloco, em PowerShell**, na mesma chamada:

```powershell
$ds = "$env:LOCALAPPDATA\DevStack"; $nodeDir = (Get-ChildItem "$ds\node\node-v26.*-win-*" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName; $env:Path = "$nodeDir;$ds\uv\bin;$env:Path"; $env:UV_PYTHON_INSTALL_DIR = "$ds\python"; $env:UV_CACHE_DIR = "$ds\uv\cache"; $env:UV_PYTHON_PREFERENCE = 'only-managed'; $env:UV_PYTHON_DOWNLOADS = 'never'
```

No Windows PowerShell 5.1, `&&` não existe: encadeie com `;`.

No início do trabalho, confira o ambiente com o bloco acima seguido de:

```powershell
node --version; npm --version; uv --version; uv python find 3.14 --no-project
```

O esperado é Node v26 e um caminho dentro de `DevStack\python`. **Se falhar, pare e peça ao dev para rodar
`Install-DevStack.ps1` e `Test-DevStack.ps1`.** Não tente instalar ou consertar o ambiente por conta própria.

## Estrutura do projeto

```
projeto/
├── CLAUDE.md
├── README.md            como rodar, em linguagem simples
├── .gitignore           .venv, node_modules, dist, .env, __pycache__, .ruff_cache
├── .gitattributes       * text=auto eol=lf
├── .env.example         nomes das variáveis, sem valores reais
├── backend/
│   ├── pyproject.toml   requires-python = ">=3.14"
│   ├── uv.lock
│   ├── .python-version  3.14
│   ├── app/
│   │   ├── main.py      cria o FastAPI e expõe GET /health -> {"status": "ok"}
│   │   ├── settings.py  pydantic-settings
│   │   └── routers/
│   └── tests/
└── frontend/
    ├── .node-version    26
    ├── package.json
    ├── package-lock.json
    ├── vite.config.ts   proxy de /api para http://127.0.0.1:8000
    └── src/
```

As rotas de negócio ficam sob `/api`. O front chama caminhos relativos (`/api/...`), nunca uma URL fixa.

## Comandos (sempre depois do bloco de ambiente)

Criar o backend, dentro de `backend/`:

```powershell
uv init --app --vcs none --no-readme --no-workspace --python 3.14 --name backend .
uv add "fastapi[standard]" pydantic-settings httpx
uv add --dev pytest ruff
```

Criar o front, na raiz do projeto:

```powershell
npm exec --yes -- create-vite@9.3.4 frontend --template react-ts --no-interactive --no-immediate
```

Depois, dentro de `frontend/`: `npm install` e `npm install --save-dev prettier`.

Rodar em desenvolvimento (processos longos: execute em segundo plano):

```powershell
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload   # em backend/
npm run dev -- --host 127.0.0.1 --port 5173                         # em frontend/
```

Dependências novas: `uv add <pacote>` ou `npm install <pacote>`. Mantenha `uv.lock` e `package-lock.json` atualizados.

## Regras para a migração a Linux

- Caminhos relativos à raiz do projeto; em Python, use `pathlib.Path`. Nunca `C:\...` nem `\` em caminhos.
- Abra arquivos com `encoding="utf-8"`.
- Configuração só por variáveis de ambiente (pydantic-settings), inclusive host, porta e URLs.
- Nomes de arquivos e imports com maiúsculas e minúsculas exatas: o Linux diferencia.
- Na aplicação, não use Registro do Windows, COM, `pywin32`, nem chamadas a `cmd` ou `powershell`.
- Biblioteca exclusiva de Windows só com justificativa aprovada pelo dev.
- Scripts do `package.json` e tarefas do projeto devem funcionar nos dois sistemas.
- Horários em UTC na API e no armazenamento.
- Nenhum segredo no código, em commits ou em logs. Valores reais só no `.env` local, que não é versionado.

## O que não fazer

- Não instalar, atualizar ou remover software da máquina (`winget`, `npm install -g`, `pip install` global,
  `uv python install`, `uv self update`).
- Não alterar o PATH persistente, perfis do PowerShell, `.gitconfig`, `.npmrc` ou configurações do VS Code.
- Não encerrar processos por nome (`taskkill /IM`, `Stop-Process -Name`). Encerre só o PID que você iniciou.
- Não desligar a verificação de certificados (`NODE_TLS_REJECT_UNAUTHORIZED=0`, `--trusted-host`, `strict-ssl=false`).
  Em erro de certificado, avise o dev.
- Não mexer em arquivos fora da pasta do projeto.
- Nesta fase, não criar Dockerfile, docker-compose ou CI/CD, e não usar WSL, salvo pedido do dev.
- Não escolher banco de dados nem ORM por conta própria. Se a funcionalidade precisar guardar dados, pergunte antes.

## Antes de dizer que terminou

Rode e confirme que tudo passa:

```powershell
# em backend/
uv run ruff check .
uv run ruff format --check .
uv run pytest -q
# em frontend/
npm run lint
npx prettier --check src
npm run build
```

Teste também `GET http://127.0.0.1:8000/health` com a API rodando, encerre os processos que você iniciou
e diga ao dev, em linguagem simples, o que foi feito e como abrir a aplicação. Se algo falhou, diga o que falhou.
