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

# Só em shell interativo
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

# Wrapper genérico: atrasa e confirma antes de executar o binário real
_bentoo_guard_cmd() {
    local real=$1; shift
    _bentoo_delay "$real ${*}" || return 1
    command "$real" "$@"
}

# --- reboot / poweroff / halt ---------------------------------------------
_bentoo_guard_power() {
    local real=$1; shift
    _bentoo_delay "$real solicitado" || return 1
    command "$real" "$@"
}
reboot()   { _bentoo_guard_power reboot   "$@"; }
poweroff() { _bentoo_guard_power poweroff "$@"; }
halt()     { _bentoo_guard_power halt     "$@"; }
shutdown() { _bentoo_guard_power shutdown "$@"; }

# --- rm --------------------------------------------------------------------
rm() {
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
                printf '\033[1;41m BLOQUEADO \033[0m alvo crítico: %q\n' "$t" >&2
                return 1 ;;
        esac
        if [[ $t == "$HOME" || $t == "$HOME/" ]]; then
            printf '\033[1;41m BLOQUEADO \033[0m apagar o HOME: %q\n' "$t" >&2
            return 1
        fi
    done
    [[ -n $no_preserve ]] && {
        printf '\033[1;41m BLOQUEADO \033[0m --no-preserve-root recusado.\n' >&2
        return 1
    }

    # Token quando: recursivo (com ou SEM -f) OU alvo em diretório crítico
    local crit=
    for t in "${targets[@]}"; do
        _bentoo_is_critical_dir "$t" && { crit=1; break; }
    done
    if [[ -n $recursive || -n $crit ]]; then
        _bentoo_delay "rm${recursive:+ -r}${force:+f}: ${targets[*]}" || return 1
    fi
    command rm "$@"
}

# --- disco / sistema de arquivos -------------------------------------------
dd()         { _bentoo_guard_cmd dd         "$@"; }
mkswap()     { _bentoo_guard_cmd mkswap     "$@"; }
wipefs()     { _bentoo_guard_cmd wipefs     "$@"; }
blkdiscard() { _bentoo_guard_cmd blkdiscard "$@"; }
shred()      { _bentoo_guard_cmd shred      "$@"; }
fdisk()      { _bentoo_guard_cmd fdisk      "$@"; }
gdisk()      { _bentoo_guard_cmd gdisk      "$@"; }
sgdisk()     { _bentoo_guard_cmd sgdisk     "$@"; }
parted()     { _bentoo_guard_cmd parted     "$@"; }
truncate()   { _bentoo_guard_cmd truncate   "$@"; }

# mkfs e suas variantes mkfs.<fs> (nomes de função com ponto: ok no bash)
_bentoo_mk=
for _bentoo_mk in mkfs mkfs.ext2 mkfs.ext3 mkfs.ext4 mkfs.btrfs mkfs.xfs \
                  mkfs.vfat mkfs.fat mkfs.f2fs mkfs.ntfs; do
    eval "${_bentoo_mk}() { _bentoo_guard_cmd ${_bentoo_mk} \"\$@\"; }"
done
unset _bentoo_mk

# cryptsetup: só os subcomandos destrutivos (luksOpen/status etc. passam)
cryptsetup() {
    case "$1" in
        luksFormat|luksErase|erase|reencrypt)
            _bentoo_guard_cmd cryptsetup "$@" ;;
        *)
            command cryptsetup "$@" ;;
    esac
}

# --- permissões recursivas em diretório crítico ---------------------------
_bentoo_guard_perm() {
    local real=$1; shift
    local a rec=
    for a in "$@"; do
        [[ $a == --recursive || ( $a == -* && $a == *R* ) ]] && { rec=1; break; }
    done
    if [[ -n $rec ]]; then
        for a in "$@"; do
            [[ $a == -* ]] && continue
            if _bentoo_is_critical_dir "$a"; then
                _bentoo_delay "$real -R em $a" || return 1
                break
            fi
        done
    fi
    command "$real" "$@"
}
chmod() { _bentoo_guard_perm chmod "$@"; }
chown() { _bentoo_guard_perm chown "$@"; }

# --- emerge: remoção de pacotes -------------------------------------------
emerge() {
    local a destructive=
    for a in "$@"; do
        case "$a" in
            -C|--unmerge|--depclean|-c|--prune|-P) destructive=1; break ;;
            --) break ;;
        esac
    done
    if [[ -n $destructive ]]; then
        _bentoo_delay "emerge (remoção): ${*}" || return 1
    fi
    command emerge "$@"
}
