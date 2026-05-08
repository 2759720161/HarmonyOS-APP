import { image } from '@kit.ImageKit'
import { Colors, StorageKeys } from '../common/Constants'
import { GlobalContext, GCKeys } from '../common/GlobalContext'
import { PlayerService } from '../service/PlayerService'

@Component
export struct MiniPlayer {
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('currentIndex') currentIndex: number = -1
  @StorageLink('currentTitle') currentTitle: string = ''
  @StorageLink('currentArtist') currentArtist: string = ''
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('screenHeightVp') screenHeightVp: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @StorageLink('coverVersion') @Watch('syncCover') coverVersion: number = 0
  @StorageLink('dominantColor') dominantColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @StorageLink('detailDialogVisible') detailDialogVisible: boolean = false
  @StorageLink('immersiveModeProgress') immersiveModeProgress: number = 0

  @Prop expandProgress: number = 0
  @Prop lyricsProgress: number = 0
  @Prop dockBottomOffset: number = 0
  onOpen?: () => void
  onSwipeUpdate?: (offsetY: number) => void
  onSwipeEnd?: (velocityY: number) => void

  @State private coverPixelMap: image.PixelMap | null = null
  @State private isDragging: boolean = false

  private readonly transparency: number = 0.85
  private readonly pillHeight: number = 64
  // pill 形态
  private readonly pillMaxWidth: number = 560
  private readonly pillSidePadding: number = 18
  private readonly pillBottomGap: number = 20
  private readonly pillRadius: number = 30
  private readonly pillThumbSize: number = 44
  private readonly pillThumbLeft: number = 28 // 10(padding) + 包含圆角补偿
  private readonly pillTitleLeft: number = 80
  private readonly pillTitleTop: number = 24
  private readonly pillTitleFont: number = 15
  private readonly pillControlsWidth: number = 82
  private readonly pillControlsRight: number = 10
  // Full-page cover metrics aligned with NowPlayingView.
  private readonly coverPageMaxSize: number = 520
  private readonly coverPageMinSize: number = 180
  private readonly coverPageWidthRatio: number = 0.845
  private readonly immersiveCoverPageWidthRatio: number = 0.845
  private readonly immersiveCoverTopShiftRatio: number = 0.12
  private readonly coverPageHorizontalPadding: number = 48
  private readonly coverPageTopOffset: number = 174
  private readonly coverAudioHeight: number = 82
  private readonly coverProgressHeight: number = 44
  private readonly coverControlsBaseHeight: number = 176
  private readonly coverProgressControlsGap: number = 15
  private readonly coverHeaderTopOffset: number = 8
  private readonly coverTitleLineHeight: number = 32
  private readonly coverArtistLineHeight: number = 20
  private readonly coverTextGap: number = 4
  private readonly coverTitleFont: number = 24
  private readonly coverArtistFont: number = 13
  // 阶段阈值
  private readonly morphEnd: number = 0.60
  private readonly shellFadeStart: number = 0.80
  private readonly shellFadeEnd: number = 0.95

  aboutToAppear(): void {
    this.syncCover()
  }

  private syncCover(): void {
    const pixelMap = GlobalContext.getInstance().get(GCKeys.CURRENT_COVER)
    this.coverPixelMap = pixelMap ? pixelMap as image.PixelMap : null
  }

  private withAlpha(color: string, alpha: number): string {
    const normalizedAlpha: number = Math.max(0, Math.min(1, alpha))
    const rgbaMatch: RegExpMatchArray | null = color.match(/rgba?\(([^)]+)\)/)
    if (rgbaMatch && rgbaMatch[1]) {
      const channels: string[] = rgbaMatch[1].split(',').map((item: string) => item.trim())
      if (channels.length >= 3) {
        return `rgba(${channels[0]}, ${channels[1]}, ${channels[2]}, ${normalizedAlpha})`
      }
    }

    let hex: string = color.replace('#', '').trim()
    if (hex.length === 3) {
      hex = hex.split('').map((item: string) => `${item}${item}`).join('')
    } else if (hex.length === 8) {
      hex = hex.substring(2)
    }

    if (hex.length === 6) {
      const red: number = Number.parseInt(hex.substring(0, 2), 16)
      const green: number = Number.parseInt(hex.substring(2, 4), 16)
      const blue: number = Number.parseInt(hex.substring(4, 6), 16)
      return `rgba(${red}, ${green}, ${blue}, ${normalizedAlpha})`
    }

    return `rgba(123, 127, 255, ${normalizedAlpha})`
  }

  private canOpen(): boolean {
    return this.currentIndex >= 0 && this.currentTitle.length > 0
  }

  private getTitle(): string {
    if (this.currentTitle.length > 0) {
      return this.currentTitle
    }
    return 'No song playing'
  }

  private getHighlightColor(): string {
    return this.isDarkMode ? this.withAlpha('#FFFFFF', 0.08) : this.withAlpha('#FFFFFF', 0.28)
  }

  private getTailColor(): string {
    return this.isDarkMode ? this.withAlpha('#FFFFFF', 0.02) : this.withAlpha('#FFFFFF', 0.10)
  }

  private getBorderColor(): string {
    return this.isDarkMode ? this.withAlpha('#FFFFFF', 0.14) : this.withAlpha('#000000', 0.10)
  }

  private getSceneMaskColor(): string {
    return this.isDarkMode ? this.withAlpha('#FFFFFF', 0.03) : this.withAlpha('#000000', 0.02)
  }

  private getSceneEdgeColor(): string {
    return this.isDarkMode ? this.withAlpha('#FFFFFF', 0.36) : this.withAlpha('#FFFFFF', 0.24)
  }

  private clamp01(v: number): number {
    return Math.max(0, Math.min(1, v))
  }

  private morphT(): number {
    return this.clamp01(this.expandProgress / this.morphEnd)
  }

  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t
  }

  // ease-out quad for spatial interpolation so elements "land" softly
  private easeOut(t: number): number {
    return 1 - (1 - t) * (1 - t)
  }

  private getCardHeight(): number {
    const t = this.morphT()
    const fullH = this.screenHeightVp > 0 ? this.screenHeightVp : 800
    return this.lerp(this.pillHeight, fullH, t)
  }

  private getCardMaxWidth(): number {
    const t = this.morphT()
    const fullW = (this.screenWidthVp > 0 ? this.screenWidthVp : 800) + 200
    return this.lerp(this.pillMaxWidth, fullW, t)
  }

  private getSidePadding(): number {
    const t = this.morphT()
    return this.lerp(this.pillSidePadding, 0, t)
  }

  private getBottomPadding(): number {
    const t = this.morphT()
    return this.lerp(this.bottomSafeHeight + this.pillBottomGap + this.dockBottomOffset, 0, t)
  }

  private getCardRadius(): number {
    const t = this.morphT()
    return this.lerp(this.pillRadius, 0, t)
  }

  // pill 内的右侧按钮（播放/下一首）在形变开始就快速淡出
  private getPillButtonsOpacity(): number {
    const p = this.expandProgress
    if (p <= 0) {
      return 1
    }
    if (p >= 0.15) {
      return 0
    }
    return 1 - p / 0.15
  }

  // pill 自身背景：在 shellFadeStart 之后淡出，让 NowPlayingView 的纯背景接管
  private getShellOpacity(): number {
    const p = this.expandProgress
    if (p <= this.shellFadeStart) {
      return 1
    }
    if (p >= this.shellFadeEnd) {
      return 0
    }
    return 1 - (p - this.shellFadeStart) / (this.shellFadeEnd - this.shellFadeStart)
  }

  private isHitTestActive(): boolean {
    return this.expandProgress < 0.05
  }

  // ---------- 形变元素：封面 ----------
  private getCoverSize(): number {
    const t = this.easeOut(this.morphT())
    return this.lerp(this.pillThumbSize, this.getCoverTargetSize(), t)
  }

  private getFullScreenHeight(): number {
    return this.screenHeightVp > 0 ? this.screenHeightVp : 800
  }

  private getFullScreenWidth(): number {
    return this.screenWidthVp > 0 ? this.screenWidthVp : 360
  }

  private getCoverProgressReserveHeight(): number {
    return this.coverControlsBaseHeight + this.bottomSafeHeight + this.coverProgressControlsGap
  }

  private getCoverTopLimit(): number {
    return this.topSafeHeight + this.coverPageTopOffset
  }

  private getCoverSlotBottom(): number {
    return this.getFullScreenHeight() - this.getCoverProgressReserveHeight() -
      this.coverAudioHeight - this.coverProgressHeight
  }

  private getCoverPageSize(): number {
    const screenW = this.getFullScreenWidth()
    const widthLimit = Math.min(screenW - this.coverPageHorizontalPadding, screenW * this.coverPageWidthRatio)
    const heightLimit = this.getCoverSlotBottom() - this.getCoverTopLimit()
    const targetSize = Math.min(this.coverPageMaxSize, widthLimit, heightLimit)
    const adaptiveMinSize = Math.min(this.coverPageMinSize, Math.max(120, heightLimit))
    return Math.max(adaptiveMinSize, targetSize)
  }

  private getCoverPageTop(): number {
    const topLimit = this.getCoverTopLimit()
    const coverSize = this.getCoverPageSize()
    const availableHeight = this.getCoverSlotBottom() - topLimit
    if (availableHeight <= coverSize) {
      return topLimit
    }
    return topLimit + (availableHeight - coverSize) / 2
  }

  private getImmersiveCoverPageSize(): number {
    const screenW = this.getFullScreenWidth()
    return Math.min(screenW - this.coverPageHorizontalPadding, screenW * this.immersiveCoverPageWidthRatio)
  }

  private getCoverTargetSize(): number {
    return this.lerp(this.getCoverPageSize(), this.getImmersiveCoverPageSize(), this.getImmersiveProgress())
  }

  private getCoverTargetTop(): number {
    const normalSize = this.getCoverPageSize()
    const targetSize = this.getCoverTargetSize()
    return this.getCoverPageTop() - (targetSize - normalSize) * this.immersiveCoverTopShiftRatio
  }

  private getCoverTextTop(): number {
    const topLimit = this.topSafeHeight + this.coverHeaderTopOffset
    const coverTop = this.getCoverPageTop()
    return this.topSafeHeight + ((coverTop - topLimit) - 68) / 2
  }

  private getCoverArtistOffset(): number {
    return this.coverTitleLineHeight + this.coverTextGap
  }

  // 卡片内部横向坐标（相对卡片左上角）
  private getCoverLeft(): number {
    const t = this.easeOut(this.morphT())
    const cardW = this.getEffectiveCardWidth()
    const targetLeft = (cardW - this.getCoverTargetSize()) / 2
    return this.lerp(this.pillThumbLeft, targetLeft, t)
  }

  private getCoverTop(): number {
    const t = this.easeOut(this.morphT())
    // pill 形态时相对卡片（卡片此刻等于 pill），封面缩略图在 (76-52)/2 = 12
    // 全屏态时封面距卡片顶部 top safe + coverPageTopOffset
    const target = this.getCoverTargetTop()
    const pillTop = (this.pillHeight - this.pillThumbSize) / 2
    return this.lerp(pillTop, target, t)
  }

  private getCoverRadius(): number {
    const t = this.morphT()
    return this.lerp(20, 18, t)
  }

  // ---------- 形变元素：标题 ----------
  private getTitleLeft(): number {
    const t = this.easeOut(this.morphT())
    const cardW = this.getEffectiveCardWidth()
    const targetLeft = (cardW - this.getCoverTextWidth()) / 2
    return this.lerp(this.pillTitleLeft, targetLeft, t)
  }

  private getTitleTop(): number {
    const t = this.easeOut(this.morphT())
    const target = this.getCoverTextTop()
    return this.lerp(this.pillTitleTop, target, t)
  }

  private getTitleFontSize(): number {
    const t = this.morphT()
    return this.lerp(this.pillTitleFont, this.coverTitleFont, t)
  }

  private getTitleWidth(): number {
    const t = this.easeOut(this.morphT())
    const cardW = this.getEffectiveCardWidth()
    const pillW = cardW - this.pillTitleLeft - this.pillControlsWidth - this.pillControlsRight - 12
    const coverW = this.getCoverTextWidth()
    return this.lerp(Math.max(80, pillW), coverW, t)
  }

  private getCoverTextWidth(): number {
    const cardW = this.getEffectiveCardWidth()
    return Math.min(cardW - 48, this.getCoverTargetSize() + 28)
  }

  private getEffectiveCardWidth(): number {
    const t = this.morphT()
    const screenW = this.screenWidthVp > 0 ? this.screenWidthVp : 800
    const pillW = Math.min(this.pillMaxWidth, Math.max(0, screenW - this.pillSidePadding * 2))
    return this.lerp(pillW, screenW, t)
  }

  private getPillControlsLeft(): number {
    return this.getEffectiveCardWidth() - this.pillControlsWidth - this.pillControlsRight
  }

  private getOpenHitWidth(): number {
    return Math.max(0, this.getPillControlsLeft() - 6)
  }

  // 仅在接近全屏（expandProgress 0.80→0.95）时让歌词页进度生效，
  // 这样关闭动画期间形变封面/标题会重新淡入并继续 morph 回 mini 形态。
  private getLyricsEffectGate(): number {
    const p = this.expandProgress
    if (p <= 0.80) {
      return 0
    }
    if (p >= 0.95) {
      return 1
    }
    return (p - 0.80) / 0.15
  }

  private getEffectiveLyricsProgress(): number {
    return this.clamp01(this.lyricsProgress) * this.getLyricsEffectGate()
  }

  private getMorphLayerTranslateX(): number {
    const screenW = this.screenWidthVp > 0 ? this.screenWidthVp : 800
    return -this.getEffectiveLyricsProgress() * screenW
  }

  private getMorphLayerOpacity(): number {
    if (this.detailDialogVisible) {
      return 0
    }
    return 1 - this.getEffectiveLyricsProgress()
  }

  private getImmersiveProgress(): number {
    return Math.max(0, Math.min(1, this.immersiveModeProgress))
  }

  private getTextMorphOpacity(): number {
    return this.getMorphLayerOpacity() * (1 - this.getImmersiveProgress())
  }

  private getCoverImmersiveScale(): number {
    return 1
  }

  @Builder
  private CoverMorph() {
    Stack() {
      if (this.coverPixelMap) {
        Image(this.coverPixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(this.lerp(20, 120, this.morphT()))
            .fontColor([$r('sys.color.ohos_id_color_text_primary')])
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.mini_player_placeholder'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width(this.getCoverSize())
    .height(this.getCoverSize())
    .borderRadius(this.getCoverRadius())
    .clip(true)
    .position({ x: this.getCoverLeft() + this.getMorphLayerTranslateX(), y: this.getCoverTop() })
    .scale({
      x: this.getCoverImmersiveScale(),
      y: this.getCoverImmersiveScale(),
      centerX: '50%',
      centerY: '50%'
    })
    .opacity(this.getMorphLayerOpacity())
    .shadow({
      radius: 24 * this.morphT(),
      color: this.isDarkMode ? this.withAlpha('#000000', 0.32) : this.withAlpha(this.dominantColor, 0.22),
      offsetX: 0,
      offsetY: 12 * this.morphT()
    })
  }

  @Builder
  private TitleMorph() {
    if (this.expandProgress < 0.05) {
      Marquee({
        start: this.currentTitle.length > 12,
        step: 6,
        loop: -1,
        fromStart: true,
        src: this.getTitle()
      })
        .width(this.getTitleWidth())
        .height(22)
        .fontSize(this.pillTitleFont)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .position({ x: this.getTitleLeft() + this.getMorphLayerTranslateX(), y: this.getTitleTop() - 2 })
        .opacity(this.getTextMorphOpacity())
    } else {
      Text(this.getTitle())
        .width(this.getTitleWidth())
        .height(this.coverTitleLineHeight)
        .fontSize(this.getTitleFontSize())
        .lineHeight(this.coverTitleLineHeight)
        .fontWeight(this.morphT() > 0.5 ? FontWeight.Bold : FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.morphT() > 0.5 ? TextAlign.Center : TextAlign.Start)
        .position({ x: this.getTitleLeft() + this.getMorphLayerTranslateX(), y: this.getTitleTop() })
        .opacity(this.getTextMorphOpacity())
    }
  }

  @Builder
  private ArtistMorph() {
    Text(this.currentArtist)
      .height(this.coverArtistLineHeight)
      .fontSize(this.coverArtistFont)
      .lineHeight(this.coverArtistLineHeight)
      .fontWeight(FontWeight.Medium)
      .fontColor('#111111')
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(this.morphT() > 0.5 ? TextAlign.Center : TextAlign.Start)
      .width(this.getTitleWidth())
      .position({ x: this.getTitleLeft() + this.getMorphLayerTranslateX(), y: this.getArtistTop() })
      .opacity(this.getArtistOpacity() * this.getTextMorphOpacity())
  }

  private getArtistTop(): number {
    const t = this.easeOut(this.morphT())
    const target = this.getCoverTextTop() + this.getCoverArtistOffset()
    return this.lerp(this.pillTitleTop, target, t)
  }

  private getArtistOpacity(): number {
    if (this.expandProgress < 0.60) {
      return 0
    }
    return Math.min(1, (this.expandProgress - 0.60) / 0.25)
  }

  @Builder
  private PillButtons() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(18)
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
      .width(34)
      .height(34)
      .backgroundColor(this.withAlpha(this.dominantColor, 0.22))
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => {
        PlayerService.getInstance().togglePlayPause()
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(18)
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
      .width(34)
      .height(34)
      .backgroundColor($r('app.color.mini_player_neutral_button'))
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => {
        PlayerService.getInstance().next()
      })
    }
    .width(this.pillControlsWidth)
    .position({ x: this.getPillControlsLeft(), y: 15 })
    .opacity(this.getPillButtonsOpacity())
    .hitTestBehavior(this.expandProgress > 0.05 ? HitTestMode.None : HitTestMode.Default)
  }

  @Builder
  private MorphCard() {
    Stack() {
      // —— 卡片外壳：pill 背景 → 形变时淡出让 NowPlayingView 背景接管 ——
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [
              [this.withAlpha(this.dominantColor, 0.12), 0.0],
              [this.getHighlightColor(), 0.42],
              [this.getTailColor(), 1.0]
            ]
          })
          .backgroundColor($r('app.color.mini_player_surface'))
          .backgroundBlurStyle(BlurStyle.Regular, { colorMode: ThemeColorMode.SYSTEM })
          .opacity(this.transparency)

      }
      .width('100%')
      .height('100%')
      .border({ width: this.expandProgress < 0.5 ? 1 : 0, color: this.getBorderColor() })
      .borderRadius(this.getCardRadius())
      .shadow(ShadowStyle.OUTER_FLOATING_SM)
      .clip(true)
      .opacity(this.getShellOpacity())

      // —— 形变元素：封面 + 标题 + 歌手 连续在卡片坐标内移动+放大 ——
      this.CoverMorph()
      this.TitleMorph()
      this.ArtistMorph()

      if (this.expandProgress < 0.05) {
        Column()
          .width(this.getOpenHitWidth())
          .height(this.pillHeight)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.onOpen) {
              this.onOpen()
            }
          })
      }

      // —— 仅 pill 状态下显示的右侧两颗按钮 ——
      if (this.expandProgress < 0.15) {
        this.PillButtons()
      }

    }
    .width('100%')
    .height(this.getCardHeight())
    .constraintSize({ maxWidth: this.getCardMaxWidth() })
    .alignContent(Alignment.TopStart)
  }

  build() {
    Column() {
      this.MorphCard()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: this.getSidePadding(),
      right: this.getSidePadding(),
      bottom: this.getBottomPadding()
    })
    .hitTestBehavior(this.isHitTestActive() ? HitTestMode.Default : HitTestMode.Transparent)
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 6 })
        .onActionStart(() => {
          if (!this.canOpen() || this.expandProgress > 0.05) {
            return
          }
          this.isDragging = true
        })
        .onActionUpdate((event: GestureEvent) => {
          if (!this.canOpen() || !this.isDragging || !this.onSwipeUpdate) {
            return
          }
          this.onSwipeUpdate(event.offsetY)
        })
        .onActionEnd((event: GestureEvent) => {
          if (!this.isDragging) {
            return
          }
          this.isDragging = false
          if (this.onSwipeEnd) {
            this.onSwipeEnd(event.velocityY)
          }
        })
    )
  }
}
