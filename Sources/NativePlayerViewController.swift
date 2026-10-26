import UIKit
import AVFoundation
import AVKit
import MediaPlayer

/// 原生播放器（AVPlayer + HLS 本地代理）。
///
/// 手势：
///   · 按住右半屏      → 2 倍速，松手恢复
///   · 左半屏上下滑    → 亮度
///   · 右半屏上下滑    → 音量
///   · 屏幕左右滑      → 快进 / 后退
///   · 双击左/右区域   → -10s / +10s，双击中间 → 播放暂停
///   · 单击            → 显示/隐藏控制条
/// 控制条：播放暂停、进度拖动、速度、画中画、横竖屏。
final class NativePlayerViewController: UIViewController {

    // MARK: - 输入

    private let embedURL: URL
    private let titleText: String
    private let code: String

    /// 原生播放失败（或取流失败）时回调，交给 embed 播放器兜底
    var onFallback: ((URL, String) -> Void)?

    // MARK: - 播放

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var proxy: HLSLocalProxy?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var pip: AVPictureInPictureController?

    private var duration: Double = 0
    private var currentRate: Float = 1
    private var restoreRate: Float = 1
    private var isBoosting = false
    private var isDraggingSlider = false
    private var fallbackFired = false

    // MARK: - UI

    private let videoView = UIView()
    private let gestureView = UIView()
    private let controls = UIView()
    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let slider = UISlider()
    private let currentLabel = UILabel()
    private let durationLabel = UILabel()
    private let speedButton = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)
    private let rotateButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let boostBadge = UILabel()
    private let hud = PlayerHUD()
    private let statusLabel = UILabel()

    private var volumeView: MPVolumeView?
    private var hideTimer: Timer?
    private var controlsVisible = true
    private var forcedMask: UIInterfaceOrientationMask = .allButUpsideDown

    // MARK: - 初始化

    init(embedURL: URL, title: String, code: String) {
        self.embedURL = embedURL
        self.titleText = title
        self.code = code
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        hideTimer?.invalidate()
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureAudioSession()
        setupViews()
        setupGestures()
        setupSystemVolume()
        startPlayback()
        scheduleHideControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = videoView.bounds
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { forcedMask }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }

    // MARK: - 视图

    private func setupViews() {
        videoView.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)

        gestureView.backgroundColor = .clear
        gestureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gestureView)

        controls.backgroundColor = .clear
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        for anchor in [videoView, gestureView, controls] {
            NSLayoutConstraint.activate([
                anchor.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                anchor.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                anchor.topAnchor.constraint(equalTo: view.topAnchor),
                anchor.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        // 顶部：关闭 / 标题 / 速度
        topBar.layer.cornerRadius = 14
        topBar.clipsToBounds = true
        topBar.translatesAutoresizingMaskIntoConstraints = false
        controls.addSubview(topBar)

        styleIconButton(closeButton, systemName: "xmark")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLabel.text = titleText
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        styleTextButton(speedButton, title: "1.0x")
        speedButton.addTarget(self, action: #selector(showSpeedMenu), for: .touchUpInside)

        let topStack = UIStackView(arrangedSubviews: [closeButton, titleLabel, speedButton])
        topStack.axis = .horizontal
        topStack.spacing = 10
        topStack.alignment = .center
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.contentView.addSubview(topStack)

        // 底部：播放 / 时间 / 进度 / 画中画 / 旋转
        bottomBar.layer.cornerRadius = 14
        bottomBar.clipsToBounds = true
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        controls.addSubview(bottomBar)

        styleIconButton(playButton, systemName: "play.fill")
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)

        currentLabel.text = "00:00"
        currentLabel.textColor = .white
        currentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        durationLabel.text = "--:--"
        durationLabel.textColor = UIColor(white: 1, alpha: 0.7)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 0
        slider.minimumTrackTintColor = UIColor(red: 0.91, green: 0.24, blue: 0.55, alpha: 1)
        slider.maximumTrackTintColor = UIColor(white: 1, alpha: 0.28)
        slider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        styleIconButton(pipButton, systemName: "pip.enter")
        pipButton.addTarget(self, action: #selector(togglePiP), for: .touchUpInside)

        styleIconButton(rotateButton, systemName: "arrow.up.left.and.arrow.down.right")
        rotateButton.addTarget(self, action: #selector(toggleOrientation), for: .touchUpInside)

        let bottomStack = UIStackView(arrangedSubviews: [playButton, currentLabel, slider, durationLabel, pipButton, rotateButton])
        bottomStack.axis = .horizontal
        bottomStack.spacing = 8
        bottomStack.alignment = .center
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.contentView.addSubview(bottomStack)

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        statusLabel.text = ""
        statusLabel.textColor = UIColor(white: 1, alpha: 0.75)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        boostBadge.text = "2x ▶▶"
        boostBadge.textColor = .white
        boostBadge.font = .systemFont(ofSize: 13, weight: .bold)
        boostBadge.backgroundColor = UIColor(red: 0.91, green: 0.24, blue: 0.55, alpha: 0.9)
        boostBadge.textAlignment = .center
        boostBadge.layer.cornerRadius = 11
        boostBadge.clipsToBounds = true
        boostBadge.isHidden = true
        boostBadge.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(boostBadge)

        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topBar.heightAnchor.constraint(equalToConstant: 44),

            topStack.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 8),
            topStack.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -8),
            topStack.centerYAnchor.constraint(equalTo: topBar.contentView.centerYAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            bottomBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            bottomBar.heightAnchor.constraint(equalToConstant: 46),

            bottomStack.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 8),
            bottomStack.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -8),
            bottomStack.centerYAnchor.constraint(equalTo: bottomBar.contentView.centerYAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),

            boostBadge.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            boostBadge.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            boostBadge.widthAnchor.constraint(equalToConstant: 66),
            boostBadge.heightAnchor.constraint(equalToConstant: 22),

            hud.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hud.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        speedButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func styleIconButton(_ button: UIButton, systemName: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    private func styleTextButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        button.widthAnchor.constraint(equalToConstant: 46).isActive = true
    }

    // MARK: - 手势

    private enum PanMode { case undecided, seek, brightness, volume }

    private var panMode: PanMode = .undecided
    private var panStartPoint: CGPoint = .zero
    private var startBrightness: CGFloat = 0
    private var startVolume: Float = 0
    private var seekStartTime: Double = 0
    private var seekTargetTime: Double = 0

    private func setupGestures() {
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.32
        longPress.allowableMovement = 14

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1

        for g in [singleTap, doubleTap, pan, longPress] as [UIGestureRecognizer] {
            gestureView.addGestureRecognizer(g)
        }
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        setControlsVisible(!controlsVisible)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: gestureView).x
        let width = max(gestureView.bounds.width, 1)
        if x < width * 0.35 {
            seek(by: -10)
        } else if x > width * 0.65 {
            seek(by: 10)
        } else {
            togglePlay()
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard gesture.location(in: gestureView).x > gestureView.bounds.width * 0.5 else { return }
            guard let player = player, player.timeControlStatus == .playing else { return }
            isBoosting = true
            restoreRate = currentRate
            player.rate = 2.0
            boostBadge.isHidden = false
        case .ended, .cancelled, .failed:
            guard isBoosting else { return }
            isBoosting = false
            player?.rate = restoreRate
            boostBadge.isHidden = true
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: gestureView)
        let width = max(gestureView.bounds.width, 1)

        switch gesture.state {
        case .began:
            panMode = .undecided
            panStartPoint = point
            startBrightness = UIScreen.main.brightness
            startVolume = currentSystemVolume()
            seekStartTime = player?.currentTime().seconds ?? 0
            seekTargetTime = seekStartTime

        case .changed:
            let dx = point.x - panStartPoint.x
            let dy = point.y - panStartPoint.y
            if panMode == .undecided {
                if abs(dx) > abs(dy) * 1.4 && abs(dx) > 12 {
                    panMode = .seek
                } else if abs(dy) > 12 {
                    panMode = panStartPoint.x < width * 0.5 ? .brightness : .volume
                }
            }

            switch panMode {
            case .seek:
                let delta = Double(dx / width) * 120.0   // 全屏宽度 ≈ 120 秒
                seekTargetTime = min(max(0, seekStartTime + delta), max(duration, 0))
                let sign = delta >= 0 ? "+" : "-"
                hud.show(symbol: delta >= 0 ? "goforward" : "gobackward",
                         text: "\(timeText(seekTargetTime)) / \(timeText(duration))\n\(sign)\(Int(abs(delta)))s")

            case .brightness:
                let value = min(max(0, startBrightness - dy / 220), 1)
                UIScreen.main.brightness = value
                hud.show(symbol: "sun.max.fill", text: "亮度 \(Int(value * 100))%")

            case .volume:
                let value = min(max(0, startVolume - Float(dy / 220)), 1)
                setSystemVolume(value)
                hud.show(symbol: value <= 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                         text: "音量 \(Int(value * 100))%")

            case .undecided:
                break
            }

        case .ended, .cancelled, .failed:
            if panMode == .seek {
                seek(to: seekTargetTime)
            }
            if panMode != .undecided {
                hud.hide()
            }
            panMode = .undecided

        default:
            break
        }
    }

    // MARK: - 播放控制

    private func startPlayback() {
        spinner.startAnimating()
        statusLabel.text = "正在取流…"
        StreamResolver.resolve(embedURL: embedURL) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let streamURL):
                self.statusLabel.text = ""
                self.attach(streamURL: streamURL)
            case .failure(let error):
                self.fallback(reason: error.localizedDescription)
            }
        }
    }

    private func attach(streamURL: URL) {
        guard let proxyURL = HLSLocalProxy.proxyURL(for: streamURL) else {
            fallback(reason: "地址不支持")
            return
        }

        let host = embedURL.host ?? ""
        let proxy = HLSLocalProxy(referer: "https://\(host)/")
        self.proxy = proxy

        let asset = AVURLAsset(url: proxyURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        asset.resourceLoader.setDelegate(proxy, queue: DispatchQueue(label: "avstream.proxy"))

        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 12

        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = videoView.bounds
        layer.backgroundColor = UIColor.black.cgColor
        videoView.layer.addSublayer(layer)
        self.playerLayer = layer

        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    self.spinner.stopAnimating()
                    self.statusLabel.text = ""
                    let d = item.duration.seconds
                    if d.isFinite && d > 0 {
                        self.duration = d
                        self.durationLabel.text = self.timeText(d)
                    }
                    player.play()
                    self.updatePlayButton()
                case .failed:
                    self.fallback(reason: item.error?.localizedDescription ?? "播放失败")
                default:
                    break
                }
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.3, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            let seconds = time.seconds
            if seconds.isFinite {
                if !self.isDraggingSlider {
                    self.currentLabel.text = self.timeText(seconds)
                    if self.duration > 0 {
                        self.slider.value = Float(min(max(seconds / self.duration, 0), 1))
                    }
                }
            }
            self.updatePlayButton()
        }

        setupPiP(with: layer)
    }

    private func fallback(reason: String) {
        guard !fallbackFired else { return }
        fallbackFired = true
        spinner.stopAnimating()
        statusLabel.text = "原生播放失败（\(reason)）\n正在切换播放器…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            self.player?.pause()
            self.onFallback?(self.embedURL, self.titleText)
        }
    }

    private func setupPiP(with layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            pipButton.isHidden = true
            return
        }
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        pip = controller
    }

    @objc private func togglePlay() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            if duration > 0 && player.currentTime().seconds >= duration - 0.6 {
                player.seek(to: .zero)
            }
            player.play()
            if currentRate != 1 {
                player.rate = currentRate
            }
        }
        updatePlayButton()
        setControlsVisible(true)
    }

    private var lastPlayingState: Bool?

    private func updatePlayButton() {
        let playing = player?.timeControlStatus == .playing
        guard lastPlayingState != playing else { return }
        lastPlayingState = playing
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let name = playing ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
    }

    private func seek(to seconds: Double) {
        guard let player = player, duration > 0 else { return }
        let target = min(max(0, seconds), max(0, duration - 0.4))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentLabel.text = timeText(target)
        if duration > 0 {
            slider.value = Float(target / duration)
        }
    }

    private func seek(by delta: Double) {
        let now = player?.currentTime().seconds ?? 0
        seek(to: now + delta)
        hud.show(symbol: delta >= 0 ? "goforward.10" : "gobackward.10",
                 text: "\(delta >= 0 ? "+" : "")\(Int(delta))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.hud.hide()
        }
    }

    // MARK: - 进度条

    @objc private func sliderTouchDown() {
        isDraggingSlider = true
        setControlsVisible(true)
        cancelHideTimer()
    }

    @objc private func sliderChanged() {
        guard duration > 0 else { return }
        let target = Double(slider.value) * duration
        currentLabel.text = timeText(target)
        hud.show(symbol: "arrow.left.and.right", text: "\(timeText(target)) / \(timeText(duration))")
    }

    @objc private func sliderTouchUp() {
        isDraggingSlider = false
        guard duration > 0 else { return }
        seek(to: Double(slider.value) * duration)
        hud.hide()
        scheduleHideControls()
    }

    // MARK: - 速度 / 画中画 / 方向

    @objc private func showSpeedMenu() {
        let sheet = UIAlertController(title: "播放速度", message: nil, preferredStyle: .actionSheet)
        for rate in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] as [Float] {
            let title = String(format: "%.2fx", rate).replacingOccurrences(of: "0x", with: "x")
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.applyRate(rate)
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = speedButton
        sheet.popoverPresentationController?.sourceRect = speedButton.bounds
        present(sheet, animated: true, completion: nil)
    }

    private func applyRate(_ rate: Float) {
        currentRate = rate
        if player?.timeControlStatus == .playing {
            player?.rate = rate
        }
        speedButton.setTitle(abs(rate - 1) < 0.01 ? "1.0x" : String(format: "%.2fx", rate), for: .normal)
        setControlsVisible(true)
    }

    @objc private func togglePiP() {
        guard let pip = pip else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    @objc private func toggleOrientation() {
        let isLandscape: Bool
        if let scene = view.window?.windowScene {
            isLandscape = scene.interfaceOrientation.isLandscape
        } else {
            isLandscape = UIDevice.current.orientation.isLandscape
        }
        let target: UIInterfaceOrientationMask = isLandscape ? .portrait : .landscapeRight
        forcedMask = target

        if #available(iOS 16.0, *), let scene = view.window?.windowScene {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target), errorHandler: { _ in })
        } else {
            let raw = (target == .portrait) ? UIInterfaceOrientation.portrait.rawValue
                                            : UIInterfaceOrientation.landscapeRight.rawValue
            UIDevice.current.setValue(raw, forKey: "orientation")
        }
        setControlsVisible(true)
    }

    @objc private func closeTapped() {
        player?.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        dismiss(animated: true, completion: nil)
    }

    // MARK: - 系统音量

    private func setupSystemVolume() {
        let view = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 40, height: 40))
        view.showsRouteButton = false
        view.alpha = 0.01
        self.view.addSubview(view)
        volumeView = view
    }

    private func systemVolumeSlider() -> UISlider? {
        return volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    private func currentSystemVolume() -> Float {
        return systemVolumeSlider()?.value ?? 0.5
    }

    private func setSystemVolume(_ value: Float) {
        systemVolumeSlider()?.value = value
    }

    // MARK: - 控制条显隐

    private func setControlsVisible(_ visible: Bool) {
        controlsVisible = visible
        UIView.animate(withDuration: 0.2) {
            self.controls.alpha = visible ? 1 : 0
        }
        controls.isUserInteractionEnabled = visible
        if visible {
            scheduleHideControls()
        } else {
            hideTimer?.invalidate()
        }
    }

    private func scheduleHideControls() {
        cancelHideTimer()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.isDraggingSlider else { return }
            self.setControlsVisible(false)
        }
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: - 工具

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 手势冲突：长按优先于拖动

extension NativePlayerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

// MARK: - 画中画

extension NativePlayerViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        setControlsVisible(false)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        setControlsVisible(true)
    }
}

// MARK: - 手势反馈 HUD

final class PlayerHUD: UIView {

    private let iconView = UIImageView()
    private let label = UILabel()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        alpha = 0

        blur.layer.cornerRadius = 14
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -12),

            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(symbol: String, text: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        iconView.image = UIImage(systemName: symbol, withConfiguration: config) ?? UIImage(systemName: "circle")
        label.text = text
        alpha = 1
    }

    func hide() {
        UIView.animate(withDuration: 0.25) { self.alpha = 0 }
    }
}
