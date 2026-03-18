---
name: sync-readme
description: Synchronize multi-language README files. Use this skill when the user asks to sync, update, or check the status of README files in different languages (e.g., README.md, README_CN.md, README_JA.md). The skill identifies the latest version and translates other language versions to match.
---

# Sync Readme

Synchronize multi-language README files by identifying the latest version and updating other language versions.

## Workflow

### Step 1: Find All README Files

Use Glob to find all README files in the project root:

```
README*.md
```

Common patterns:
- `README.md` - English (default)
- `README_CN.md` or `README_zh-CN.md` - Chinese
- `README_JA.md` - Japanese
- etc.

### Step 2: Check Status and Identify Latest

Check modification times and git history to determine which file is the most recent:

```bash
# Check file modification times
ls -la README*.md

# Check git commit history for each file
git log -1 --format="%ci %s" -- README.md
git log -1 --format="%ci %s" -- README_CN.md
```

Compare:
1. File modification time (`mtime`)
2. Last git commit date
3. Whether the file has uncommitted changes

**Priority order for determining "latest":**
1. File with uncommitted changes (actively being edited)
2. Most recent git commit
3. Most recent modification time

### Step 3: Handle Ambiguity

If multiple files have similar modification times (within a few minutes) or no clear "latest" can be determined, use AskUserQuestion to ask the user:

> "I found multiple README files with similar timestamps. Which should be the source for synchronization?"
> - README.md (modified: ...)
> - README_CN.md (modified: ...)

### Step 4: Read Source README

Read the content of the latest README file identified in Step 2.

### Step 5: Sync Target README(s)

For each README file that needs to be synchronized:

1. Read the target file to understand the current translation
2. Translate the source content to the target language
3. Write the translated content to the target file

**Translation guidelines:**
- Preserve the same structure (headings, sections, formatting)
- Translate all text content while keeping code blocks and URLs unchanged
- Keep technical terms in English when appropriate
- Maintain any language-specific conventions (e.g., Chinese uses full-width punctuation)

### Step 6: Report Results

Summarize what was done:

```
Synced README files:
- Source: README.md (latest)
- Updated: README_CN.md
- Skipped: README_JA.md (already up to date)
```
