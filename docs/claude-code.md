# Codex と Claude Code の skill 同期

## Skill の正本と同期

Codex と Claude Code で同じ skill を使うため、正本は `.agents/skills/` に置く。
Codex は正本を直接参照し、Claude Code は `.claude/skills/<skill-name>/SKILL.md` を検出する。
`.claude/skills/` は `.agents/skills/` から生成するため、同期対象 skill を直接編集しない。

```powershell
.\scripts\sync-claude-skills.ps1
.\scripts\sync-claude-skills.ps1 -Check
```

skill を追加・変更・削除した場合は、同期後に生成された `.claude/skills/` の差分も同じ commit に含める。
CI は `-Check` を実行し、未同期または削除漏れを検出する。

`.claude/skills/atlas/` は Atlas の Claude Code 用 skill であり、この同期の対象外とする。
それ以外の `.claude/skills/` は同期対象であり、手作業の skill を置かない。
