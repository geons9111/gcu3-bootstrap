# GCU3 development environment guardrails

- Edit `gcu3-platform` only in its local WSL session worktree. Run lightweight formatting, linting, unit tests, and repository checks locally.
- Never run a full Yocto build on the Windows host or local WSL2 Docker Engine.
- Keep the active Docker context `default`; it must remain the local WSL engine. Never run `docker context use`.
- Every Azure Docker command must include `--context gcu3-platform-azure`. Prefer the guarded scripts in `azure/`.
- Azure Compose operations must use project `gcu3-platform`. Never prune Docker, enumerate or alter unrelated containers/images/networks, change Docker daemon configuration, or modify `/opt/data/yocto`.
- Use only `/opt/data/gcu3-platform/{src,downloads,sstate-cache,build,artifacts}` for this workflow. Source bind paths are remote VM paths, not local WSL paths.
- Stop the builder before `azure/sync_source.sh` or `azure/remote_clone.sh`. Do not add `rsync --delete` or sync secrets, keys, `.env` files, caches, or build output.
- Use a pinned prebuilt image through `GCU3_YOCTO_IMAGE`. Never put registry credentials, proxy credentials, tokens, or SSH keys in repository files or image layers.
- Start builds only after an explicit user request. Retrieve only specifically requested artifacts with `azure/download_artifacts.sh` and bounded log summaries with `azure/compose.sh logs`.
- The current 2-vCPU/8-GB VM and approximately 121 GB free space are below routine Yocto targets. Treat compute resize and free-space review as capacity prerequisites, not reasons to move builds local.
<!-- mermaid-ai-skills:start -->
## Mermaid Diagrams

When the user asks to create, edit, or visualize a diagram, follow the
instructions in `.github/instructions/mermaid.instructions.md`.
<!-- mermaid-ai-skills:end -->
