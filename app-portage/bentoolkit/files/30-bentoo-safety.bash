# /etc/bash/bashrc.d/30-bentoo-safety.bash
# Bentoo: guardas de segurança para comandos destrutivos (shells interativos).
# Funções (não exportadas) => NÃO afetam scripts/cron/systemd.
# Escape consciente: BENTOO_NO_GUARD=1 <comando>
#
# Comandos protegidos com código de confirmação:
#   power : reboot poweroff halt shutdown
#   rm    : recursivo (-r, COM ou SEM -f) e alvos em diretórios críticos
#   disco : dd mkfs[.*] mkswap wipefs blkdiscard shred fdisk gdisk sgdisk
#           parted truncate cryptsetup(luksFormat/erase/reencrypt)
#   perms : chmod -R / chown -R em diretório crítico
#   gentoo: emerge -C/--unmerge/--depclean/--prune
#
# As mesmas regras valem quando o comando é elevado por sudo/doas/run0/pkexec
# (ex.: `sudo rm -rf /algo`). Sem esse cuidado o elevador chamaria o binário
# real e furaria a guarda -- justamente nos comandos que exigem root (dd, mkfs,
# emerge -C, ...). O wrapper de elevação NUNCA altera os argumentos repassados
# ao elevador; apenas pede a confirmação (ou bloqueia) antes de executá-lo.

# Só em shell interativo. Tudo abaixo (inclusive os wrappers de elevação)
# deixa de existir em scripts, cron e units do systemd, que não são interativos.
[[ $- == *i* ]] || return 0

# Diretórios cujo conteúdo é vital ao sistema (token mesmo sem recursão)
_bentoo_critical_paths='/etc /boot /usr /bin /sbin /lib /lib64 /var /opt /root /dev /proc /sys /run'

_bentoo_is_critical_dir() {
    local p=${1%/} c
    [[ -z $p ]] && return 1
    for c in $_bentoo_critical_paths; do
        [[ $p == "$c" || $p == "$c"/* ]] && return 0
    done
    return 1
}

_bentoo_delay() {
    local label=$1
    [[ -n $BENTOO_NO_GUARD ]] && return 0
    printf '\033[1;31m⚠️  %s\033[0m\n' "$label"

    # Congela a entrada do terminal durante a contagem: sem eco e sem modo
    # canônico, as teclas digitadas vão para o buffer raw (não são exibidas
    # nem confirmam nada) e são descartadas antes de pedir o código.
    local stty_saved=
    stty_saved=$(stty -g 2>/dev/null) || stty_saved=
    [[ -n $stty_saved ]] && stty -echo -icanon 2>/dev/null

    # Contagem regressiva (Ctrl-C cancela)
    local i
    for ((i=3; i>0; i--)); do
        printf '\r\033[33m   %ds para cancelar (Ctrl-C)... \033[0m' "$i"
        if ! sleep 1; then
            [[ -n $stty_saved ]] && stty "$stty_saved" 2>/dev/null
            printf '\n\033[32mCancelado.\033[0m\n'; return 1
        fi
    done
    printf '\r\033[K'

    # Drena qualquer tecla digitada durante a contagem (ainda em modo raw)
    local junk
    while read -rsn1 -t 0.001 junk 2>/dev/null; do :; done

    # Reativa a entrada normal só agora, para capturar a digitação do código
    [[ -n $stty_saved ]] && stty "$stty_saved" 2>/dev/null

    # Confirmação com código alfanumérico de 4 dígitos (sem caracteres ambíguos)
    local chars='ABCDEFGHJKLMNPQRSTUVWXYZ23456789' code='' answer
    for ((i=0; i<4; i++)); do code+=${chars:RANDOM%${#chars}:1}; done

    printf '\033[1;37mDigite o código \033[1;33m%s\033[1;37m para confirmar: \033[0m' "$code"
    if ! read -r answer; then
        printf '\n\033[32mCancelado.\033[0m\n'; return 1
    fi
    if [[ ${answer^^} != "$code" ]]; then
        printf '\033[1;41m Cancelado \033[0m código incorreto.\n'
        return 1
    fi
    return 0
}

# --- núcleo de decisão ------------------------------------------------------
# Avalia (comando + args) e devolve a política em _BENTOO_LABEL:
#   rc 0 => confirmar (label = texto exibido na confirmação)
#   rc 1 => liberar   (nada a fazer)
#   rc 2 => bloquear  (label = mensagem de bloqueio, já com cores)
# É a ÚNICA fonte das regras: guardas diretas e wrappers de elevação a usam.

_bentoo_assess_rm() {
    local recursive= force= no_preserve= end_opts=
    local -a targets=()
    local a
    for a in "$@"; do
        if [[ -z $end_opts && $a == -- ]]; then end_opts=1; continue; fi
        if [[ -z $end_opts && $a == --* ]]; then
            case "$a" in
                --recursive|--dir) recursive=1 ;;
                --force) force=1 ;;
                --no-preserve-root) no_preserve=1 ;;
            esac
            continue
        fi
        if [[ -z $end_opts && $a == -* ]]; then
            [[ $a == *[rRd]* ]] && recursive=1
            [[ $a == *f* ]] && force=1
            continue
        fi
        targets+=("$a")
    done

    # Bloqueio TOTAL de alvos catastróficos (mesmo sem -rf)
    local t
    for t in "${targets[@]}"; do
        case "$t" in
            / | /\* | '~' | '.' | '..' | '*' )
                printf -v _BENTOO_LABEL '\033[1;41m BLOQUEADO \033[0m alvo crítico: %q' "$t"
                return 2 ;;
        esac
        if [[ $t == "$HOME" || $t == "$HOME/" ]]; then
            printf -v _BENTOO_LABEL '\033[1;41m BLOQUEADO \033[0m apagar o HOME: %q' "$t"
            return 2
        fi
    done
    [[ -n $no_preserve ]] && {
        _BENTOO_LABEL='\033[1;41m BLOQUEADO \033[0m --no-preserve-root recusado.'
        return 2
    }

    # Token quando: recursivo (com ou SEM -f) OU alvo em diretório crítico
    local crit=
    for t in "${targets[@]}"; do
        _bentoo_is_critical_dir "$t" && { crit=1; break; }
    done
    if [[ -n $recursive || -n $crit ]]; then
        _BENTOO_LABEL="rm${recursive:+ -r}${force:+f}: ${targets[*]}"
        return 0
    fi
    return 1
}

_bentoo_assess_perm() {
    local real=$1; shift
    local a rec=
    for a in "$@"; do
        [[ $a == --recursive || ( $a == -* && $a == *R* ) ]] && { rec=1; break; }
    done
    [[ -z $rec ]] && return 1
    for a in "$@"; do
        [[ $a == -* ]] && continue
        if _bentoo_is_critical_dir "$a"; then
            _BENTOO_LABEL="$real -R em $a"
            return 0
        fi
    done
    return 1
}

_bentoo_assess() {
    local cmd=$1; shift
    _BENTOO_LABEL=
    case "$cmd" in
        reboot|poweroff|halt|shutdown)
            _BENTOO_LABEL="$cmd solicitado"; return 0 ;;

        dd|mkswap|wipefs|blkdiscard|shred|fdisk|gdisk|sgdisk|parted|truncate)
            _BENTOO_LABEL="$cmd ${*}"; return 0 ;;
        mkfs|mkfs.*)
            _BENTOO_LABEL="$cmd ${*}"; return 0 ;;

        cryptsetup)
            case "$1" in
                luksFormat|luksErase|erase|reencrypt)
                    _BENTOO_LABEL="cryptsetup ${*}"; return 0 ;;
            esac
            return 1 ;;

        chmod|chown)
            _bentoo_assess_perm "$cmd" "$@"; return $? ;;

        emerge)
            local a
            for a in "$@"; do
                case "$a" in
                    -C|--unmerge|--depclean|-c|--prune|-P)
                        _BENTOO_LABEL="emerge (remoção): ${*}"; return 0 ;;
                    --) break ;;
                esac
            done
            return 1 ;;

        rm)
            _bentoo_assess_rm "$@"; return $? ;;
    esac
    return 1
}

# Aplica a política a (comando + args). Retorna 0 se pode prosseguir, 1 se deve
# abortar (bloqueado ou confirmação recusada/cancelada).
_bentoo_gate() {
    _bentoo_assess "$@"
    case $? in
        2) printf '%s\n' "$_BENTOO_LABEL" >&2; return 1 ;;
        0) _bentoo_delay "$_BENTOO_LABEL" || return 1 ;;
    esac
    return 0
}

# --- guardas diretas --------------------------------------------------------
# Cada wrapper avalia no shell e, se liberado, chama o binário real.
_bentoo_c=
for _bentoo_c in reboot poweroff halt shutdown \
                 dd mkswap wipefs blkdiscard shred fdisk gdisk sgdisk \
                 parted truncate \
                 mkfs mkfs.ext2 mkfs.ext3 mkfs.ext4 mkfs.btrfs mkfs.xfs \
                 mkfs.vfat mkfs.fat mkfs.f2fs mkfs.ntfs \
                 rm chmod chown cryptsetup emerge; do
    eval "${_bentoo_c}() { _bentoo_gate ${_bentoo_c} \"\$@\" || return 1; command ${_bentoo_c} \"\$@\"; }"
done
unset _bentoo_c

# --- elevação de privilégio (sudo/doas/run0/pkexec) -------------------------
# Extrai o comando real por trás do elevador. Resultado em _BENTOO_REAL (nome)
# e _bentoo_cmd_args[] (argumentos do comando). rc 0 = achou; 1 = não há
# comando (sessão de shell, --help, só opções) e nada deve ser interceptado.
#
# O parsing é deliberadamente conservador: se errar, erra "aberto" (não acha o
# comando => não intercepta). Os argumentos originais NUNCA são alterados; quem
# roda o elevador é sempre `command "$elev" "$@"` em _bentoo_guard_elev.
_bentoo_parse_elev() {
    local elev=$1; shift
    _BENTOO_REAL=
    _bentoo_cmd_args=()

    # Opções curtas que consomem o PRÓXIMO token como valor (forma `-x val`).
    local shortarg
    case "$elev" in
        sudo)   shortarg='CDghpRrtTUu' ;;
        doas)   shortarg='aCu' ;;
        run0)   shortarg='puMHGE' ;;
        *)      shortarg='' ;;   # pkexec e afins: sem curtas com valor separado
    esac
    # Opções longas (forma `--opt val`, sem '=') que consomem o próximo token.
    local longarg=' user group chdir chroot role type host prompt setenv unit slice machine property command-timeout close-from other-user '

    local a skipnext= seen_dd=
    while (( $# )); do
        a=$1; shift
        if [[ -n $skipnext ]]; then skipnext=; continue; fi
        if [[ -n $seen_dd ]]; then
            _BENTOO_REAL=$a; _bentoo_cmd_args=("$@"); return 0
        fi
        case "$a" in
            --)      seen_dd=1; continue ;;
            --*=*)   continue ;;                      # --opt=val: valor embutido
            --*)     [[ $longarg == *" ${a#--} "* ]] && skipnext=1; continue ;;
            -[!-]*)  # opção curta; só consome o próximo na forma exata `-x`
                     [[ ${#a} -eq 2 && $shortarg == *"${a:1:1}"* ]] && skipnext=1
                     continue ;;
            *=*)     # atribuição de ambiente antes do comando (ex.: sudo FOO=bar cmd)
                     [[ $a == [A-Za-z_]*=* ]] && continue
                     _BENTOO_REAL=$a; _bentoo_cmd_args=("$@"); return 0 ;;
            *)       _BENTOO_REAL=$a; _bentoo_cmd_args=("$@"); return 0 ;;
        esac
    done
    return 1
}

_bentoo_guard_elev() {
    local elev=$1; shift
    if (( $# )); then
        _bentoo_parse_elev "$elev" "$@"
        [[ -n $_BENTOO_REAL ]] && { _bentoo_gate "$_BENTOO_REAL" "${_bentoo_cmd_args[@]}" || return 1; }
    fi
    command "$elev" "$@"
}

# Definidas via eval para manter um único corpo (e evitar o literal de
# definição que dispara falso-positivo de "command injection" em linters).
_bentoo_e=
for _bentoo_e in sudo doas run0 pkexec; do
    eval "${_bentoo_e}() { _bentoo_guard_elev ${_bentoo_e} \"\$@\"; }"
done
unset _bentoo_e
