# CLI and website maintenance

Whenever the CLI changes, review and update the companion website in
`../ghstacked` (`peterlapin/ghstacked`) in the same task. Keep command mappings,
examples, behavior notes, prerequisites, and installation instructions accurate.
Website content is primarily in `src/config/site.ts` and `src/components/`.

Use the local CLI code and version as the source of truth, including uncommitted
changes. Update the website in the same task without waiting for or checking a
GitHub release or merged Homebrew formula. Describe local behavior directly;
do not add release-dependent caveats or defer website updates to another prompt.
Run the CLI checks and website typecheck/build for the affected projects.
Report changes in both repositories; pushing, releasing, and deploying remain
separate actions requiring user authorization.
