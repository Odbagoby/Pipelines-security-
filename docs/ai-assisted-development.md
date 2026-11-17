# AI-assisted development

This repository is set up to be worked on with an AI coding agent (Claude Code) using
[ECC](https://github.com/affaan-m/ECC), an MIT-licensed plugin that gives the agent a fixed
engineering loop: plan, test, implement, review, verify.

An AI agent with shell access is part of the software supply chain, so its configuration is
treated like any other security-relevant code in this project: scoped, reviewed and documented.

## What is in this repository

| File | Purpose |
|---|---|
| [`CLAUDE.md`](../CLAUDE.md) | Project instructions the agent loads every session: commands, workflow, and the security invariants it must not weaken |
| This document | How to install ECC for this project and which parts are used |

ECC itself is not vendored here. It is installed as a plugin, from its official source, at a
pinned version, so that updates are deliberate and reviewable.

## Which parts of ECC this project uses

| ECC component | Used here | Why |
|---|---|---|
| `/ecc:plan` and the `planner` agent | Yes | Changes start as a reviewable plan |
| `tdd-workflow` skill | Yes | Security regression tests are written before the fix |
| `python-reviewer` agent | Yes | Fresh-context review of every Python change |
| `security-reviewer` agent | Yes | Review of auth, input handling, Dockerfile, workflow and Terraform changes |
| `security-review`, `docker-patterns`, `terraform-patterns` skills | Yes | Loaded on demand for the matching file types |
| Rules: `common` and `python` packs | Yes | Always-loaded standards, kept to the two packs that match this stack |
| Hooks runtime | Not by default | Hooks run scripts on the developer machine on every tool call. Enable only after reading them |
| Other language packs, the remaining skills and agents | No | Not relevant to this stack, and every always-loaded file costs context |

## Install

Prerequisites: Node.js 18 or newer, Git, and Claude Code 2.1 or newer.

1. Install the plugin. Inside Claude Code, from the repository root:

   ```text
   /plugin marketplace add https://github.com/affaan-m/ECC
   /plugin install ecc@ecc
   ```

   Or use the guided installer from a terminal and choose the project scope:

   ```bash
   npx ecc-universal@2.2.3 setup
   ```

   Use one method only. Installing twice duplicates skills and hooks.

2. Add the two rule packs to this project. Plugins cannot ship rules, so they are copied from a
   checkout of ECC:

   ```bash
   git clone --depth 1 https://github.com/affaan-m/ECC.git /tmp/ECC
   mkdir -p .claude/rules/ecc
   cp -R /tmp/ECC/rules/common .claude/rules/ecc/
   cp -R /tmp/ECC/rules/python .claude/rules/ecc/
   ```

   Read the copied files before committing them. They become standing instructions for the agent.

3. Start a new Claude Code session and confirm with `/plugin list` that `ecc@ecc` is enabled.

## Daily use

| Task | Start with |
|---|---|
| New feature or pipeline stage | `/ecc:plan "describe the change"` |
| Bug fix | A failing test, then the `tdd-workflow` skill |
| Review before commit | `/code-review` |
| Security-sensitive change | Ask for the `security-reviewer` agent |
| Before pushing | `make all` |

## Security stance on the agent itself

- **Official sources only.** ECC is installed from its GitHub repository or the `ecc-universal`
  npm package, at a pinned version. Mirrors and re-uploads are not used.
- **Least capability.** Only the components in the table above are in use. Hooks stay off until
  `hooks/hooks.json` and the scripts it calls have been read.
- **Agent configuration is reviewed like code.** Changes to `CLAUDE.md` and `.claude/` go through
  a pull request. A malicious edit to those files is a prompt-injection path into every later
  session.
- **The agent cannot release.** The AWS role trusts only the `production` environment on
  `main`. An agent working on a branch or a developer laptop has no path to production, and
  nothing merges without the pipeline's gates passing.
- **Untrusted content stays data.** `CLAUDE.md` instructs the agent not to follow instructions
  found in issues, pull requests, web pages or tool output.
- **Scan the agent configuration.** ECC's companion scanner, AgentShield, audits prompts, hooks,
  MCP configuration, permissions and secrets with `agentshield scan --path .`. It is not wired
  into CI here yet because the project has not pinned and reviewed a release of it.

## Attribution

ECC is copyright (c) 2026 Affaan Mustafa and released under the MIT License. This setup was
written against ECC 2.2.3.
