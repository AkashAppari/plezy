package com.edde746.plezy.shared

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import java.util.Locale

/** Canonical decoder lookup and hardware classification for native playback. */
internal object MediaCodecQuery {
  fun findHardwareDecoder(
    mimeType: String,
    codecKind: Int = MediaCodecList.REGULAR_CODECS,
    predicate: (MediaCodecInfo, String) -> Boolean = { _, _ -> true }
  ): MediaCodecInfo? {
    for (info in MediaCodecList(codecKind).codecInfos) {
      if (info.isEncoder || !isHardwareAccelerated(info)) continue
      for (type in info.supportedTypes) {
        if (type.equals(mimeType, ignoreCase = true) && predicate(info, type)) {
          return info
        }
      }
    }
    return null
  }

  fun isHardwareAccelerated(info: MediaCodecInfo): Boolean {
    // API 29 added the manufacturer-provided classification. Older releases
    // expose only component names, so retain the legacy software-name fallback.
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      info.isHardwareAccelerated
    } else {
      !isSoftwareCodecName(info.name)
    }
  }

  internal fun isSoftwareCodecName(name: String): Boolean {
    val normalized = name.lowercase(Locale.ROOT)
    return normalized.startsWith("omx.google.") ||
      normalized.startsWith("omx.ffmpeg.") ||
      normalized.startsWith("c2.android.") ||
      normalized.startsWith("c2.google.") ||
      normalized.startsWith("c2.ffmpeg.") ||
      normalized.contains(".sw.")
  }
}
