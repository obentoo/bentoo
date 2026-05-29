# /etc/bash/bashrc.d/30-bentoo-safety.bash
# Bentoo: guardas de segurança para comandos destrutivos (shells interativos).
# Funções (não exportadas) => NÃO afetam scripts/cron/systemd.
# Escape consciente: BENTOO_NO_GUARD=1 <comando>

# Só em shell interativo
[[ $- == *i* ]] || return 0

_bentoo_delay() {
    local label=$1
    [[ -n $BENTOO_NO_GUARD ]] && return 0
    printf '\033[1;31m⚠️  %s\033[0m\n' "$label"

    # Contagem regressiva (Ctrl-C cancela)
    local i
    for ((i=3; i>0; i--)); do
        printf '\r\033[33m   %ds para cancelar (Ctrl-C)... \033[0m' "$i"
        sleep 1 || { printf '\n\033[32mCancelado.\033[0m\n'; return 1; }
    done
    printf '\r\033[K'

    # Confirmação com código alfanumérico de 4 dígitos
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
                --recursive) recursive=1 ;;
                --force) force=1 ;;
                --no-preserve-root) no_preserve=1 ;;
            esac
            continue
        fi
        if [[ -z $end_opts && $a == -* ]]; then
            [[ $a == *[rR]* ]] && recursive=1
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

    # Delay quando recursivo + force
    if [[ -n $recursive && -n $force ]]; then
        _bentoo_delay "rm -rf: ${targets[*]}" || return 1
    fi
    command rm "$@"
}
