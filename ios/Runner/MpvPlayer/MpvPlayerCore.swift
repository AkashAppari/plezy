import AVFoundation
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
    container.backgroundColor = .clear
    container.isUserInteractionEnabled = false

    let layer = MpvVideoLayer()
    layer.frame = container.bounds
    layer.contentsScale = window.screen.nativeScale
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
    guard let containerView else { return }

    isVisible = visible
    if visible { refreshExternalDisplayAttachment() }
    containerView.isHidden = !visible
    if !visible { mainBlankView?.isHidden = true }
  }

  func updateFrame(_ frame: CGRect? = nil) {
    guard let videoLayer, let containerView else { return }

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

    containerView.isHidden = !isVisible
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

    if containerView.superview !== superview {
      containerView.removeFromSuperview()
    }
    containerView.frame = superview.bounds
    containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    superview.insertSubview(containerView, at: 0)
  }

  private func setMainBlankViewVisible(_ visible: Bool) {
    guard visible, let window else {
      mainBlankView?.removeFromSuperview()
      mainBlankView = nil
      return
    }

    let blankView = mainBlankView ?? UIView(frame: window.bounds)
    blankView.backgroundColor = .black
    blankView.isUserInteractionEnabled = false
    blankView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blankView.frame = window.bounds

    if blankView.superview !== window {
      blankView.removeFromSuperview()
      window.insertSubview(blankView, at: 0)
    } else {
      window.insertSubview(blankView, at: 0)
    }

    blankView.isHidden = false
    mainBlankView = blankView
  }

  /// Nudge mpv to present the current paused frame after leaving PiP.
  func forceDraw() {
    command(["seek", "0", "relative+exact"])
  }

  override func updateEDRMode(sigPeak: Double) {
    guard let videoLayer else { return }

    var edrHeadroom: CGFloat = 1.0
    #if os(iOS)
      if #available(iOS 17.0, *) {
        edrHeadroom = containerView?.window?.screen.potentialEDRHeadroom ?? 1.0
        videoLayer.wantsExtendedDynamicRangeContent = hdrEnabled && sigPeak > 1.0 && edrHeadroom > 1.0
      }
    #endif

    let shouldEnableEDR = hdrEnabled && sigPeak > 1.0 && edrHeadroom > 1.0
    print(
      "[MpvPlayerCore] EDR mode: \(shouldEnableEDR) (hdrEnabled: \(hdrEnabled), sigPeak: \(sigPeak), headroom: \(edrHeadroom))"
    )
  }

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
