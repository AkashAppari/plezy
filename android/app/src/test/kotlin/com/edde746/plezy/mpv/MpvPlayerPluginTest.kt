package com.edde746.plezy.mpv

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class MpvPlayerPluginTest {

  @Test
  fun commandWithoutCoreReportsNotInitialized() {
    val result = RecordingResult()

    MpvPlayerPlugin().onMethodCall(
      MethodCall("command", mapOf("args" to listOf("seek", "1", "absolute"))),
      result
    )

    assertEquals("NOT_INITIALIZED", result.errorCode)
    assertNull(result.successValue)
  }

  @Test
  fun setLogLevelReportsUnsupported() {
    val result = RecordingResult()

    MpvPlayerPlugin().onMethodCall(
      MethodCall("setLogLevel", mapOf("level" to "warn")),
      result
    )

    assertEquals("UNSUPPORTED", result.errorCode)
    assertNull(result.successValue)
  }

  private class RecordingResult : MethodChannel.Result {
    var successValue: Any? = null
    var errorCode: String? = null

    override fun success(result: Any?) {
      successValue = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
      this.errorCode = errorCode
    }

    override fun notImplemented() = Unit
  }
}
