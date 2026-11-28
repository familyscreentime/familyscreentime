package org.familyscreentime

import org.junit.Test

/** The diagnostic log is called from every component: it must never throw. */
class DiagTest {
    @Test
    fun logsWithoutCallingItself() {
        // 0.32.2 crashed here: Diag.i called Diag.i (StackOverflowError).
        Diag.i("a line")
        Diag.w("a warning")
        Diag.w("a failure", IllegalStateException("test"))
    }
}
