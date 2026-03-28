# Cursor agent instructions — Tally (iOS)

This file is for **AI assistants working in this repository**. Read it at the start of a session (or when the user points you here). The human’s preferences below apply **in addition** to any user rules they configure in Cursor.

---

## 1. Which repo is “the project”

- **Tally app source of truth for Git + Cursor:** this folder — the **TallyRepo** clone (`Tally.xcodeproj`, `Tally/`, `TallyTests/` at the root of this tree).
- **Not in scope when the user says “Tally only”:** the parent monorepo **A Simple Life** (`ASimpleLife`), the marketing **Website** submodule, or any path like `Tally/IOS/...` *outside* this clone unless the user explicitly asks to sync or mirror them.
- **Practical rule:** If the user opens **`TallyRepo` as the Cursor workspace root**, Git status, search, and commits refer only to **https://github.com/joshmalosh/Tally.git**. That avoids confusion with other repos.

When the user asks to **push** or **sync** “the Tally app,” assume they mean **`origin/main` on this repo** unless they name another remote or path.

---

## 2. How this user expects you to behave

### 2.1 Execute; don’t delegate

- This is a **real machine** with shell and network. **Run commands yourself** (build checks, `git status`, searches, linters).
- **Do not** reply with “you should run X” when you can run X. If something fails, **try alternatives** and narrow the cause before giving up.

### 2.2 Instructions are strict

- Follow **user messages, rules, skills, and tool constraints completely** — not partially.
- If a skill or rule specifies format, steps, or naming, **follow it** even if another approach seems nicer.

### 2.3 Scope and code quality

- **Change only what the task requires.** No drive-by refactors, no “while I’m here” edits in unrelated files, no extra features.
- **Read surrounding code** before editing. Match existing naming, types, patterns, imports, and comment density. New code should read as if the same author wrote it.
- **No** placeholder code, **no** commented-out blocks left “for later,” **no** unnecessary docstrings on obvious APIs, **no** noisy defensive `try/catch` unless the codebase already does that.
- **Do not** add or rewrite markdown docs (README, briefs, CHANGELOG) **unless the user asks** — except maintaining **this** `AGENTS.md` when they ask to update agent instructions.

### 2.4 Communication style (replies to the user)

- Use **proper prose** — clear, structured, technically precise, not telegraphic.
- **Code references** in answers: use Cursor’s required block form so the UI can link files — opening fence on its own line:

  ````text
  ```12:20:Tally/SomeFile.swift
  // code here
  ```
  ````

  Do **not** prefix the opening fence with list markers or other text on the same line.
- **Inline code** and **fenced code** are literal — don’t use HTML entities (`&amp;`) for characters that should show as symbols.
- Prefer **full URLs and full paths** when linking (no eliding `https://` or middle path segments for “brevity”).
- Use **bold and backticks sparingly** for emphasis, not decoration.
- Avoid the **§** character in user-facing copy (rendering issues).
- Skip **engagement-bait closings** (“Let me know if you need anything!”). If a useful follow-up exists, state it plainly in one sentence.
- **Todos:** if you use a todo list, mark items **completed** when done; don’t leave items `in_progress` when finished.

### 2.5 Conversation and intent

- Interpret each message **in context** of the thread: the latest message often **refines** ongoing work, not a brand-new unrelated task.
- Infer **underlying goals** and **constraints** (what “done” looks like, what must not break).

---

## 3. Product and technical context (Tally iOS)

### 3.1 Stack

- **SwiftUI**, **SwiftData** (`@Model`, `ModelContainer`), iOS target as defined in the Xcode project.
- **Monetization / ads:** project may include **Google Mobile Ads** and subscription-related code; **do not rip out** billing, OCR, tags, export, or subscription flows unless the user explicitly requests it.

### 3.2 Important locations (typical)

| Area | Where to look |
|------|----------------|
| App entry, SwiftData setup | `Tally/TallyApp.swift` |
| Global UI state | `Tally/AppState/AppState.swift` |
| Persistence models | `Tally/Models/` |
| Home / list | `Tally/Views/Home/HomeView.swift` |
| Add / edit expense | `Tally/Views/AddExpense/AddExpenseView.swift` |
| Detail | `Tally/Views/ExpenseDetail/ExpenseDetailView.swift` |
| Export | `Tally/Views/Export/` (`ExportView.swift`, `GlobalExportSheet.swift`, etc.) |
| Settings | `Tally/Views/Settings/SettingsView.swift` |
| Shared UI / cards | `Tally/Theme/Components.swift`, design tokens |
| Services | `Tally/Services/` |

Paths are from the **repo root** (the folder that contains `Tally.xcodeproj`).

### 3.3 Recent architectural notes (continuity)

Use `git log` for authoritative history; this section avoids re-deriving intent from scratch.

- **Recurring expenses** were **fully removed** from the app (model fields, UI, launch processing, notification scheduling, dedicated services). Do **not** reintroduce them unless the user explicitly asks for a new design.
- **SwiftData schema changes** in dev: the app uses a **store schema version** in `TallyApp` to **delete and recreate** the local store when the version bumps — **no lightweight migration** for that path. If you add/remove `@Model` properties, coordinate with the user on bumping that version.
- **Free-tier CSV exports:** business rules live in `AppState` (e.g. monthly cap, `canExportCSV`, `recordCSVExport`). **Pro** vs **free** gating for other features (templates, PDF, etc.) may be separate — **read the code** before assuming one flag controls everything.
- **`ExportLimitSheet`** (or similar) copy and presentation must stay aligned with whatever the current free-tier rule is; search for usages — some sheets may exist without being wired.

If something in this section disagrees with the code, **the code wins**; update this file only when the user wants the handoff refreshed.

---

## 4. Git and delivery workflow

### 4.1 Day-to-day

- After non-trivial work, offer or perform **`git status`** / **`git diff`** sanity checks.
- When the user says **push** (for Tally): from **this repo**, on **`main`**, **`git push origin main`** after commits. Use clear commit messages (full sentences, describe *why* when non-obvious).

### 4.2 Avoid common mix-ups

- **Do not** assume pushes to **A-Simple-Life-Website** or other remotes satisfy “push Tally” unless they say so.
- **Mirroring** from a monorepo folder into this repo is a **separate, deliberate** operation (easy to delete extra files with blind `robocopy /MIR`). Prefer **git-based** workflows or explicit file lists unless the user asks for a full mirror.

### 4.3 Submodules / nested repos inside this tree

- If this clone ever contains **nested git checkouts** (e.g. under `Tally/Repo/`), treat them carefully: **don’t** commit another repo’s `.git` into Tally by mistake. Follow `.gitignore` and the user’s intent.

---

## 5. Before you change things

1. **Search** the codebase for existing patterns (grep / semantic search).
2. **Read** full files or large contiguous sections when the task touches behavior, not just the diff hunk.
3. **Preserve** unrelated behavior (export formats, OCR gates, tag logic, subscription checks) unless the task says otherwise.
4. After edits, **run linters** / diagnostics on touched files if available in the environment.

---

## 6. Optional: first message to paste for a brand-new chat

If the user starts a **new** agent thread and wants zero context loss, they can paste:

> Read `AGENTS.md` in the repo root and follow it. This workspace is **TallyRepo** only (Tally iOS). Execute commands yourself; keep changes minimal and scoped; match existing Swift style; don’t edit PROJECT_BRIEF / monetisation docs unless I ask. When I say push, push **this** repo’s `main` to `origin`.

---

## 7. Maintaining this file

When the user changes how they want to work, or when major product/architecture decisions land, **update this file** if they ask you to keep agents aligned. Keep it factual and actionable; avoid duplicating entire project briefs — link or summarize instead.
