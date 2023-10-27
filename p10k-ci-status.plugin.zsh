#!/usr/bin/env zsh
# TODO:
# - [x] Asynchronous execution
#   - [ ] Properly refresh terminal - might just not work with warp?
#   - [ ] Support all states
#   - [ ] Prompt updating
#   - [x] Proper caching per repo & branch
# - [ ] Fall-back: hub ci-status $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
# - [ ] Allow configuration
# - [ ] Add a readme
#

function _ci_status() {
    local hub_output hub_exit_code state
    local repo_root="$1"
    local repo_branch="$2"

    hub_output="$(cd $repo_root; hub ci-status 2> /dev/null)"
    hub_exit_code=$?

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
}

function _ci_status_callback() {
    local working_directory
    local ci_status
    local return_values=(${(f)3})
    _P9K_CI_STATUS_STATE[$return_values[1]]=$return_values[2]
}

typeset -g -A _P9K_CI_STATUS_STATE

async_init
async_stop_worker _p10k_ci_status_worker
async_start_worker _p10k_ci_status_worker -n
async_unregister_callback _p10k_ci_status_worker
async_register_callback _p10k_ci_status_worker _ci_status_callback

function prompt_ci_status() {
    (( $+commands[hub] )) || return

    local repo_root="$(git rev-parse --show-toplevel)"
    local repo_branch="$(git rev-parse --abbrev-ref HEAD)"
    async_job _p10k_ci_status_worker _ci_status $repo_root $repo_branch

    local state="$_P9K_CI_STATUS_STATE[${repo_root}@${repo_branch}]"
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

    if [ ! -z $icon ]; then
        p10k segment -s $state -i $icon -f $foreground -t $icon
    fi
}
