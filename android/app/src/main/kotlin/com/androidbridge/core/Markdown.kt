package com.androidbridge.core

/**
 * Minimal block-level markdown model used to render Second Brain notes.
 *
 * Splitting a note into blocks lets the UI render it in a LazyColumn: only the
 * visible blocks are laid out, so a very long note no longer blocks the main
 * thread the way a single giant Text/TextField does.
 */
sealed interface MdBlock {
    data class Heading(val level: Int, val text: String) : MdBlock
    data class Paragraph(val text: String) : MdBlock
    data class ListItem(val text: String, val indent: Int, val ordered: Boolean) : MdBlock
    data class Quote(val text: String) : MdBlock
    data class Code(val text: String) : MdBlock
    data class Table(val rows: List<List<String>>) : MdBlock
    data object Divider : MdBlock
}

private val HEADING = Regex("^(#{1,6})\\s+(.*)$")
private val UNORDERED = Regex("^(\\s*)[-*+]\\s+(.*)$")
private val ORDERED = Regex("^(\\s*)\\d+[.)]\\s+(.*)$")
private val RULE = Regex("^\\s*([-*_])(\\s*\\1){2,}\\s*$")
private val TABLE_SEPARATOR = Regex("^\\s*\\|?\\s*:?-{3,}:?\\s*(\\|\\s*:?-{3,}:?\\s*)+\\|?\\s*$")

fun parseMarkdown(md: String): List<MdBlock> {
    val blocks = mutableListOf<MdBlock>()
    val lines = md.replace("\r\n", "\n").split("\n")
    val para = StringBuilder()

    fun flushParagraph() {
        if (para.isNotBlank()) blocks.add(MdBlock.Paragraph(para.toString().trim()))
        para.setLength(0)
    }

    var i = 0
    while (i < lines.size) {
        val line = lines[i]
        if (line.trimStart().startsWith("```")) {
            flushParagraph()
            i++
            val fence = mutableListOf<String>()
            while (i < lines.size && !lines[i].trimStart().startsWith("```")) {
                fence.add(lines[i])
                i++
            }
            i++ // consume the closing fence (or run off the end for an unterminated block)
            blocks.add(MdBlock.Code(fence.joinToString("\n")))
            continue
        }

        val heading = HEADING.find(line)
        val ordered = ORDERED.find(line)
        val unordered = UNORDERED.find(line)
        if (i + 1 < lines.size && tableRow(line) != null && TABLE_SEPARATOR.matches(lines[i + 1])) {
            flushParagraph()
            val rows = mutableListOf(tableRow(line)!!)
            i += 2
            while (i < lines.size) {
                val row = tableRow(lines[i]) ?: break
                rows.add(row)
                i++
            }
            blocks.add(MdBlock.Table(rows))
            continue
        }
        when {
            line.isBlank() -> flushParagraph()
            RULE.matches(line) -> { flushParagraph(); blocks.add(MdBlock.Divider) }
            heading != null -> { flushParagraph(); blocks.add(MdBlock.Heading(heading.groupValues[1].length, heading.groupValues[2].trim())) }
            ordered != null -> { flushParagraph(); blocks.add(MdBlock.ListItem(ordered.groupValues[2].trim(), ordered.groupValues[1].length, true)) }
            unordered != null -> { flushParagraph(); blocks.add(MdBlock.ListItem(unordered.groupValues[2].trim(), unordered.groupValues[1].length, false)) }
            line.trimStart().startsWith(">") -> { flushParagraph(); blocks.add(MdBlock.Quote(line.trimStart().removePrefix(">").trim())) }
            else -> { if (para.isNotEmpty()) para.append(' '); para.append(line.trim()) }
        }
        i++
    }
    flushParagraph()
    return blocks
}

private fun tableRow(line: String): List<String>? {
    val trimmed = line.trim()
    if (!trimmed.contains('|')) return null
    return trimmed.trim('|').split('|').map { it.trim() }.takeIf { it.size > 1 }
}
