package com.androidbridge

import com.androidbridge.core.NoteLink
import com.androidbridge.core.conflictBasePath
import com.androidbridge.core.isSyncConflictPath
import com.androidbridge.core.parseNoteTags
import com.androidbridge.core.resolveNoteLink
import com.androidbridge.core.searchSnippet
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe

class NoteLinksTest : StringSpec({
    "relative link resolves against the current note's folder" {
        resolveNoteLink("acme/kickoff.md", "work/sela/meetings/index.md") shouldBe
            NoteLink.Note("work/sela/meetings/acme/kickoff.md")
    }

    "parent traversal resolves" {
        resolveNoteLink("../index.md", "work/sela/meetings/acme/kickoff.md") shouldBe
            NoteLink.Note("work/sela/meetings/index.md")
    }

    "leading slash is brain-root absolute" {
        resolveNoteLink("/personal/travel.md", "work/index.md") shouldBe
            NoteLink.Note("personal/travel.md")
    }

    "missing extension gets .md appended" {
        resolveNoteLink("kickoff", "work/index.md") shouldBe NoteLink.Note("work/kickoff.md")
    }

    "anchor and percent-encoding are handled" {
        resolveNoteLink("my%20note.md#section", "work/index.md") shouldBe NoteLink.Note("work/my note.md")
    }

    "http and https links are external" {
        resolveNoteLink("https://example.com/a", "work/index.md") shouldBe
            NoteLink.External("https://example.com/a")
        resolveNoteLink("http://example.com", "work/index.md") shouldBe
            NoteLink.External("http://example.com")
    }

    "frontmatter inline tag array parses" {
        val md = "---\ntitle: X\ntags: [meeting, acme-corp]\n---\n\nBody"
        parseNoteTags(md) shouldBe listOf("meeting", "acme-corp")
    }

    "empty or missing tags yield empty list" {
        parseNoteTags("---\ntags: []\n---\nBody") shouldBe emptyList()
        parseNoteTags("no frontmatter") shouldBe emptyList()
    }

    "sync conflict file names are detected and mapped to their base note" {
        val conflict = "work/notes.sync-conflict-20260722-101010-ABCDEF7.md"
        isSyncConflictPath(conflict) shouldBe true
        isSyncConflictPath("work/notes.md") shouldBe false
        conflictBasePath(conflict) shouldBe "work/notes.md"
    }

    "snippet picks first line matching a term, skipping frontmatter" {
        val md = "---\ntags: [x]\n---\n# Title\nAlpha line here\nBeta target line\n"
        searchSnippet(md, listOf("target")) shouldBe "Beta target line"
    }

    "snippet falls back to first body line when no term matches" {
        val md = "---\ntags: [x]\n---\n# Title\nFirst body line\n"
        searchSnippet(md, listOf("zzz")) shouldBe "# Title"
    }
})
