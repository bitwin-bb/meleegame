# Nevermore Integration Audit

Implemented on April 18, 2026.

## Adopted cleanly

- `ServiceBag`
  Client and server entrypoints now start a dedicated Nevermore service bag through `Shared/Modules/Core/NevermoreSupport.luau`.
- `Binder` + `BinderProvider`
  Repeated binder startup in service `Init()` methods was consolidated into:
  `Client/Binders/ClientBinderSupport.luau`
  `Server/Binders/ServerBinderSupport.luau`
- `Snackbar`
  Client notifications now use `SnackbarServiceClient` instead of ad-hoc notification plumbing for build and crafting feedback.
- `ClientTranslator`
  Snackbar messages are routed through `AquariaBackupTranslator.lua`, which now includes user-facing notification strings.
- `Octree`
  `Shared/Classes/WindFoliage/TreeRuntimeRegistry.luau` now applies Nevermore Octree region-size/depth configuration correctly instead of passing ignored constructor arguments.

## Repo-wide candidates reviewed

- `Shared/Modules/UI/NotificationBus.luau`
  This overlaps with `Snackbar` for transient feedback, but it is broader than the current user-facing needs. I left it in place for richer queued/pool-based custom UI use cases.
- `Shared/Classes/WindFoliage/init.luau`
  Already had a solid tag-observer architecture; binder adoption there would duplicate behavior.
- Manual service bootstraps in `AquariaBackupClientBootstrap.lua` and `AquariaBackupServerBootstrap.lua`
  I kept the gameplay/service init order intact and wrapped Nevermore around it rather than trying to force every singleton into unordered `ServiceBag` initialization.
- `CmdrService`
  Audited but not force-fit. There is no existing command-registration surface in this repo that would let me add it without inventing a parallel admin/debug command architecture.
- `Flipbook`
  Audited but not force-fit. None of the current UI or sprite animation paths are using sheet-driven flipbook animation, so adding it here would be speculative rather than a clean replacement.

## Result

- Binder lifecycle is centralized.
- Snackbar/localization are now real package-backed systems.
- Octree configuration is no longer silently ignored.
- The existing gameplay bootstrap order remains stable.
