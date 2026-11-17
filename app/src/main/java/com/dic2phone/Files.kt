package com.dic2phone

import java.io.File

/**
 * Puts [tmp] in place of this file. On Android a rename replaces the target atomically, so a
 * reader sees the old file or the new one, never half of one.
 * @return false if it couldn't.
 */
fun File.replaceWith(tmp: File): Boolean = tmp.renameTo(this) || (delete() && tmp.renameTo(this))
