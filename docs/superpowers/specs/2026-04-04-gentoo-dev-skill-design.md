# Design Spec: gentoo-dev Skill

**Data:** 2026-04-04
**Status:** Draft
**Localização:** `~/.claude/skills/gentoo-dev/`

## Objetivo

Skill para desenvolvimento completo no ecossistema Gentoo Linux: criar, editar, bumpar e manter ebuilds e overlays. Totalmente automática com review final. Genérica para qualquer overlay com perfil de convenções intercambiável (bentoo como perfil padrão).

## Decisões de Design

| Decisão | Escolha | Razão |
|---------|---------|-------|
| Localização | `~/.claude/skills/` (pessoal) | Disponível em qualquer projeto/overlay |
| Automação | Total, review no final | Fluxo rápido sem interrupções |
| Escopo | Genérica + perfil bentoo | Reutilizável em qualquer overlay |
| Arquitetura | Sub-agentes especializados | Modelos calibrados por tarefa |
| Hooks | 3 (manifest warning, quick-lint, delete reminder) | Feedback imediato, previne erros comuns |

## Estrutura de Arquivos (28 arquivos)

```
~/.claude/skills/gentoo-dev/
├── SKILL.md                              # Orquestrador (~450 linhas)
├── agents/
│   ├── ebuild-creator.md                 # Criar ebuilds (inherit, maxTurns: 50)
│   ├── ebuild-editor.md                  # Alterar ebuilds (inherit, maxTurns: 50)
│   ├── ebuild-bumper.md                  # Bump de versão (sonnet, maxTurns: 30)
│   ├── overlay-maintainer.md             # Limpeza em lote (sonnet, maxTurns: 40)
│   └── qa-checker.md                     # Validação QA (haiku, maxTurns: 20)
├── references/
│   ├── eclass-guide.md                   # Eclasses por categoria e linguagem
│   ├── dependency-syntax.md              # Sintaxe de dependências
│   ├── language-ecosystems.md            # Padrões Go/Rust/Java/Python/Ruby/Perl
│   └── gotchas.md                        # Armadilhas críticas
├── scripts/
│   ├── detect-overlay.sh                 # Auto-detecta overlay (dynamic context)
│   └── quick-lint.sh                     # Lint leve pós-escrita de ebuild
├── assets/
│   ├── profiles/
│   │   ├── bentoo.md                     # Convenções overlay bentoo
│   │   └── default.md                    # Convenções genéricas Gentoo
│   └── templates/
│       ├── source-autotools.ebuild       # Template: ./configure + make
│       ├── source-cmake.ebuild           # Template: CMake
│       ├── source-meson.ebuild           # Template: Meson
│       ├── source-cargo.ebuild           # Template: Rust/Cargo
│       ├── source-go.ebuild              # Template: Go modules
│       ├── source-python.ebuild          # Template: Python PEP 517
│       ├── binary-deb.ebuild             # Template: binário de .deb
│       ├── binary-direct.ebuild          # Template: binário download direto
│       ├── binary-appimage.ebuild        # Template: AppImage repack
│       ├── live-snapshot.ebuild          # Template: dual live/snapshot
│       ├── gstreamer-plugin.ebuild       # Template: plugin GStreamer
│       └── metadata.xml                  # Template: metadata de pacote
└── evals/
    ├── evals.json                        # Casos de teste da skill
    └── trigger-queries.json              # Queries de ativação/não-ativação
```

---

## SKILL.md -- Frontmatter

```yaml
---
name: gentoo-dev
description: >
  Develop and maintain Gentoo ebuilds and overlays. Use when creating new
  ebuilds, editing existing ebuilds, bumping package versions, cleaning old
  ebuilds, running QA checks, generating Manifests, managing overlay
  structure, or working with eclasses. Triggers on: "create ebuild",
  "new package", "bump version", "update ebuild", "edit ebuild",
  "add USE flag", "fix dependencies", "clean overlay", "remove old versions",
  "run QA", "check ebuild", "generate Manifest", "criar ebuild",
  "atualizar pacote", "nova versão", "limpar overlay", "verificar QA".
  Also triggers when working with .ebuild files, metadata.xml, Manifest
  files, eclass files, or any Gentoo packaging task.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
effort: high
compatibility: >
  Requires bash shell. Benefits from: ebuild command (sys-apps/portage),
  pkgcheck (dev-util/pkgcheck), pkgdev (dev-util/pkgdev). Falls back to
  manual validation if tools unavailable.
argument-hint: "[create|edit|bump|clean|qa] [category/package] [version]"
metadata:
  author: lucascouts
  version: "1.0"
hooks:
  PostToolUse:
    - matcher: "Write|Edit"
      if: "Write(*.ebuild)|Edit(*.ebuild)"
      type: command
      command: >
        EBUILD="$TOOL_INPUT_FILE_PATH"
        && DIR=$(dirname "$EBUILD")
        && if grep -q 'SRC_URI' "$EBUILD" 2>/dev/null; then
          echo "[gentoo-dev] Manifest may need regeneration for $(basename $DIR)";
        fi
    - matcher: "Write"
      if: "Write(*.ebuild)"
      type: command
      command: >
        bash "${CLAUDE_SKILL_DIR}/scripts/quick-lint.sh"
        "$TOOL_INPUT_FILE_PATH"
    - matcher: "Bash"
      if: "Bash(rm *.ebuild)|Bash(git rm *.ebuild)"
      type: command
      command: >
        echo "[gentoo-dev] Ebuild removed. Regenerate the Manifest
        to clean stale DIST entries."
  Stop:
    - type: prompt
      prompt: >
        Check if any .ebuild file was written or edited during this session.
        If so, verify that a Manifest was regenerated for each affected
        package directory. If a Manifest regeneration is missing, respond
        {"decision": "deny", "reason": "Manifest not regenerated for modified ebuild"}.
        Otherwise respond {"decision": "allow"}.
---
```

## SKILL.md -- Body Structure

### Seção 1: Auto-Detected Overlay Context

```markdown
## Overlay Context

!`bash ${CLAUDE_SKILL_DIR}/scripts/detect-overlay.sh 2>/dev/null || echo "No overlay detected"`
```

O script `detect-overlay.sh` lê `metadata/layout.conf`, `profiles/repo_name`, e retorna:
- Nome do repositório
- Masters
- thin-manifests sim/não
- Caminho absoluto do overlay
- Perfil recomendado (bentoo vs default)

### Seção 2: Command Routing

```
$ARGUMENTS parsing:

(empty) or unrecognized text
  → Analisa contexto e decide automaticamente

"create [category/package]" or "criar" or "new" or "novo"
  → CREATE mode → despacha ebuild-creator

"edit [category/package]" or "editar" or "alterar" or "modificar"
  → EDIT mode → despacha ebuild-editor

"bump [category/package] [version]" or "atualizar" or "update"
  → BUMP mode → despacha ebuild-bumper

"clean" or "limpar" or "maintain" or "manter"
  → MAINTAIN mode → despacha overlay-maintainer

"qa [category/package]" or "check" or "verificar" or "validar"
  → QA mode → despacha qa-checker
```

Quando chamado sem argumentos e sem `/gentoo-dev`, o SKILL.md analisa a intenção do usuário pelo contexto natural da conversa e roteia para o sub-agente adequado.

### Seção 3: Profile Loading

Baseado no `repo_name` detectado:
- Se `bentoo` → carrega `assets/profiles/bentoo.md`
- Caso contrário → carrega `assets/profiles/default.md`

O conteúdo do perfil é passado como contexto ao sub-agente despachado.

### Seção 4: Dispatch Protocol

Para cada sub-agente, o orquestrador prepara um prompt com:
1. **Tarefa** -- o que fazer (criar, editar, bumpar, limpar, validar)
2. **Pacote** -- categoria/nome e versão se aplicável
3. **Perfil** -- convenções do overlay atual
4. **Gotchas** -- instrução para carregar `references/gotchas.md`
5. **Template** -- qual template usar (para CREATE mode)
6. **Contexto extra** -- argumentos do usuário, ebuilds existentes para referência

### Seção 5: Gotchas (inline)

As armadilhas mais críticas ficam inline no SKILL.md para que todo sub-agente despachado as receba:

1. `eapply_user` obrigatório em `src_prepare` overridden -- chamar `default` ou `eapply_user` explicitamente
2. `|| die` após todo comando que pode falhar em ebuilds
3. KEYWORDS vazio em live ebuilds (PV=9999)
4. `S=` deve corresponder ao diretório extraído do tarball
5. SRC_URI rename com `->` quando nome upstream não é informativo
6. `QA_PREBUILT="*"` e `RESTRICT="strip"` para pacotes binários
7. Copyright header na primeira linha, EAPI na primeira linha não-comentário
8. thin-manifests -- Manifest só contém DIST entries
9. `default` em src_prepare aplica PATCHES array + eapply_user automaticamente
10. Usar `MY_P`/`MY_PN` quando naming upstream difere do Gentoo

### Seção 6: Reference Loading Conditions

```markdown
## References (progressive disclosure)

- Read `references/eclass-guide.md` when choosing or configuring an eclass
- Read `references/dependency-syntax.md` when building DEPEND/RDEPEND/BDEPEND blocks
- Read `references/language-ecosystems.md` when the package uses Go, Rust, Java, Python, Ruby, Perl, or is an Electron app
- Read `references/gotchas.md` for the full gotchas list with examples (summary is inline above)
```

---

## Sub-agentes

### ebuild-creator (agents/ebuild-creator.md)

```yaml
---
name: ebuild-creator
description: >
  Creates new Gentoo ebuilds from scratch. Analyzes upstream source to
  determine build system, dependencies, and license. Selects appropriate
  template and generates ebuild, metadata.xml, and Manifest.
model: inherit
tools: Read, Write, Edit, Bash, Glob, Grep
maxTurns: 50
effort: max
---
```

**Protocolo de execução:**

1. **Análise upstream** -- Identifica: sistema de build (cmake, meson, autotools, cargo, go, python), licença, homepage, dependências, versão
2. **Seleção de template** -- Escolhe de `assets/templates/` baseado no tipo detectado
3. **Geração de ebuild** -- Preenche template com dados reais, adaptando ao perfil do overlay
4. **Geração de metadata.xml** -- Cria a partir do template com maintainer, USE flags, upstream info
5. **Criação de diretório** -- `category/package/` com `files/` se necessário
6. **Manifest** -- Executa `ebuild <path> manifest` para gerar checksums
7. **Relatório** -- Lista arquivos criados e decisões tomadas

**Carregamento de referências:**
- Sempre: `references/gotchas.md` (via contexto do orquestrador)
- Se precisa escolher eclass: `references/eclass-guide.md`
- Se linguagem específica: `references/language-ecosystems.md`
- Se deps complexas: `references/dependency-syntax.md`

### ebuild-editor (agents/ebuild-editor.md)

```yaml
---
name: ebuild-editor
description: >
  Modifies existing Gentoo ebuilds with structural awareness. Ensures
  consistency across IUSE, dependencies, metadata.xml, and phase functions
  when making changes.
model: inherit
tools: Read, Write, Edit, Bash, Glob, Grep
maxTurns: 50
effort: max
---
```

**Protocolo de execução:**

1. **Leitura** -- Lê ebuild atual, identifica EAPI, eclasses, variáveis, fases
2. **Análise de impacto** -- Determina o que a alteração afeta (USE flag nova? dep nova? patch novo?)
3. **Aplicação** -- Faz a modificação mantendo estilo e convenções
4. **Verificação de consistência:**
   - USE flag nova → adicionada em IUSE + deps condicionais + metadata.xml
   - Dependência nova → tipo correto (DEPEND/RDEPEND/BDEPEND)
   - Patch novo → arquivo em `files/`, referência em PATCHES ou src_prepare
   - Alteração de SRC_URI → Manifest precisa regenerar
5. **Manifest** -- Regenera se SRC_URI mudou
6. **Relatório** -- Diff das alterações + checklist de consistência

### ebuild-bumper (agents/ebuild-bumper.md)

```yaml
---
name: ebuild-bumper
description: >
  Bumps Gentoo ebuild versions. Copies previous ebuild as base, updates
  version, commit hash, SRC_URI, and regenerates Manifest. Handles
  snapshot (_p<date>) and standard version bumps.
model: sonnet
tools: Read, Write, Edit, Bash, Glob, Grep
maxTurns: 30
effort: high
---
```

**Protocolo de execução:**

1. **Identificação** -- Localiza ebuild da versão anterior mais recente
2. **Cópia** -- `cp <old>.ebuild <new>.ebuild` com nome de versão atualizado
3. **Edição** -- Atualiza:
   - `GIT_COMMIT=` se snapshot
   - `SRC_URI` se URL mudou
   - `S=` se diretório de sources muda
   - Sufixo `_p<YYYYMMDD>` se snapshot datado
4. **Remoção** -- Remove ebuild(s) antigo(s) se solicitado pelo usuário
5. **Manifest** -- Regenera via `ebuild <path> manifest`
6. **Relatório** -- `versão_antiga → versão_nova`, arquivos alterados/removidos

### overlay-maintainer (agents/overlay-maintainer.md)

```yaml
---
name: overlay-maintainer
description: >
  Maintains Gentoo overlay health. Removes old ebuild versions, regenerates
  Manifests in batch, cleans stale DIST entries, and reports overlay status.
model: sonnet
tools: Read, Write, Edit, Bash, Glob, Grep
maxTurns: 40
effort: high
---
```

**Protocolo de execução:**

1. **Scan** -- Itera sobre categorias/pacotes identificando:
   - Pacotes com múltiplas versões (candidatos a limpeza)
   - Manifests com entries órfãs
   - metadata.xml faltando
   - Ebuilds sem KEYWORDS
2. **Ação** -- Conforme instrução:
   - Remove ebuilds obsoletos
   - Regenera Manifests
   - Cria metadata.xml faltantes
3. **Relatório** -- Pacotes afetados, ações tomadas, estado final

### qa-checker (agents/qa-checker.md)

```yaml
---
name: qa-checker
description: >
  Validates Gentoo ebuild quality. Checks EAPI, copyright, die statements,
  eapply_user, KEYWORDS, IUSE consistency, metadata.xml, and Manifest.
  Runs pkgcheck if available.
model: haiku
tools: Read, Bash, Glob, Grep
maxTurns: 20
effort: medium
---
```

**Protocolo de execução:**

1. **Recebe** -- Caminho(s) de ebuild(s) para validar
2. **Lint manual** -- Verifica (independente de ferramentas externas):
   - EAPI=8 declarado
   - Copyright header presente e atual
   - `|| die` após comandos falíveis
   - `eapply_user` em src_prepare overridden
   - KEYWORDS vazio em live ebuilds
   - Consistência IUSE vs uso real
   - metadata.xml presente
   - Manifest presente e cobrindo todos os SRC_URI
   - SLOT declarado
   - LICENSE declarado
3. **pkgcheck** -- Se disponível: `pkgcheck scan <path>`
4. **Relatório** -- Imprime no stdout lista de issues com severidade (ERROR/WARNING/INFO). Não escreve arquivos.

---

## Scripts

### scripts/detect-overlay.sh

Detecta o overlay Gentoo no diretório atual:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Walk up to find overlay root (has metadata/layout.conf)
DIR="${1:-.}"
DIR="$(cd "$DIR" && pwd)"

while [[ "$DIR" != "/" ]]; do
    if [[ -f "$DIR/metadata/layout.conf" && -f "$DIR/profiles/repo_name" ]]; then
        REPO_NAME=$(cat "$DIR/profiles/repo_name" | tr -d '[:space:]')
        echo "=== Gentoo Overlay Detected ==="
        echo "Path: $DIR"
        echo "Name: $REPO_NAME"
        echo ""
        echo "=== layout.conf ==="
        cat "$DIR/metadata/layout.conf"
        echo ""
        if [[ -f "$DIR/profiles/package.mask" ]]; then
            echo "=== package.mask ==="
            cat "$DIR/profiles/package.mask"
            echo ""
        fi
        echo "=== Profile ==="
        echo "Recommended: $REPO_NAME"
        echo "=== Categories ==="
        ls -d "$DIR"/*/ 2>/dev/null | grep -v -E '(metadata|profiles|eclass)' \
            | xargs -I{} basename {} | sort | tr '\n' ' '
        echo ""
        if [[ -d "$DIR/eclass" ]]; then
            echo "=== Custom Eclasses ==="
            ls "$DIR/eclass/"*.eclass 2>/dev/null | xargs -I{} basename {} | sort
        fi
        exit 0
    fi
    DIR="$(dirname "$DIR")"
done

echo "No Gentoo overlay detected in current directory tree."
```

### scripts/quick-lint.sh

Lint leve para ebuilds (executado pelo hook PostToolUse):

```bash
#!/usr/bin/env bash
set -euo pipefail

EBUILD="$1"
ERRORS=0
WARNINGS=0

if [[ ! -f "$EBUILD" ]]; then
    echo "File not found: $EBUILD" >&2
    exit 0
fi

BASENAME=$(basename "$EBUILD")

# Check EAPI
if ! grep -q '^EAPI=' "$EBUILD"; then
    echo "[ERROR] Missing EAPI declaration"
    ERRORS=$((ERRORS + 1))
fi

# Check copyright header
if ! head -1 "$EBUILD" | grep -q '^# Copyright'; then
    echo "[ERROR] Missing copyright header on line 1"
    ERRORS=$((ERRORS + 1))
fi

# Check eapply_user in overridden src_prepare
if grep -q 'src_prepare()' "$EBUILD"; then
    if ! grep -q 'eapply_user\|default' "$EBUILD"; then
        echo "[ERROR] src_prepare() overridden without eapply_user or default"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check KEYWORDS empty for live ebuilds
if echo "$BASENAME" | grep -q '9999'; then
    if grep -q '^KEYWORDS="..*"' "$EBUILD"; then
        echo "[ERROR] Live ebuild (9999) must have empty KEYWORDS"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check SLOT declared
if ! grep -q '^SLOT=' "$EBUILD"; then
    echo "[WARNING] Missing SLOT declaration"
    WARNINGS=$((WARNINGS + 1))
fi

# Check LICENSE declared
if ! grep -q '^LICENSE=' "$EBUILD"; then
    echo "[WARNING] Missing LICENSE declaration"
    WARNINGS=$((WARNINGS + 1))
fi

# Summary
if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "[gentoo-dev] $ERRORS error(s), $WARNINGS warning(s) in $BASENAME"
    exit 2  # Block on errors
elif [[ $WARNINGS -gt 0 ]]; then
    echo "[gentoo-dev] $WARNINGS warning(s) in $BASENAME"
fi

exit 0
```

---

## Profiles

### assets/profiles/bentoo.md

Convenções específicas do overlay bentoo:

- **Repositório:** `bentoo`, masters = `gentoo`
- **Manifests:** thin-manifests = true, sign-manifests = false
- **Snapshots:** Usar sufixo `_p<YYYYMMDD>` com variável `GIT_COMMIT=` ou `COMMIT=`
- **SRC_URI:** Sempre renomear com `-> ${P}.tar.gz` quando tarball upstream não é informativo
- **KEYWORDS:** Primário `~amd64`, secundário `~arm64` quando aplicável
- **Copyright:** `# Copyright 1999-<ano_atual> Gentoo Authors`
- **Live ebuilds:** Dual-mode com `if [[ ${PV} == 9999 ]]` para suportar live e snapshot
- **Binários:** Instalar em `/opt/<nome>/`, usar `QA_PREBUILT="*"`, `RESTRICT="bindist mirror strip"`
- **Binários .deb:** `inherit unpacker`, usar `unpack` default
- **Desktop apps:** Instalar ícones com `newicon -s`, criar .desktop files, bash/zsh completions
- **GStreamer:** Usar eclass customizada `gstreamer-meson` (suporta meson.options)
- **EAPI:** Sempre EAPI=8

### assets/profiles/default.md

Convenções genéricas para qualquer overlay Gentoo:

- Detectar configuração via `metadata/layout.conf`
- Seguir Gentoo devmanual estritamente
- EAPI=8
- KEYWORDS `~amd64` como default
- Copyright `# Copyright 1999-<ano_atual> Gentoo Authors`
- Preferir `default` em src_prepare ao invés de chamar eapply_user manualmente
- SRC_URI com rename `->` apenas quando necessário
- Testar com `ebuild <path> manifest clean unpack compile install`

---

## Templates (resumo)

Cada template segue o formato:
- Copyright header + GPLv2
- EAPI=8
- Placeholders com `@@VARIABLE@@`
- Comentários inline explicando decisões
- Dependências mínimas típicas do tipo

| Template | Herda | Fases overridden | Padrão-chave |
|----------|-------|------------------|--------------|
| source-autotools | -- | src_configure, src_install | econf, emake |
| source-cmake | cmake | -- (defaults do eclass) | mycmakeargs |
| source-meson | meson | -- (defaults do eclass) | emesonargs |
| source-cargo | cargo | src_unpack, src_compile | CRATES, ECARGO_VENDOR |
| source-go | go-module | src_compile, src_install | ego build, ldflags |
| source-python | distutils-r1 | -- (defaults do eclass) | DISTUTILS_USE_PEP517 |
| binary-deb | unpacker xdg | src_install | /opt/, QA_PREBUILT |
| binary-direct | -- | src_install | exeinto, newexe |
| binary-appimage | -- | src_install | /opt/, wrapper script |
| live-snapshot | git-r3 | src_unpack | if PV==9999, GIT_COMMIT |
| gstreamer-plugin | gstreamer-meson | -- | plugin extraction |
| metadata.xml | -- | -- | maintainer, USE flags |

---

## Evals

### evals/trigger-queries.json

**Should-trigger (~12 queries):**
- "create an ebuild for package X"
- "bump mesa to version 26.0.5"
- "add wayland USE flag to cursor ebuild"
- "clean old versions from dev-util/glslang"
- "run QA check on the new ebuild"
- "criar ebuild para o pacote Y"
- "atualizar brave-browser para 1.89"
- "gerar Manifest para media-libs/mesa"
- "remover versões antigas do overlay"
- "editar as dependências do qemu"
- "add a patch to fix build with gcc-15"
- "write metadata.xml for new package"

**Should-not-trigger (~10 queries):**
- "explain what USE flags are"
- "how does Portage work?"
- "compile this C++ file"
- "create a Python script"
- "fix this JavaScript bug"
- "what is an eclass?"
- "install mesa on my system"
- "run emerge --sync"
- "help me configure make.conf"
- "review this pull request"

### evals/evals.json

**Formato de cada eval:**
```json
{
  "name": "create-cmake-ebuild",
  "prompt": "Create an ebuild for dev-util/foo-1.0 that uses CMake",
  "assertions": [
    "File dev-util/foo/foo-1.0.ebuild exists",
    "Ebuild contains 'inherit cmake'",
    "Ebuild contains 'EAPI=8'",
    "Ebuild contains copyright header on line 1",
    "File dev-util/foo/metadata.xml exists",
    "metadata.xml contains <pkgmetadata>"
  ]
}
```

**Casos de teste (6):**

1. **Create source ebuild** -- "Create an ebuild for dev-util/foo-1.0 that uses CMake"
   - Assertions: ebuild exists, inherits cmake, EAPI=8, copyright, metadata.xml exists, Manifest exists
2. **Create binary ebuild** -- "Create an ebuild for app-editors/bar-2.0 from upstream .deb"
   - Assertions: inherits unpacker, QA_PREBUILT="*", RESTRICT contains "strip", installs to /opt/
3. **Bump version** -- "Bump dev-util/glslang from 1.4.341.0 to 1.4.342.0"
   - Assertions: new ebuild file exists with correct version, old version content preserved as base, Manifest regenerated
4. **Edit ebuild** -- "Add wayland USE flag to app-editors/cursor"
   - Assertions: IUSE contains "wayland", RDEPEND/DEPEND has wayland conditional, metadata.xml has wayland flag description
5. **Clean overlay** -- "Remove old versions of app-editors/cursor, keep only latest"
   - Assertions: only latest ebuild remains, Manifest updated, no stale DIST entries
6. **QA check** -- "Run QA check on dev-util/glslang"
   - Assertions: output contains severity levels (ERROR/WARNING/INFO), output mentions specific checks performed

---

## Token Budget

| Componente | Tokens | Quando |
|------------|--------|--------|
| SKILL.md metadata | ~100 | Sempre (startup) |
| SKILL.md body (inclui gotchas inline) | ~3.500 | Na ativação |
| detect-overlay.sh output | ~200 | Na ativação (dynamic context) |
| Agent dispatch overhead | ~300 | Quando sub-agente é despachado |
| Sub-agente prompt | ~2.000 | Quando despachado |
| Perfil do overlay | ~500 | Passado ao sub-agente como contexto |
| Referência (cada) | ~1.500 | Sob demanda dentro do sub-agente |
| Template (cada) | ~200 | Quando necessário |

**Fluxo típico (ex: bump de versão):**
- Ativação: 100 + 3.500 + 200 = **3.800**
- Dispatch: 300 + 2.000 + 500 (perfil) = **2.800**
- Referência sob demanda: +1.500 (se necessário)
- **Total sem referência: ~6.600**
- **Total com 1 referência: ~8.100**

---

## Riscos e Mitigações

| Risco | Mitigação |
|-------|-----------|
| `ebuild manifest` falha (sem portage) | QA checker detecta; manual fallback documentado |
| Sub-agente gera ebuild com erros | Hook quick-lint.sh bloqueia ERRORs; QA checker como step final |
| Template desatualizado | Templates são referência, não cópia literal; agente adapta |
| Overlay sem perfil configurado | Fallback para `default.md` |
| Sub-agente não pode chamar outro sub-agente | Design garante que cada fluxo é resolvido por um único sub-agente |
