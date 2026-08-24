# Local homeserver deployment automation code generation plan

This plan is the source of truth for adding relay deployment to the local `main` push routine.

- [x] Inspect the existing pre-push hook, local Mac/Android updater, relay deployment script, homeserver prerequisites, and tests.
- [x] Extend the fake-command integration test so relay deployment is required across Android availability cases and remains skipped for non-`main` pushes.
- [x] Run the changed test and confirm it fails before implementation.
- [x] Refactor Android target selection so Android skips do not exit before relay deployment.
- [x] Invoke the existing relay deployment script after Mac and optional Android updates.
- [x] Update operator documentation for automatic pre-push relay deployment and failure behavior.
- [x] Run shell syntax, fake-command integration, ShellCheck, relay tests, and Docker image validation.
- [x] Deploy to `homeserver` without deleting the named configuration volume and verify container health.
- [x] Verify NPM/DNS/TLS reachability or record the exact remaining operator configuration.
- [x] Update AI-DLC state and audit evidence.
