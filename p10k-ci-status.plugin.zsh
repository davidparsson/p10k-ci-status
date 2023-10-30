#!/usr/bin/env zsh
# TODO:
# - [x] Asynchronous execution
#   - [ ] Support all states
#   - [x] Update the prompt once the async job is completed
#   - [x] Proper caching per repo & branch
#     - [ ] Check commit instead of branch?
# - [x] Fall-back: hub ci-status $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
#   - [ ] Better colors - does Warp have another theme?
# - [ ] Allow configuration. Probably done with states and colors.
# - [ ] Add a readme
# - [ ] Optimizations:
#   - [x] Add a timeout to not check to often
#   - [ ] Only update when state changes
#   - [ ] Prevent memory leaks in arrays
#   - [ ] Check how concurrency works for async. Will runs be restarted if they are already running?
#

function _ci_status_compute() {
    # Check if it is time to call the background task
    (( EPOCHREALTIME >= _ci_status_next_time )) || return
    # Start background task
    async_job _p10k_ci_status_worker _ci_status_async $@
    # Set time for next execution
    _ci_status_next_time=$((EPOCHREALTIME + 10))
}

function _ci_status_async() {
    local hub_output hub_exit_code state
    local repo_root="$1"
    local repo_commit="$2"
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

    local symbol foreground
    case $state in
        "SUCCESS")
            symbol='✔︎'
            foreground="%{$fg[green]%}"
            ;;
        "FAILURE")
            symbol='✖︎'
            foreground="%{$fg[red]%}"
            ;;
        "BUILDING")
            symbol='•'
            foreground="%{$fg[yellow]%}"
            ;;
        "ACTION_REQUIRED")
            symbol='▴'
            foreground="%{$fg[red]%}"
            ;;
        "CANCELLED")
            symbol='✖︎'
            foreground="%{$fg[yellow]%}"
            ;;
        "NEUTRAL")
            symbol='✔︎'
            foreground="%{$fg[cyan]%}"
            ;;
    esac

    if [[ $upstream == '1' ]]; then
        foreground="%{$fg[gray]%}"
    fi

    echo "${repo_root}@${repo_commit}"
    echo $state
    echo $symbol
    echo $foreground
}

function _ci_status_callback() {
    local return_values=(${(f)3})

    local cache_key=$return_values[1]
    local state=$return_values[2]
    local symbol=$return_values[3]
    local foreground=$return_values[4]

    _P9K_CI_STATUS_STATE[$cache_key]=$state
    _P9K_CI_STATUS_SYMBOL[$cache_key]="$foreground$symbol"

    p10k display -r
}

typeset -g -A _P9K_CI_STATUS_STATE
typeset -g -A _P9K_CI_STATUS_SYMBOL
typeset -g _p9k_ci_status_cache_key
typeset -gF _ci_status_next_time=0

async_init
async_stop_worker _p10k_ci_status_worker
async_start_worker _p10k_ci_status_worker -n
async_unregister_callback _p10k_ci_status_worker
async_register_callback _p10k_ci_status_worker _ci_status_callback

function prompt_ci_status() {
    (( $+commands[hub] )) || return

    local repo_root="$(git rev-parse --show-toplevel 2> /dev/null)"
    [[ $? != 0 || -z $repo_root ]] && return

    local repo_commit="$(git rev-parse --short HEAD 2> /dev/null)"
    [[ $? != 0 || -z $repo_commit ]] && return

    _ci_status_compute $repo_root $repo_commit

    _p9k_ci_status_cache_key="${repo_root}@${repo_commit}"

    p10k segment -e -c '$_P9K_CI_STATUS_SYMBOL[$_p9k_ci_status_cache_key]' -t '$_P9K_CI_STATUS_SYMBOL[$_p9k_ci_status_cache_key]'
}
