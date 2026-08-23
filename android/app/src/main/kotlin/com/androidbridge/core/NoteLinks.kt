package com.androidbridge.core

/** A markdown link target inside a Second Brain note. */
sealed interface NoteLink {
    /** Opens outside the app (http, https, mailto, …). */
    data class External(val url: String) : NoteLink

    /** Brain-relative path of another note. */
    data class Note(val path: String) : NoteLink
}

private val URI_SCHEME = Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:")
private val SYNC_CONFLICT = Regex("\\.sync-conflict-\\d{8}-\\d{6}-[A-Z0-9]+")

/**
 * Resolves a markdown link target against the note it appears in.
 * Relative targets resolve against the note's folder; a leading `/` means the
 * brain root; anchors and `%20` are stripped; `.md` is appended when missing.
 */
fun resolveNoteLink(target: String, currentPath: String): NoteLink {
    val trimmed = target.trim()
    if (URI_SCHEME.containsMatchIn(trimmed)) return NoteLink.External(trimmed)
    val decoded = trimmed.substringBefore('#').replace("%20", " ")
    if (decoded.isBlank()) return NoteLink.Note(currentPath)
    val base = if (decoded.startsWith("/")) "" else currentPath.substringBeforeLast('/', "")
    val segments = mutableListOf<String>()
    for (seg in (base.split('/') + decoded.trimStart('/').split('/'))) {
        when {
            seg.isBlank() || seg == "." -> Unit
            seg == ".." -> segments.removeLastOrNull()
            else -> segments.add(seg)
        }
    }
    val joined = segments.joinToString("/")
    return NoteLink.Note(if (joined.endsWith(".md")) joined else "$joined.md")
}

/** Parses `tags: [a, b]` from the note's YAML frontmatter. */
fun parseNoteTags(md: String): List<String> {
    val lines = md.lineSequence().iterator()
    if (!lines.hasNext() || lines.next().trim() != "---") return emptyList()
    while (lines.hasNext()) {
        val line = lines.next().trim()
        if (line == "---") return emptyList()
        if (line.startsWith("tags:")) {
            return line.substringAfter("tags:").trim().removePrefix("[").removeSuffix("]")
                .split(',').map { it.trim() }.filter { it.isNotEmpty() }
        }
    }
    return emptyList()
}

/** True for Syncthing conflict copies like `x.sync-conflict-20260722-101010-ABCDEF7.md`. */
fun isSyncConflictPath(path: String): Boolean = SYNC_CONFLICT.containsMatchIn(path)

/** Maps a conflict copy path back to the note it conflicts with. */
fun conflictBasePath(path: String): String = SYNC_CONFLICT.replace(path, "")

/**
 * First content line matching any search term (frontmatter skipped), for
 * showing context under a search result. Falls back to the first body line.
 */
fun searchSnippet(content: String, terms: List<String>): String {
    val body = stripFrontmatter(content).lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
    val lowered = terms.map { it.lowercase() }
    val match = body.firstOrNull { line -> lowered.any { line.lowercase().contains(it) } }
    return (match ?: body.firstOrNull() ?: "").take(140)
}

private fun stripFrontmatter(md: String): String {
    if (!md.startsWith("---")) return md
    val end = md.indexOf("\n---", 3)
    return if (end == -1) md else md.substring(end + 4)
}
