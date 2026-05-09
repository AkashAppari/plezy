import AVFoundation
import Cocoa
import Libmpv

/// Core MPV player using AVFoundation sample-buffer rendering.
class MpvPlayerCore: MpvPlayerCoreBase {

  private weak var window: NSWindow?
  private var playbackActivity: NSObjectProtocol?
  private var layerHiddenForOcclusion = false
  private var isDisposed = false

  func initialize(in window: NSWindow) -> Bool {
    guard !isInitialized else {
      print("[MpvPlayerCore] Already initialized")
      return true
    }

    guard let contentView = window.contentView else {
      print("[MpvPlayerCore] No content view")
      return false
    }

    self.window = window

    let layer = MpvVideoLayer()
    layer.frame = contentView.bounds
    if let screen = window.screen ?? NSScreen.main {
      layer.contentsScale = screen.backingScaleFactor
    }
    layer.isOpaque = true
    layer.backgroundColor = NSColor.black.cgColor
    layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    layer.videoGravity = .resizeAspect

    videoLayer = layer
    updateEDRMode(sigPeak: lastSigPeak)

    contentView.wantsLayer = true
    contentView.layer?.addSublayer(layer)

    print("[MpvPlayerCore] Video layer added, frame: \(layer.frame)")

    guard setupMpv() else {
      print("[MpvPlayerCore] Failed to setup MPV")
      layer.removeFromSuperlayer()
      videoLayer = nil
      return false
    }

    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(windowDidEnterFullScreen),
      name: NSWindow.didEnterFullScreenNotification,
      object: window
    )
    center.addObserver(
      self,
      selector: #selector(windowDidExitFullScreen),
      name: NSWindow.didExitFullScreenNotification,
      object: window
    )
    center.addObserver(
      self,
      selector: #selector(windowOcclusionDidChange),
      name: NSWindow.didChangeOcclusionStateNotification,
      object: window
    )

    isInitialized = true
    print("[MpvPlayerCore] Initialized successfully with MPV")
    return true
  }

  override func configurePlatformMpvOptions() {
    guard let mpv else { return }
    checkError(mpv_set_option_string(mpv, "avfoundation-composite-osd", "no"))
    checkError(mpv_set_option_string(mpv, "ao", "avfoundation,coreaudio"))
  }

  func reattachVideoLayer() {
    guard let videoLayer, let contentView = window?.contentView else { return }

    if videoLayer.superlayer == nil {
      contentView.wantsLayer = true
      contentView.layer?.insertSublayer(videoLayer, at: 0)
      videoLayer.frame = contentView.bounds
      if let screen = window?.screen ?? NSScreen.main {
        videoLayer.contentsScale = screen.backingScaleFactor
      }
    }

    print("[MpvPlayerCore] Video layer reattached to window")
  }

  func forceDraw() {
    command(["seek", "0", "relative+exact"])
  }

  private var isVisible = false
  private var pausedState = true

  func setVisible(_ visible: Bool) {
    guard let videoLayer, !isPipActive else { return }

    isVisible = visible
    isBackgrounded = !visible

    if visible {
      videoLayer.removeFromSuperlayer()
      if let superlayer = window?.contentView?.layer {
        superlayer.insertSublayer(videoLayer, at: 0)
      }
      beginPlaybackActivity()
    } else {
      endPlaybackActivity()
    }

    videoLayer.isHidden = !visible
    print("[MpvPlayerCore] setVisible(\(visible))")
  }

  func setPaused(_ paused: Bool) {
    pausedState = paused
    if paused {
      endPlaybackActivity()
    } else if isVisible {
      beginPlaybackActivity()
    }
  }

  func updateFrame(_ frame: CGRect? = nil) {
    guard let videoLayer, !isPipActive else { return }

    if let frame {
      videoLayer.frame = frame
    } else if let contentView = window?.contentView {
      videoLayer.frame = contentView.bounds
    }

    if let screen = window?.screen ?? NSScreen.main {
      videoLayer.contentsScale = screen.backingScaleFactor
    }
    updateEDRMode(sigPeak: lastSigPeak)

  }

  override func updateEDRMode(sigPeak: Double) {
    guard let videoLayer else { return }

    let hdrEnabled = self.hdrEnabled
    var currentHeadroom: CGFloat = 1.0
    var potentialHeadroom: CGFloat = 1.0
    if let screen = window?.screen ?? NSScreen.main {
      currentHeadroom = screen.maximumExtendedDynamicRangeColorComponentValue
      potentialHeadroom = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
    }

    let signalHeadroom = CGFloat(max(sigPeak, 1.0))
    let contentHeadroom = min(signalHeadroom, potentialHeadroom)
    let shouldEnableEDR = hdrEnabled && sigPeak > 1.0 && potentialHeadroom > 1.0
    if #available(macOS 26.0, *) {
      videoLayer.preferredDynamicRange = shouldEnableEDR ? .high : .standard
      videoLayer.contentsHeadroom = shouldEnableEDR ? contentHeadroom : 0
    }
    if #available(macOS 15.0, *) {
      videoLayer.toneMapMode = shouldEnableEDR ? .ifSupported : .automatic
    }
    if #available(macOS 14.0, *) {
      videoLayer.wantsExtendedDynamicRangeContent = shouldEnableEDR
    }

  }

  func dispose() {
    if isDisposed { return }
    isDisposed = true

    endPlaybackActivity()
    NotificationCenter.default.removeObserver(self)
    disposeSharedState(destroySynchronously: false)

    videoLayer?.removeFromSuperlayer()
    videoLayer = nil
    isInitialized = false
    print("[MpvPlayerCore] Disposed")
  }

  deinit {
    dispose()
  }

  @objc private func windowDidEnterFullScreen(_ notification: Notification) {
    guard !isPipActive else { return }
    updateFrame()
  }

  @objc private func windowDidExitFullScreen(_ notification: Notification) {
    guard !isPipActive else { return }
    updateFrame()
  }

  @objc private func windowOcclusionDidChange(_ notification: Notification) {
    guard let videoLayer, mpv != nil, !isPipActive else { return }

    let windowVisible = window?.occlusionState.contains(.visible) ?? true
    if !windowVisible && !layerHiddenForOcclusion {
      print("[MpvPlayerCore] Window occluded - hiding video layer")
      videoLayer.isHidden = true
      layerHiddenForOcclusion = true
      isBackgrounded = true
      endPlaybackActivity()
    } else if windowVisible && layerHiddenForOcclusion {
      print("[MpvPlayerCore] Window visible - showing video layer")
      layerHiddenForOcclusion = false
      videoLayer.isHidden = false
      isBackgrounded = false
      if !pausedState {
        beginPlaybackActivity()
      }
    }
  }

  private func beginPlaybackActivity() {
    guard playbackActivity == nil else { return }
    playbackActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .latencyCritical],
      reason: "Video playback"
    )
    print("[MpvPlayerCore] Began playback activity assertion")
  }

  private func endPlaybackActivity() {
    guard let playbackActivity else { return }
    ProcessInfo.processInfo.endActivity(playbackActivity)
    self.playbackActivity = nil
    print("[MpvPlayerCore] Ended playback activity assertion")
  }
}
