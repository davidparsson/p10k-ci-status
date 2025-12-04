# GitHub CI status for Powerlevel10k

A segment for Powerlevel10k that indicates the GitHub's CI status for the current branch.

## Installation

This depends on [hub](https://hub.github.com) to perform status checks, and
[zsh-async](https://github.com/mafredri/zsh-async) to do this asynchronously. These
dependencies need to be installed manually.

Once the dependencies are installed, load `p10k-ci-status.plugin.zsh` after Powerlevel10k is
loaded in your `~/.zshrc` or similar, for example with `zgen`:

    zgen load davidparsson/p10k-ci-status

Finally add the `ci_status` segment to your list of segments in `~/.p10k.zsh`. In the examples
below it is added last to `POWERLEVEL9K_LEFT_PROMPT_ELEMENTS`.

## What it does

It provides a symbol for the status of the current branch, below seen as the green checkmark
or red cross:

<img width="482" alt="A prompt with a green checkmark" src="https://github.com/davidparsson/p10k-ci-status/assets/325325/0ad58da2-44ba-425b-a75d-8f73e6aea182">
<img width="482" alt="A prompt with a red cross" src="https://github.com/davidparsson/p10k-ci-status/assets/325325/e2b21b80-58aa-43c4-bdb8-bf8f60f2fcd2">

The available statuses are:

- `SUCCESS`: A green checkmark
- `BUILDING`: A yellow bullet
- `FAILURE`: A red cross
- `CANCELLED`: A yellow cross
- `ACTION_REQUIRED`: A red triangle
- `NEUTRAL`: A cyan checkmark
- `SKIPPED`: A grey dash

If there is no status for the local branch head, the upstream/remote branch head is used. In that
case the same symbol is used, but the color is grey. The upstream statuses are:

- `UPSTREAM_SUCCESS`
- `UPSTREAM_BUILDING`
- `UPSTREAM_FAILURE`
- `UPSTREAM_CANCELLED`
- `UPSTREAM_ACTION_REQUIRED`
- `UPSTREAM_NEUTRAL`
- `UPSTREAM_SKIPPED`
