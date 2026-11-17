package com.dic2phone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class FilesTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun replacesExistingFile() {
        val f = tmp.newFile("a.json").apply { writeText("old") }
        val t = File(tmp.root, "a.json.tmp").apply { writeText("new") }
        assertTrue(f.replaceWith(t))
        assertEquals("new", f.readText())
        assertFalse(t.exists())
    }

    @Test fun createsMissingFile() {
        val f = File(tmp.root, "b.json")
        val t = File(tmp.root, "b.json.tmp").apply { writeText("x") }
        assertTrue(f.replaceWith(t))
        assertEquals("x", f.readText())
    }
}
