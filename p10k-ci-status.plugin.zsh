#!/usr/bin/env zsh
# TODO:
# - [x] Asynchronous execution
#   - [x] Support all states
#   - [x] Update the prompt once the async job is completed
#   - [x] Proper caching per repo & branch
#     - [x] Check commit instead of branch?
# - [x] Prefer gh cli over hub
# - [x] Fall-back: hub ci-status $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
#   - [ ] Better colors - does Warp have another theme?
# - [x] Allow configuration. Probably done with states and colors.
# - [ ] Add a readme
# - [ ] Optimizations:
#   - [x] Add a timeout to not check to often
#   - [x] Only update when state changes
#   - [ ] Prevent memory leaks in arrays
#   - [ ] Perform git root-dir and commit check asynchronously? (Takes 0.009 s.)
#   - [ ] Check how concurrency works for async. Will runs be restarted if they are already running? Check worker parameters!
#

function _ci_status_compute() {
    local repo_root=$1 cache_key=$2
    (( EPOCHREALTIME >= _p9k_ci_status_next_time )) || return

    async_job _p10k_ci_status_worker _ci_status_async $repo_root $cache_key

    _p9k_ci_status_next_time=$((EPOCHREALTIME + 10))
}

function _ci_status_async() {
    local repo_root=$1
    local cache_key=$2

    if (( $+commands[gh] )); then
        _ci_status_using_gh $repo_root $cache_key
    elif (( $+commands[hub] )); then
        _ci_status_using_hub $repo_root $cache_key
    else
        echo $cache_key
        echo UNAVAILABLE
    fi
}

function _ci_status_gh_api_call() {
    local repo=$1
    local commit=$2

    gh api -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        /repos/$repo/commits/$commit/check-runs --paginate 2> /dev/null
}

function _ci_status_using_gh() {
    local gh_output gh_exit_code state
    local repo_root=$1
    local cache_key=$2
    local upstream_prefix=''
    local github_repo_path

    if [[ -n ${_p9k_ci_status_github_repo_paths[$repo_root]} ]]; then
        github_repo_path=${_p9k_ci_status_github_repo_paths[$repo_root]}
    else
        github_repo_path="$(gh repo view --json nameWithOwner -q .nameWithOwner 2> /dev/null)"
        if [[ -n $github_repo_path ]]; then
            _p9k_ci_status_github_repo_paths[$repo_root]=$github_repo_path
        else
            echo $cache_key
            echo UNAVAILABLE
            return
        fi
    fi

    state=NEUTRAL
    local local_commit=$(git rev-parse HEAD 2> /dev/null)
    gh_output="$(_ci_status_gh_api_call $github_repo_path $local_commit)"
    gh_exit_code=$?

    if [[ $gh_exit_code == 1 ]]; then
        local upstream_commit="$(git rev-parse @{u} 2> /dev/null)"
        if [[ $? == 0 && ! -z $upstream_commit ]]; then
            gh_output="$(_ci_status_gh_api_call $github_repo_path $upstream_commit)"
            gh_exit_code=$?
            upstream_prefix='UPSTREAM_'
        fi
    fi

    state=UNKNOWN
    if [[ $gh_exit_code == 0 ]]; then
        local run_conclusions="$(echo $gh_output \
            | jq -r '.check_runs[] | select(.status=="completed") | .conclusion' \
            | sort | uniq
        )"

        local run_statuses="$(echo $gh_output \
            | jq -r '.check_runs[] | .status' \
            | sort | uniq
        )"

        if [[ $run_conclusions =~ "action_required" ]]; then
            state=ACTION_REQUIRED
        elif [[ $run_conclusions =~ "failure" ]]; then
            state=FAILURE
        elif [[ $run_conclusions =~ "cancelled" || $run_conclusions =~ "timed_out" ]]; then
            state=CANCELLED
        elif [[ $run_statuses != "" && $run_statuses != "completed" ]]; then
            state=BUILDING
        elif [[ $run_conclusions =~ "neutral" ]]; then
            state=NEUTRAL
        elif [[ $run_conclusions =~ "success" ]]; then
            state=SUCCESS
        fi
    else
        state=UNAVAILABLE
    fi

    echo $cache_key
    echo $upstream_prefix$state
}

function _ci_status_using_hub() {
    local hub_output hub_exit_code state
    local repo_root=$1
    local cache_key=$2
    local upstream_prefix=''

    pushd $repo_root > /dev/null

    hub_output="$(hub ci-status 2> /dev/null)"
    hub_exit_code=$?

    if [[ $hub_exit_code == 3 && $hub_output == "no status" ]]; then
        local upstream_branch
        upstream_branch="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2> /dev/null)"
        if [[ $? == 0 && ! -z $upstream_branch ]]; then
            hub_output="$(hub ci-status $upstream_branch 2> /dev/null)"
            hub_exit_code=$?
            upstream_prefix='UPSTREAM_'
        fi
    fi

    popd > /dev/null

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

    echo $cache_key
    echo $upstream_prefix$state
}

function _ci_status_callback() {
    local return_values=(${(f)3})

    local cache_key=$return_values[1]
    local state=$return_values[2]


    if [[ $_p9k_ci_status_state[$cache_key] != $state ]]; then
        _p9k_ci_status_state[$cache_key]=$state
        p10k display -r
    fi

    _p9k_ci_status_next_time=$((EPOCHREALTIME + 5))
}

typeset -gA _p9k_ci_status_state
typeset -gA _p9k_ci_status_github_repo_paths
typeset -gF _p9k_ci_status_next_time=0
typeset -g _p9k_ci_status_cache_key

async_init
async_stop_worker _p10k_ci_status_worker
async_start_worker _p10k_ci_status_worker -n
async_unregister_callback _p10k_ci_status_worker
async_register_callback _p10k_ci_status_worker _ci_status_callback

function _ci_status_create_segment() {
    local state=$1 color=$2 text=$3
    p10k segment -s $state -c '${(M)_p9k_ci_status_state[$_p9k_ci_status_cache_key]:#'$state'}' -f $color -et $text
}

function prompt_ci_status() {
    (( $+commands[gh] )) || (( $+commands[hub] )) || return

    local repo_root="$(git rev-parse --show-toplevel 2> /dev/null)"
    [[ $? != 0 || -z $repo_root ]] && return

    local repo_commit="$(git rev-parse --short HEAD 2> /dev/null)"
    [[ $? != 0 || -z $repo_commit ]] && return

    local new_cache_key="${repo_root}@${repo_commit}"
    if [[ $_p9k_ci_status_cache_key != $new_cache_key ]]; then
        _p9k_ci_status_cache_key=$new_cache_key
        _p9k_ci_status_next_time=0
    fi

    _ci_status_compute $repo_root $_p9k_ci_status_cache_key

    local checkmark='✔︎' bullet='•' cross='✖︎' triangle='▴'

    _ci_status_create_segment SUCCESS green $checkmark
    _ci_status_create_segment BUILDING yellow $bullet
    _ci_status_create_segment FAILURE red $cross
    _ci_status_create_segment CANCELLED yellow $cross
    _ci_status_create_segment ACTION_REQUIRED red $triangle
    _ci_status_create_segment NEUTRAL cyan $checkmark

    _ci_status_create_segment UPSTREAM_SUCCESS grey $checkmark
    _ci_status_create_segment UPSTREAM_BUILDING grey $bullet
    _ci_status_create_segment UPSTREAM_FAILURE grey $cross
    _ci_status_create_segment UPSTREAM_CANCELLED grey $cross
    _ci_status_create_segment UPSTREAM_ACTION_REQUIRED grey $triangle
    _ci_status_create_segment UPSTREAM_NEUTRAL grey $checkmark
}
