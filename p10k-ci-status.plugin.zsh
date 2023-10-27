# TODO:
# - [ ] Asynchronous execution
# - [ ] Fall-back: hub ci-status $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
# - [ ] Allow configuration
# - [ ] Add a readme
#

function prompt_ci_status() {
    local state color='' text=''
    local output exit_code
    local CHECK='✔︎' CROSS='✖︎' BULLET='•' TRIANGLE='▴'
    
    output="$(hub ci-status 2> /dev/null)"
    exit_code=$?

    case $exit_code in
        0)
            text="$CHECK"
            if [[ $output == "neutral" ]]; then
                state=NEUTRAL
                color=gray
            else
                state=SUCCESS
                color=green
            fi
            ;;
        1)
            text="$CROSS"
            if [[ $output == "action_required" ]]; then
                state=ACTION_REQUIRED
                text="$TRIANGLE"
                color=red
            elif [[ $output == "cancelled" || $output == "timed_out" ]]; then
                state=CANCELLED
                color=yellow
            elif [[ $output == "failure" || $output == "error" ]]; then
                state=FAILURE
                color=red
            fi
            ;;
        2)
            state=BUILDING
            text="$BULLET"
            color=yellow
            ;;
        3)
            state=NO_STATUS
            ;;
    esac

    p10k segment -s $state -f $color -t $text
}
