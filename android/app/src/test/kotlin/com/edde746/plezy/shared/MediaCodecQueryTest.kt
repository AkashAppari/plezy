package com.edde746.plezy.shared

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaCodecQueryTest {

  @Test
  fun recognizesKnownPlatformAndFfmpegSoftwareCodecNames() {
    listOf(
      "OMX.google.h264.decoder",
      "OMX.FFMPEG.VIDEO.DECODER",
      "c2.android.avc.decoder",
      "c2.google.av1.decoder",
      "c2.ffmpeg.vp9.decoder",
      "vendor.video.sw.decoder"
    ).forEach { name ->
      assertTrue("expected software codec: $name", MediaCodecQuery.isSoftwareCodecName(name))
    }
  }

  @Test
  fun doesNotMisclassifyVendorHardwareCodecNames() {
    listOf(
      "OMX.qcom.video.decoder.avc",
      "OMX.MTK.VIDEO.DECODER.HEVC",
      "c2.qti.avc.decoder",
      "c2.exynos.hevc.decoder"
    ).forEach { name ->
      assertFalse("expected hardware codec: $name", MediaCodecQuery.isSoftwareCodecName(name))
    }
  }
}
