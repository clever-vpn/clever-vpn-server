# Repository Copilot Instructions

## Git Workflow Policy (Mandatory)

Follow this policy for all code and workflow changes unless the user explicitly overrides it in the current chat.

1. Never push directly to `main`.
2. Do all work in a non-main branch.
3. Use pull requests for all merges into `main`.
4. Preferred lifecycle is:
   - issue -> new branch -> implement -> PR -> merge -> delete branch
5. After PR merge, delete both remote and local feature branches when possible.

## Branching Rules

1. If current branch is `main`, create and switch to a new working branch before making commits.
2. Keep branch names task-oriented, for example:
   - `issue-<number>-<short-topic>`
   - `chore/<short-topic>`
   - `fix/<short-topic>`

## PR Rules

1. Ensure CI or required checks pass before merge when feasible.
2. Use clear PR titles and include a short summary of behavior changes.
3. Do not bypass branch protection rules.

## Safety Rules

1. Do not use destructive git operations unless explicitly requested.
2. Do not rewrite shared history unless explicitly requested.
3. If unexpected large workspace changes appear, stop and ask the user before proceeding.

## Default Execution Pattern

When the user asks for implementation work, default to this order:

1. Confirm/locate issue context.
2. Create a new branch for this issue.
3. Implement and validate changes.
4. Commit and push branch.
5. Open PR.
6. Merge PR after checks.
7. Delete feature branch.

## Release Tag Rules

Apply these rules when implementing or modifying release workflows and version logic.

1. Git tags and GitHub Releases must use a `v` prefix, for example `v1.2.3` and `v1.2.3-rc.1`.
2. Workflow input may accept both prefixed and unprefixed versions, for example `v1.2.3` and `1.2.3`.
3. Normalize version input internally, but always publish using the prefixed tag format.
4. Auto-bump logic should parse the latest release version safely and publish the next version with the `v` prefix.
5. Duplicate checks should target the normalized publish tag to avoid mixed-prefix conflicts.
