# docent

English | [한국어](README.ko.md)

A Claude Code plugin that grounds explanations in your existing technical experience.
Tell it “I build frontends with React and have only written small Python scripts.” No skill grades needed.

When explaining a new technology, Claude starts from useful familiar concepts, explains similarities and important differences, skips known basics, and focuses on what changes. It avoids forced analogies and does not assume an unlisted technology is unfamiliar.

## Install

```text
/plugin marketplace add tnfhrnsss/claude-docent
/plugin install docent@docent
```

Requires Bash. On Windows, use Git for Windows.

## Use

```text
/docent:status familiar I build frontends with React and have only written small Python scripts.
/docent:status
```

The first command saves your experience; the second shows the effective profile. Saving again replaces the whole description. A simple stack list also works. Run `/docent:status familiar` without a description to clear the global profile. Changes apply at the next session or after `/clear`.

Your current request takes precedence over the profile. Routine completion reports do not need analogies. This plugin supplies explanation instructions to Claude; it cannot guarantee the quality of every answer.

## Configuration and data

Global experience is stored as plain text in `~/.claude/docent/familiar.txt`. You may edit it directly, including multiple lines. For a project override, create `<project>/.claude/docent/familiar.txt`; an empty file disables the profile for that project. Commands only write the global profile and never write into your project.

Use `~/.claude/docent/config` or `<project>/.claude/docent/config` for:

```ini
enabled=true
```

Set `false` to disable injection. Project configuration overrides global configuration.

Legacy `familiar=react, typescript` still works. Precedence: project `familiar.txt`, project config `familiar`, global `familiar.txt`, global config `familiar`. Text files preserve Korean, `C#`, and multiline descriptions literally.

## Migration

Starting in 0.5.0, forced plain wording, automatic explanation levels, re-question tracking, and avoided-term recording are removed. `level`, `forget`, and `reset` are no longer used. Old records are left untouched and never read. `familiar` now accepts natural-language experience as well as stack lists.

## Update

```text
/plugin marketplace update docent
```

You can also enable automatic updates in `/plugin` → Marketplaces. Experience stored outside the plugin survives updates.

## License

MIT
