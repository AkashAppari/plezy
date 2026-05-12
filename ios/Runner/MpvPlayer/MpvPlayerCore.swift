import AVFoundation
import QuartzCore
import UIKit

/// Core MPV player using AVFoundation sample-buffer rendering for iOS/tvOS.
class MpvPlayerCore: MpvPlayerCoreBase {

  private var containerView: UIView?
  private weak var window: UIWindow?
  private var mainBlankView: UIView?
  private var isVisible = false

  var isPipStarting = false

  func initialize(in window: UIWindow) -> Bool {
    guard !isInitialized else {
      print("[MpvPlayerCore] Already initialized")
      return true
    }

    self.window = window

    let container = UIView(frame: window.bounds)
    container.backgroundColor = .black
    container.isUserInteractionEnabled = false

    let layer = MpvVideoLayer()
    layer.frame = container.bounds
    layer.contentsScale = window.screen.nativeScale
    layer.isOpaque = true
    layer.backgroundColor = UIColor.black.cgColor
    layer.videoGravity = .resizeAspect

    container.layer.addSublayer(layer)
    containerView = container
    videoLayer = layer

    window.insertSubview(container, at: 0)

    guard setupMpv() else {
      print("[MpvPlayerCore] Failed to setup MPV")
      layer.removeFromSuperlayer()
      container.removeFromSuperview()
      videoLayer = nil
      containerView = nil
      return false
    }

    setupNotifications()
    #if os(iOS)
      ExternalDisplayManager.shared.attach(core: self)
    #endif

    isInitialized = true
    print("[MpvPlayerCore] Initialized successfully with MPV")
    return true
  }

  var sampleBufferDisplayLayer: MpvVideoLayer? { videoLayer }

  func setVisible(_ visible: Bool) {
    guard containerView != nil else { return }

    isVisible = visible
    if visible { refreshExternalDisplayAttachment() }
    setContainerHidden(!visible)
    if !visible { mainBlankView?.isHidden = true }
  }

  func updateFrame(_ frame: CGRect? = nil) {
    guard let videoLayer, let containerView else { return }

    withoutLayerAnimations {
      if let frame {
        containerView.frame = frame
        videoLayer.frame = containerView.bounds
      } else if let superview = containerView.superview {
        containerView.frame = superview.bounds
        videoLayer.frame = containerView.bounds
      } else if let window {
        containerView.frame = window.bounds
        videoLayer.frame = containerView.bounds
      }

      mainBlankView?.frame = window?.bounds ?? .zero

      let screen = containerView.window?.screen ?? window?.screen ?? UIScreen.main
      let scale = screen.nativeScale > 0 ? screen.nativeScale : screen.scale
      videoLayer.contentsScale = scale
    }
  }

  func externalDisplayDidChange() {
    refreshExternalDisplayAttachment()
  }

  private func refreshExternalDisplayAttachment() {
    guard let containerView else { return }

    let externalSuperview = externalVideoSuperview

    if let externalSuperview {
      moveContainerView(to: externalSuperview)
      setMainBlankViewVisible(true)
    } else if isVisible, let window {
      moveContainerView(to: window)
      setMainBlankViewVisible(false)
    } else {
      setMainBlankViewVisible(false)
    }

    setContainerHidden(!isVisible)
    updateFrame()
  }

  private var externalVideoSuperview: UIView? {
    #if os(iOS)
      isVisible && !isPipActive && !isPipStarting
        ? ExternalDisplayManager.shared.videoSuperview
        : nil
    #else
      nil
    #endif
  }

  private func moveContainerView(to superview: UIView) {
    guard let containerView else { return }

    withoutLayerAnimations {
      if containerView.superview !== superview {
        containerView.removeFromSuperview()
        superview.insertSubview(containerView, at: 0)
      } else if superview.subviews.first !== containerView {
        superview.insertSubview(containerView, at: 0)
      }

      containerView.frame = superview.bounds
      containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
  }

  private func setMainBlankViewVisible(_ visible: Bool) {
    guard visible, let window else {
      mainBlankView?.removeFromSuperview()
      mainBlankView = nil
      return
    }

    let blankView = mainBlankView ?? UIView(frame: window.bounds)
    withoutLayerAnimations {
      blankView.backgroundColor = .black
      blankView.isUserInteractionEnabled = false
      blankView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      blankView.frame = window.bounds

      if blankView.superview !== window {
        blankView.removeFromSuperview()
        window.insertSubview(blankView, at: 0)
      } else if window.subviews.first !== blankView {
        window.insertSubview(blankView, at: 0)
      }

      blankView.isHidden = false
    }
    mainBlankView = blankView
  }

  private func setContainerHidden(_ hidden: Bool) {
    withoutLayerAnimations {
      containerView?.isHidden = hidden
    }
  }

  private func withoutLayerAnimations(_ updates: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    updates()
    CATransaction.commit()
  }

  /// Nudge mpv to present the current paused frame after leaving PiP.
  func forceDraw() {
    command(["seek", "0", "relative+exact"])
  }

  override func updateEDRMode(sigPeak: Double) {
    guard let videoLayer else { return }

    let hdrEnabled = self.hdrEnabled
    var edrHeadroom: CGFloat = 1.0
    #if os(iOS)
      if #available(iOS 17.0, *) {
        edrHeadroom = containerView?.window?.screen.potentialEDRHeadroom ?? 1.0
        withoutLayerAnimations {
          videoLayer.wantsExtendedDynamicRangeContent =
            hdrEnabled && sigPeak > 1.0 && edrHeadroom > 1.0
        }
      }
    #endif

    let shouldEnableEDR = hdrEnabled && sigPeak > 1.0 && edrHeadroom > 1.0
    print(
      "[MpvPlayerCore] EDR mode: \(shouldEnableEDR) (hdrEnabled: \(hdrEnabled), sigPeak: \(sigPeak), headroom: \(edrHeadroom))"
    )
  }

  override func updateDisplayCriteria(
    doviProfile: Int64,
    doviLevel: Int64,
    fps: Double,
    width: Int32,
    height: Int32,
    sigPeak: Double
  ) {
    #if os(tvOS)
      guard let window = containerView?.window ?? self.window else { return }
      let displayManager = window.avDisplayManager
      guard displayManager.isDisplayCriteriaMatchingEnabled else { return }

      let refreshRate = Float(fps > 0 ? fps : 0)

      if doviProfile > 0, width > 0, height > 0, #available(tvOS 17.0, *) {
        // Profile 8.x always carries a compatibility id; profile 5 has none.
        // We assume bl_signal_compatibility_id = 1 (HDR10 base) for profile 8
        // because mpv does not expose the compat id and that's by far the
        // most common case (and matches the user's reported content).
        let compat: UInt8 = doviProfile == 8 ? 1 : 0
        if let fd = Self.makeDolbyVisionFormatDescription(
          width: width,
          height: height,
          profile: UInt8(truncatingIfNeeded: doviProfile),
          level: UInt8(truncatingIfNeeded: doviLevel),
          compatibility: compat)
        {
          let criteria = AVDisplayCriteria(refreshRate: refreshRate, formatDescription: fd)
          displayManager.preferredDisplayCriteria = criteria
          print(
            "[MpvPlayerCore] preferredDisplayCriteria set to Dolby Vision (profile: \(doviProfile), level: \(doviLevel), fps: \(refreshRate), \(width)x\(height))"
          )
          return
        }
        print("[MpvPlayerCore] Failed to synthesize DV CMVideoFormatDescription; clearing criteria")
      }

      // Non-DV content (HDR10 / SDR) or DV FD synthesis failed: clear the
      // hint and let tvOS auto-pick from the AVSampleBufferDisplayLayer's
      // actual sample-buffer attachments (BT.2020 + PQ for HDR10).
      if displayManager.preferredDisplayCriteria != nil {
        displayManager.preferredDisplayCriteria = nil
        print("[MpvPlayerCore] preferredDisplayCriteria cleared (sigPeak: \(sigPeak))")
      }
    #endif
  }

  #if os(tvOS)
    /// Build a synthetic 'dvh1' `CMVideoFormatDescription` from the Dolby Vision
    /// metadata mpv exposes. Used solely as a hint object for
    /// `AVDisplayCriteria(refreshRate:formatDescription:)` — it is never
    /// enqueued onto the sample-buffer layer.
    private static func makeDolbyVisionFormatDescription(
      width: Int32,
      height: Int32,
      profile: UInt8,
      level: UInt8,
      compatibility: UInt8
    ) -> CMVideoFormatDescription? {
      // 24-byte Dolby Vision configuration record (dvcC ≤ profile 7, dvvC ≥ 8).
      // Layout from ETSI TS 103 572 §7.1.1 — same packing as FFmpeg's
      // videotoolbox_dovi_extradata_create (in 0002 patch):
      //   [0]     dv_version_major (= 1)
      //   [1]     dv_version_minor (= 0)
      //   [2..3]  big-endian uint16: profile<<9 | level<<3 | rpu<<2 | el<<1 | bl
      //   [4]     compatibility<<4 | md_compression<<2
      //   [5..23] reserved zero
      var dovi = [UInt8](repeating: 0, count: 24)
      dovi[0] = 1
      dovi[1] = 0
      let flags: UInt16 =
        (UInt16(profile) & 0x7f) << 9
        | (UInt16(level) & 0x3f) << 3
        | (1 << 2)  // rpu_present_flag
        | (1 << 0)  // bl_present_flag
      dovi[2] = UInt8((flags >> 8) & 0xff)
      dovi[3] = UInt8(flags & 0xff)
      dovi[4] = (compatibility & 0x0f) << 4

      // CoreMedia does not export a typed
      // `kCMFormatDescriptionExtension_DolbyVision…` constant. The well-known
      // CFString key is the four-char box name VideoToolbox/AVFoundation
      // expect (same key FFmpeg writes in 0002-videotoolbox-add-dolby-vision-hevc-format.patch).
      let recordKey: CFString = (profile > 7 ? "dvvC" : "dvcC") as CFString

      let extensions: [CFString: Any] = [
        recordKey: Data(dovi) as CFData,
        kCMFormatDescriptionExtension_ColorPrimaries:
          kCMFormatDescriptionColorPrimaries_ITU_R_2020,
        kCMFormatDescriptionExtension_TransferFunction:
          kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
        kCMFormatDescriptionExtension_YCbCrMatrix:
          kCMFormatDescriptionYCbCrMatrix_ITU_R_2020,
      ]

      var fd: CMVideoFormatDescription?
      let status = CMVideoFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        codecType: kCMVideoCodecType_DolbyVisionHEVC,  // 'dvh1'
        width: width,
        height: height,
        extensions: extensions as CFDictionary,
        formatDescriptionOut: &fd
      )
      return status == noErr ? fd : nil
    }
  #endif

  func dispose() {
    NotificationCenter.default.removeObserver(self)
    #if os(iOS)
      ExternalDisplayManager.shared.detach(core: self)
    #endif
    disposeSharedState(destroySynchronously: false)

    videoLayer?.removeFromSuperlayer()
    videoLayer = nil
    containerView?.removeFromSuperview()
    containerView = nil
    mainBlankView?.removeFromSuperview()
    mainBlankView = nil
    isInitialized = false
    print("[MpvPlayerCore] Disposed")
  }

  deinit {
    dispose()
  }

  private func setupNotifications() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(enterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(enterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
  }

  @objc private func enterBackground() {
    if isPipActive || isPipStarting {
      print("[MpvPlayerCore] Entering background - PiP active/starting, keeping video")
      return
    }

    print("[MpvPlayerCore] Entering background - disabling video")
    setProperty("vid", value: "no")
  }

  @objc private func enterForeground() {
    if isPipActive {
      print("[MpvPlayerCore] Entering foreground - PiP active, skipping vid restore")
      return
    }

    print("[MpvPlayerCore] Entering foreground - enabling video")
    setProperty("vid", value: "auto")
  }
}
