---
name: cli-distribution
description: >
  Patterns for distributing Python CLI tools — tab completion, man pages,
  help text, and Homebrew formula setup. Load when building or extending a
  CLI that will be distributed via Homebrew, or when adding shell completion,
  man pages, -h/--help flags, or the alph completions show/install commands.
  Covers Typer-specific gotchas learned from the alph project.
---

# CLI Distribution Patterns

Covers the surface area users touch outside the code itself: shell completion,
help text, man pages, and packaging via Homebrew. All of these interact in
non-obvious ways; the gotchas section is as important as the patterns.

---

## Help Text (`-h` / `--help`)

Typer exposes `--help` by default. Add `-h` as an alias via `context_settings`:

```python
_help_settings = {"help_option_names": ["-h", "--help"]}
app = typer.Typer(context_settings=_help_settings)
```

Apply the same `context_settings` to every sub-Typer (registry_app, pool_app,
etc.) so `-h` works at every level, not just the root command.

```python
registry_app = typer.Typer(
    help="Registry commands.",
    invoke_without_command=True,
    context_settings=_help_settings,
)
```

---

## Man Pages

Write a `man/alph.1` roff file. Homebrew installs it via `man1.install` in the
formula. Users then run `man alph`.

**Formula line:**
```ruby
man1.install "man/alph.1"
```

**What the man page must cover:**
- All commands and subcommands with their flags
- All config file keys (users frequently miss these — they exist nowhere else)
- A concrete YAML config example
- Environment variables
- Examples section with real invocations
- Tab completion section (where to find the script, how to activate it)

**Version string:** Update the `.TH` header on every release:
```
.TH ALPH 1 "2026-03-16" "alph 0.1.36" "Alpheus Context Engine Framework"
```

---

## Tab Completion

### How Typer completion works (and how it breaks)

Typer has **two separate completion mechanisms** that must both work:

1. **Script generation** (`_ALPH_COMPLETE=source_zsh alph`): produces the
   static completion script written to the shell's `fpath` directory.
2. **Runtime completion** (`_ALPH_COMPLETE=complete_zsh alph`): called by the
   installed script on every tab press to return live completions.

**Critical**: `add_completion=False` on the `typer.Typer(...)` constructor
prevents `completion_init()` from ever being called. Without it, Typer's
`ZshComplete` override is never registered, and script generation falls back to
Click's built-in template. Click's template uses `COMP_WORDS`/`zsh_complete`
format; Typer's runtime handler expects `_TYPER_COMPLETE_ARGS`/`complete_zsh`.
The mismatch makes every tab press silently return nothing and fall back to
file listing.

**Rule: always leave `add_completion` at its default (`True`).**

### Leading-newline bug in Typer's zsh script

Typer's `source_zsh` output starts with `\n#compdef alph` instead of
`#compdef alph`. zsh's `compinit` requires `#compdef` at byte offset 0 of the
file — a leading newline causes compinit to skip the file entirely, so the
completion function is never registered. Tab presses silently fall back to
filesystem listing with no error.

**Fix:** Strip leading whitespace from the generated script before writing it —
both in the Homebrew formula and in any `completions install` command:

```python
# In _generate_completion_script:
return result.stdout.lstrip("\n")
```

```ruby
# In the Homebrew formula:
(zsh_completion/"_alph").write \
  Utils.safe_popen_read({ "_ALPH_COMPLETE" => "source_zsh" }, bin/"alph").lstrip
```

### Why `--install-completion` fails in some environments

Typer's built-in `--install-completion` uses `shellingham` to detect the
current shell. `shellingham.detect_shell()` fails under pyenv shims,
non-interactive contexts, and some tmux setups, returning `None` →
"Shell None is not supported."

**Solution:** Implement `alph completions show/install` as explicit commands
using the `_ALPH_COMPLETE=source_<shell>` env var mechanism with `$SHELL`
basename fallback. Do NOT set `add_completion=False` to suppress the broken
built-in — that breaks the runtime completion mechanism (see above).

```python
completions_app = typer.Typer(help="Shell tab completion commands.", ...)
app.add_typer(completions_app, name="completions")

def _generate_completion_script(shell: str) -> str:
    env = {**os.environ, "_ALPH_COMPLETE": f"source_{shell}"}
    result = subprocess.run(["alph"], env=env, capture_output=True, text=True)
    # Typer emits a leading newline before #compdef — strip it so
    # compinit recognises the file (#compdef must be on byte 0).
    return result.stdout.lstrip("\n")

def _resolve_shell(shell: str | None) -> str:
    if shell:
        return shell.lower()
    shell_env = os.environ.get("SHELL", "")
    if shell_env:
        return Path(shell_env).name.lower()
    raise typer.BadParameter("Could not detect shell. Pass: zsh, bash, or fish.")
```

### Wiring completions to arguments

```python
@registry_app.command("check")
def registry_check(
    registry: str = typer.Argument(
        None,
        autocompletion=_complete_registry_id,
    ),
):
    ...
```

`autocompletion=` on `typer.Argument` and `typer.Option` is how custom
completion functions attach. The function receives `(ctx, param, incomplete)`
and returns a list of strings (or `(value, description)` tuples).

```python
def _complete_registry_id(ctx, param, incomplete: str) -> list[str]:
    try:
        cfg = _load_cli_config()
        ids = [r.registry_id for r in collect_registries(cfg=cfg)]
        ids.append("all")
        return [i for i in ids if i.startswith(incomplete)]
    except Exception:
        return []
```

Always swallow exceptions in completion functions — a crash during tab
completion produces a confusing error and breaks the shell session.

### Homebrew formula: generating completions at install time

Typer exposes the completion script via `_ALPH_COMPLETE=source_<shell>`. Use
`Utils.safe_popen_read` in the formula `install` block:

```ruby
(zsh_completion/"_alph").write \
  Utils.safe_popen_read({ "_ALPH_COMPLETE" => "source_zsh" }, bin/"alph")
(bash_completion/"alph").write \
  Utils.safe_popen_read({ "_ALPH_COMPLETE" => "source_bash" }, bin/"alph")
(fish_completion/"alph.fish").write \
  Utils.safe_popen_read({ "_ALPH_COMPLETE" => "source_fish" }, bin/"alph")
```

This runs after the binary is installed, so the script is always generated
from the actual installed version.

### Homebrew formula: caveats for shell setup

Homebrew installs the completion file but does not modify `~/.zshrc`. Users
must add `HOMEBREW_PREFIX/share/zsh/site-functions` to their `fpath` manually.
The formula `caveats` block is the only place to tell them this.

**Oh My Zsh gotcha:** OMZ runs its own `compinit` inside `source $ZSH/oh-my-zsh.sh`.
Any `fpath` additions that appear after that line are too late — `compinit` has
already finished and won't rescan. The `fpath` line must appear **before** the
`source $ZSH/oh-my-zsh.sh` call, not at the end of `~/.zshrc` where most users
would naturally put it. This also means `autoload -Uz compinit && compinit`
should be omitted — OMZ handles it. Adding a second `compinit` call after OMZ
has run is harmless but redundant; it will use the (already correct) cache.

**Stale compinit cache:** `compinit` writes a cache file (`~/.zcompdump*`). If
the cache was built before `_alph` appeared in `fpath`, the function will not be
loaded even after the `fpath` is fixed. Delete all variants to force a rescan:
```zsh
rm -f ~/.zcompdump* && exec zsh
```

```ruby
def caveats
  <<~EOS
    Tab completion has been installed for zsh, bash, and fish.

    zsh: add the following to ~/.zshrc if not already present:
      fpath=(#{HOMEBREW_PREFIX}/share/zsh/site-functions $fpath)
      autoload -Uz compinit && compinit

    bash: add the following to ~/.bashrc if not already present:
      [[ -r "#{HOMEBREW_PREFIX}/etc/bash_completion.d/alph" ]] && \\
        source "#{HOMEBREW_PREFIX}/etc/bash_completion.d/alph"

    fish: completions are loaded automatically — no setup needed.

    Reload your shell (exec zsh / exec bash) after editing your rc file.
  EOS
end
```

Use `#{HOMEBREW_PREFIX}` (Ruby interpolation), not a hardcoded path — it
resolves to `/opt/homebrew` on Apple Silicon and `/usr/local` on Intel.

### Testing the completion pipeline end-to-end

```bash
# 1. Verify script generation produces Typer's format (not Click's)
_ALPH_COMPLETE=source_zsh alph | grep "COMPLETE\|TYPER"
# Expected: _ALPH_COMPLETE=complete_zsh (not COMP_WORDS/zsh_complete)

# 2. Verify runtime completion returns results
_TYPER_COMPLETE_ARGS="alph registry check " _ALPH_COMPLETE=complete_zsh alph
# Expected: list of registry IDs

# 3. Verify installed script uses correct format
grep "COMPLETE\|TYPER" /opt/homebrew/share/zsh/site-functions/_alph
# Expected: _ALPH_COMPLETE=complete_zsh

# 4. Verify fpath includes Homebrew completions dir
echo $fpath | tr ' ' '\n' | grep homebrew
# Expected: /opt/homebrew/share/zsh/site-functions
```

If step 1 shows `COMP_WORDS`/`zsh_complete` instead of `_TYPER_COMPLETE_ARGS`/
`complete_zsh`, `completion_init()` was never called — check `add_completion`.

---

## Homebrew Formula: Versioning and SHA

**Never use `curl | shasum` to get the SHA.** Use `brew fetch --force` on the
formula after updating the URL. The curl download can be a redirect that
returns a different artifact than what Homebrew fetches.

```bash
# 1. Update the url line in the formula
# 2. Run:
brew fetch --force Formula/alph.rb
# 3. Read the SHA from the output and paste into sha256
```

If using the curl approach and the SHA mismatches, `brew install` will print
the correct SHA in its error message — use that value.

**Version bump checklist:**
- `pyproject.toml` version
- `man/alph.1` `.TH` header version string
- Homebrew formula `url` and `sha256`
- Git tag matching the version (`git tag v0.1.X && git push origin v0.1.X`)
- `STATE.md` current version line

---

## Shorthand Subcommands

Typer lets you register the same `Typer` instance under multiple names:

```python
app.add_typer(registry_app, name="registry")
app.add_typer(registry_app, name="reg", hidden=True)  # shorthand
```

`hidden=True` suppresses `reg` from `--help` output while keeping it
functional. Tab completion still completes `reg` subcommands because it's the
same underlying object.

For commands where `alph registry` with no subcommand should default to
`alph registry list`, use `invoke_without_command=True` and check in the
callback:

```python
registry_app = typer.Typer(invoke_without_command=True, ...)

@registry_app.callback()
def registry_callback(ctx: typer.Context) -> None:
    if ctx.invoked_subcommand is None:
        ctx.invoke(registry_list)
```

---

## Release Workflow Pattern

A GitHub Actions workflow triggered on tag push handles building the sdist/
wheel and creating a GitHub release. The Homebrew formula is updated manually
after confirming the release artifact exists (formula auto-update via
`HOMEBREW_TAP_TOKEN` is the next step but requires org-level setup).

The release workflow must be on the tag push, not the branch push, so the
artifacts exist before the formula references them.
