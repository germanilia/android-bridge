package com.androidbridge

import com.androidbridge.core.MdBlock
import com.androidbridge.core.parseMarkdown
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.types.shouldBeInstanceOf

class MarkdownTest : StringSpec({
    "headings capture level and text" {
        val blocks = parseMarkdown("# Title\n### Sub")
        blocks shouldBe listOf(
            MdBlock.Heading(1, "Title"),
            MdBlock.Heading(3, "Sub"),
        )
    }

    "consecutive lines merge into one paragraph, blank line splits" {
        val blocks = parseMarkdown("one\ntwo\n\nthree")
        blocks shouldBe listOf(
            MdBlock.Paragraph("one two"),
            MdBlock.Paragraph("three"),
        )
    }

    "unordered and ordered list items keep indent and order flag" {
        val blocks = parseMarkdown("- a\n  - b\n1. c")
        blocks shouldBe listOf(
            MdBlock.ListItem("a", 0, false),
            MdBlock.ListItem("b", 2, false),
            MdBlock.ListItem("c", 0, true),
        )
    }

    "fenced code is one block preserving inner lines and skips markers" {
        val blocks = parseMarkdown("```\nx = 1\n# not a heading\n```")
        blocks shouldBe listOf(MdBlock.Code("x = 1\n# not a heading"))
    }

    "horizontal rule becomes a divider" {
        val blocks = parseMarkdown("above\n\n---\n\nbelow")
        blocks shouldBe listOf(
            MdBlock.Paragraph("above"),
            MdBlock.Divider,
            MdBlock.Paragraph("below"),
        )
    }

    "blockquote strips the marker" {
        val blocks = parseMarkdown("> quoted line")
        blocks shouldBe listOf(MdBlock.Quote("quoted line"))
    }

    "pipe tables become table blocks" {
        val blocks = parseMarkdown("| A | B |\n|---|---|\n| one | two |")
        blocks shouldBe listOf(MdBlock.Table(listOf(listOf("A", "B"), listOf("one", "two"))))
    }

    "a long note splits into many blocks so rendering can stay lazy" {
        val note = (1..500).joinToString("\n\n") { "Paragraph $it" }
        val blocks = parseMarkdown(note)
        blocks.size shouldBe 500
        blocks.first().shouldBeInstanceOf<MdBlock.Paragraph>()
    }
})
