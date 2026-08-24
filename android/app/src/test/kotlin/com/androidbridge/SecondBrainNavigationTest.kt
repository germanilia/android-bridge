package com.androidbridge

import com.androidbridge.core.SecondBrainRefreshGate
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe

class SecondBrainNavigationTest : StringSpec({
    "back from editor returns to preview when clean" {
        secondBrainBack(SecondBrainDestination.EDITOR, dirty = false) shouldBe SecondBrainBack.Preview
    }

    "back from dirty editor asks before discarding" {
        secondBrainBack(SecondBrainDestination.EDITOR, dirty = true) shouldBe SecondBrainBack.ConfirmDiscard
    }

    "back from preview returns to library" {
        secondBrainBack(SecondBrainDestination.PREVIEW, dirty = false) shouldBe SecondBrainBack.Library
    }

    "back from preview asks before discarding unsaved edits" {
        secondBrainBack(SecondBrainDestination.PREVIEW, dirty = true) shouldBe SecondBrainBack.ConfirmDiscard
    }

    "back from library exits only the Second Brain destination" {
        secondBrainBack(SecondBrainDestination.LIBRARY, dirty = false) shouldBe SecondBrainBack.Bridge
    }

    "refresh gate rejects overlapping scans and reopens after completion" {
        val gate = SecondBrainRefreshGate()
        gate.tryStart() shouldBe true
        gate.tryStart() shouldBe false
        gate.finish()
        gate.tryStart() shouldBe true
    }
})
