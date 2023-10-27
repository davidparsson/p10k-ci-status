#!/usr/bin/env zsh
# TODO:
# - [x] Asynchronous execution
#   - [ ] Properly refresh terminal
#   - [ ] Support all states
#   - [ ] Prompt updating
#   - [x] Proper caching per repo & branch
#   - [ ] Check commit instead of branch?
# - [x] Fall-back: hub ci-status $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
#   - [ ] Better colors
# - [ ] Allow configuration
# - [ ] Add a readme
# - [ ] Optimizations:
#   - [ ] Add a timeout to not check to often
#   - [ ] Only update when state changes
#   - [ ] Prevent memory leaks in arrays
#

function _ci_status() {
    local hub_output hub_exit_code state
    local repo_root="$1"
    local repo_branch="$2"
    local upstream='0'

    hub_output="$(cd $repo_root; hub ci-status 2> /dev/null)"
    hub_exit_code=$?

    if [[ $hub_output == "no status" && $hub_exit_code == 3 ]]; then
        hub_output="$(cd $repo_root; hub ci-status $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null))"
        hub_exit_code=$?
        upstream='1'
    fi

    state=UNKNOWN
    case $hub_exit_code in
        0)
            if [[ $hub_output == "neutral" ]]; then
                state=NEUTRAL
            else
                state=SUCCESS
            fi
            ;;
        1)
            if [[ $hub_output == "action_required" ]]; then
                state=ACTION_REQUIRED
            elif [[ $hub_output == "cancelled" || $hub_output == "timed_out" ]]; then
                state=CANCELLED
            elif [[ $hub_output == "failure" || $hub_output == "error" ]]; then
                state=FAILURE
            elif [[ $hub_output == "" ]]; then
                state=UNAVAILABLE
            fi
            ;;
        2)
            state=BUILDING
            ;;
        3)
            state=NO_STATUS
            ;;
    esac

    echo "${repo_root}@${repo_branch}"
    echo $state
    echo $upstream
}

function _ci_status_callback() {
    local working_directory
    local ci_status
    local return_values=(${(f)3})
    _P9K_CI_STATUS_STATE[$return_values[1]]=$return_values[2]
    _P9K_CI_STATUS_UPSTREAM[$return_values[1]]=$return_values[3]
}

typeset -g -A _P9K_CI_STATUS_STATE
typeset -g -A _P9K_CI_STATUS_UPSTREAM

async_init
async_stop_worker _p10k_ci_status_worker
async_start_worker _p10k_ci_status_worker -n
async_unregister_callback _p10k_ci_status_worker
async_register_callback _p10k_ci_status_worker _ci_status_callback

function prompt_ci_status() {
    (( $+commands[hub] )) || return

    local repo_root="$(git rev-parse --show-toplevel 2> /dev/null)"
    [[ $? != 0 || -z $repo_root ]] && return

    local repo_branch="$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"
    [[ $? != 0 || -z $repo_branch ]] && return

    async_job _p10k_ci_status_worker _ci_status $repo_root $repo_branch

    local state="$_P9K_CI_STATUS_STATE[${repo_root}@${repo_branch}]"
    local upstream="$_P9K_CI_STATUS_UPSTREAM[${repo_root}@${repo_branch}]"
    local icon foreground

    case $state in
        "SUCCESS")
            icon='✔︎'
            foreground=green
            ;;
        "FAILURE")
            icon='✖︎'
            foreground=red
            ;;
        "BUILDING")
            icon='•'
            foreground=yellow
            ;;
        "ACTION_REQUIRED")
            icon='▴'
            foreground=red
            ;;
        "CANCELLED")
            icon='✖︎'
            foreground=yellow
            ;;
        "NEUTRAL")
            icon='✔︎'
            foreground=blue
            ;;
    esac

    if [[ $upstream == '1' ]]; then
        foreground='%F{242}'
    fi

    if [ ! -z $icon ]; then
        p10k segment -s $state -i $icon -f $foreground -t $icon
    fi
}
