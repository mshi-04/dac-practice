# Claude Code

## Skill の正本と同期

Codex と Claude Code で同じ skill を使うため、正本は `.agents/skills/` に置く。
Claude Code は `.claude/skills/<skill-name>/SKILL.md` を検出するため、この directory は
`.agents/skills/` から生成する。`.claude/skills/` 配下の同期対象 skill は直接編集しない。

```powershell
.\scripts\sync-claude-skills.ps1
.\scripts\sync-claude-skills.ps1 -Check
```

skill を追加・変更・削除した場合は、同期後に生成された `.claude/skills/` の差分も同じ commit に含める。
CI は `-Check` を実行し、未同期または削除漏れを検出する。

`.claude/skills/atlas/` は Atlas の Claude Code 用 skill であり、この同期の対象外とする。
それ以外の `.claude/skills/` は同期対象であり、手作業の skill を置かない。

## Claude Code の共通指示

`CLAUDE.md` は `@AGENTS.md` を import する。共通指示は `AGENTS.md` に集約し、
Claude Code 固有の指示だけを `CLAUDE.md` に追加する。

`@path` import は `CLAUDE.md` の機能であり、`SKILL.md` から `.agents/skills/` を
import する仕組みには使わない。
