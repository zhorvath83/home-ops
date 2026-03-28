# Evaluation

Use this reference when comparing architectural options.

## Questions To Answer

- Does the proposal reuse an existing repo pattern?
- Does it preserve GitOps as the steady-state source of truth?
- Does it fit the current single-node home-ops reality?
- Does it create a new operator surface, credential path, or failure mode?
- Does it increase maintenance burden more than the value it adds?
- Does it create cluster-wide coupling when the problem is app-local?

## Preferred Biases In This Repo

- declarative over imperative
- existing task wrappers over ad-hoc shell flows
- existing secret model over parallel secret systems
- established app or platform patterns over one-off layouts
- narrow exceptions over broad platform changes

## Option Review

For each serious option, note:

- fit with current repo structure
- required new dependencies or services
- validation path
- likely rollback or recovery story
- long-term maintenance cost
