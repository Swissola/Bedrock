# Publishing selected docs to a team wiki (optional)

> **Scope:** if your organization already has a separate documentation platform (Confluence, Notion, SharePoint, etc.) that other teams read without ever touching git or Obsidian, you may want a *subset* of this vault's docs mirrored out there — read-only, generated from the vault, not edited independently on both sides. This is entirely optional and unrelated to the vault working on its own.

## The pattern

1. **The vault stays the source of truth.** Nobody edits the wiki copy directly — every wiki page is generated from a specific `.md` file in this repo.
2. **A small manifest lists which files get published, and under what title.** `tools/wiki-publish.example.json` is a starting point:

   ```json
   {
     "space": "YOUR-SPACE-KEY",
     "documents": [
       {
         "source": "docs/mcp-setup.md",
         "title": "Obsidian Set Up Guide"
       },
       {
         "source": "runbooks/daily-workflow.md",
         "title": "Obsidian Daily Workflow",
         "parent": "Obsidian Set Up Guide"
       }
     ]
   }
   ```

   Copy it to `wiki-publish.json`, point `source` at whichever files you actually want mirrored, and set `space` to your real space/site key.

3. **A prepare script turns each source file into wiki-ready output.** `tools/prepare-wiki-docs.ps1` reads the manifest, strips the leading `# Title` heading (the wiki page title already carries that), and stages the result into `.wiki-stage/` (already in `.gitignore`).
4. **A CI job runs the prepare script and pushes the result to your wiki**, on a schedule or on every merge to your default branch, however your CI platform does that. Two minimal examples:

   **GitHub Actions** (`.github/workflows/publish-docs.yml`):
   ```yaml
   name: Publish docs
   on:
     push:
       branches: [main]
   jobs:
     publish:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - name: Prepare wiki docs
           shell: pwsh
           run: ./tools/prepare-wiki-docs.ps1
         - name: Publish
           run: |
             # Replace with your actual wiki's publish step/action —
             # this is intentionally left as a placeholder since it
             # depends entirely on which platform you're publishing to.
             echo "Publish .wiki-stage/ contents to your wiki here"
   ```

   **Jenkins** (`Jenkinsfile`):
   ```groovy
   pipeline {
       agent any
       stages {
           stage('Publish Documentation') {
               when {
                   branch 'main' // confirm this matches your repo's actual default branch
               }
               steps {
                   powershell 'tools/prepare-wiki-docs.ps1'
                   // Replace with your actual publish step, e.g. a
                   // Confluence-publisher plugin step pointed at .wiki-stage/
               }
           }
       }
   }
   ```

## Why this is worth doing deliberately, not by default

Most teams don't need this — if everyone who needs these docs already has Obsidian and git, mirroring adds a second copy to keep honest for no real benefit. It earns its keep specifically when there's a real audience who won't install Obsidian or touch git, but already lives in your existing wiki platform day to day.

## Gotchas worth knowing before you build this out

- **Markdown-to-wiki conversion can be lossy in ways that are easy to miss.** If your wiki's importer round-trips markdown through its own escaping, literal backslash-containing text (a Windows path, a regex) is a common casualty — verify a converted page actually reads correctly, don't assume a clean-looking diff means a clean result.
- **Always fetch the page back after publishing to confirm the write landed as intended** — don't trust a publish call's success response alone.
- **Check the live wiki page for content the vault doesn't have, before overwriting it**, if there's any chance someone edited the wiki copy directly (which defeats the "vault is the source of truth" premise, but happens). Pull anything newer back into the source `.md` file first, or a publish silently destroys it — including a title changed directly on the wiki, if your publish step also overwrites titles.
- **Only include `parent` in the manifest when you actually want to (re)parent a page** — omitting it for a page that already exists under a different parent avoids accidentally moving it.

## Related

- [`../runbooks/adopting-for-a-new-team.md`](../runbooks/adopting-for-a-new-team.md) — remember to update `wiki-publish.json` with your own space/site key if you adopt this, not a previous team's
