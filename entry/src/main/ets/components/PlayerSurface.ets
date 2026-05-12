import { image } from '@kit.ImageKit'
import promptAction from '@ohos.promptAction'
import { Colors, PlayMode, formatMs, StorageKeys } from '../common/Constants'
import { GlobalContext, GCKeys } from '../common/GlobalContext'
import { PlayerService } from '../service/PlayerService'
import { PlaylistManager } from '../service/PlaylistManager'
import { FavoriteManager } from '../service/FavoriteManager'
import { AudioScanner } from '../service/AudioScanner'
import { LrcApiConfigService, LrcApiSettings } from '../service/LrcApiConfigService'
import { LrcApiCoverResult, LrcApiService } from '../service/LrcApiService'
import { LyricView } from './LyricView'
import { LyricLine } from '../service/LyricParser'
import { MoreMenuDialog } from './playerSurface/MoreMenuDialog'
import { OnlineSearchDialog } from './playerSurface/OnlineSearchDialog'
import { DetailDialog } from './playerSurface/DetailDialog'
import { DeleteSongDialog } from './playerSurface/DeleteSongDialog'
import { ApiSettingsDialog } from './playerSurface/ApiSettingsDialog'

@Component
struct SurfaceMiniPlayer {
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('currentIndex') currentIndex: number = -1
  @StorageLink('currentTitle') currentTitle: string = ''
  @StorageLink('currentArtist') currentArtist: string = ''
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('coverVersion') @Watch('syncCover') coverVersion: number = 0
  @StorageLink('coverBackdropTopColor') coverBackdropTopColor: string = '#E8F1F2'
  @StorageLink('coverBackdropMiddleColor') coverBackdropMiddleColor: string = '#EDF2F0'
  @StorageLink('coverBackdropBottomColor') coverBackdropBottomColor: string = '#D8E2E3'
  @StorageLink('coverThemeAccentColor') coverThemeAccentColor: string = 'rgba(123, 127, 255, 1)'
  @StorageLink('coverThemeShadowColor') coverThemeShadowColor: string = 'rgba(0, 0, 0, 0.16)'

  @Prop visible: boolean = true
  @Prop opacityValue: number = 1
  @Prop interactive: boolean = true
  @Prop dockBottomOffset: number = 0
  @Prop coverGeometryId: string = ''

  onOpen?: () => void

  @State private coverPixelMap: image.PixelMap | null = null

  aboutToAppear(): void {
    this.syncCover()
  }

  private syncCover(): void {
    const pixelMap = GlobalContext.getInstance().get(GCKeys.CURRENT_COVER)
    this.coverPixelMap = pixelMap ? pixelMap as image.PixelMap : null
  }

  private normalizeAlpha(alpha: number): number {
    return Math.max(0, Math.min(1, alpha))
  }

  private withAlpha(color: string, alpha: number): string {
    const normalizedAlpha = this.normalizeAlpha(alpha)
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

  private getMiniBackgroundStart(): string {
    return this.withAlpha(this.coverBackdropTopColor, 1)
  }

  private getMiniBackgroundMiddle(): string {
    return this.withAlpha(this.coverBackdropMiddleColor, 1)
  }

  private getMiniBackgroundEnd(): string {
    return this.withAlpha(this.coverBackdropBottomColor, 1)
  }

  private getMiniAccentBackground(): string {
    return this.withAlpha(this.coverThemeAccentColor, 0.22)
  }

  private canOpen(): boolean {
    return this.currentIndex >= 0 && this.currentTitle.length > 0
  }

  @Builder
  private CoverThumbBody() {
    if (this.coverPixelMap) {
      Image(this.coverPixelMap)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(22)
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.mini_player_placeholder'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  private CoverThumb() {
    if (this.coverGeometryId.length > 0) {
      Stack() {
        this.CoverThumbBody()
      }
      .width(44)
      .height(44)
      .borderRadius(14)
      .clip(true)
      .geometryTransition(this.coverGeometryId)
      .transition(TransitionEffect.OPACITY)
    } else {
      Stack() {
        this.CoverThumbBody()
      }
      .width(44)
      .height(44)
      .borderRadius(14)
      .clip(true)
    }
  }

  build() {
    Row() {
      Row() {
        this.CoverThumb()

        Column({ space: 2 }) {
          Text(this.currentTitle.length > 0 ? this.currentTitle : 'No song playing')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.currentArtist)
            .fontSize(11)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .opacity(0.72)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .margin({ left: 10, right: 10 })
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(this.visible && this.interactive && this.opacityValue > 0.05 ? HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (this.visible && this.interactive && this.opacityValue > 0.05 && this.canOpen() && this.onOpen) {
          this.onOpen()
        }
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(18)
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
      .width(34)
      .height(34)
      .backgroundColor(this.getMiniAccentBackground())
      .hitTestBehavior(this.visible && this.interactive && this.opacityValue > 0.05 ? HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (this.visible && this.interactive && this.opacityValue > 0.05) {
          PlayerService.getInstance().togglePlayPause()
        }
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(18)
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
      .width(34)
      .height(34)
      .margin({ left: 8 })
      .backgroundColor($r('app.color.mini_player_neutral_button'))
      .hitTestBehavior(this.visible && this.interactive && this.opacityValue > 0.05 ? HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (this.visible && this.interactive && this.opacityValue > 0.05) {
          PlayerService.getInstance().next()
        }
      })
    }
    .height(64)
    .padding({ left: 12, right: 10 })
    .margin({
      left: 18,
      right: 18,
      bottom: this.bottomSafeHeight + 20 + this.dockBottomOffset
    })
    .borderRadius(30)
    .linearGradient({
      angle: 90,
      colors: [
        [this.getMiniBackgroundStart(), 0.0],
        [this.getMiniBackgroundMiddle(), 0.48],
        [this.getMiniBackgroundEnd(), 1.0]
      ]
    })
    .shadow(ShadowStyle.OUTER_FLOATING_SM)
    .opacity(this.visible ? this.opacityValue : 0)
    .hitTestBehavior(this.visible && this.interactive && this.opacityValue > 0.05 ? HitTestMode.Default : HitTestMode.None)
  }
}


@Component
struct PlayerProgressStrip {
  @StorageLink('currentPosition') currentPosition: number = 0
  @StorageLink('totalDuration') totalDuration: number = 0

  @Prop accentColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @Prop trackColor: string = 'rgba(0, 0, 0, 0.16)'
  @Prop interactive: boolean = true
  @Prop timeWidth: number = 46
  @Prop rowHeight: number = 34
  @Prop fontSize: number = 12
  @Prop trackThickness: number = 4
  @Prop blockSizeValue: number = 12

  @State private isSeeking: boolean = false
  @State private seekValue: number = 0

  private getProgressPercent(): number {
    if (this.totalDuration <= 0) {
      return 0
    }
    return Math.max(0, Math.min(100, this.currentPosition / this.totalDuration * 100))
  }

  private getDisplayPosition(): number {
    if (this.isSeeking && this.totalDuration > 0) {
      return (this.seekValue / 100) * this.totalDuration
    }
    return this.currentPosition
  }

  private commitSeek(percent: number): void {
    const targetPercent: number = Math.max(0, Math.min(100, percent))
    this.seekValue = targetPercent
    if (this.totalDuration > 0) {
      void PlayerService.getInstance().seekTo((targetPercent / 100) * this.totalDuration)
    }
    this.isSeeking = false
  }

  build() {
    Row({ space: 8 }) {
      Text(formatMs(this.getDisplayPosition()))
        .width(this.timeWidth)
        .flexShrink(0)
        .fontSize(this.fontSize)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .textAlign(TextAlign.Start)

      Slider({
        value: this.isSeeking ? this.seekValue : this.getProgressPercent(),
        min: 0,
        max: 100,
        step: 0.1,
        style: SliderStyle.OutSet
      })
        .layoutWeight(1)
        .height(this.rowHeight)
        .trackColor(this.trackColor)
        .selectedColor(this.accentColor)
        .blockColor($r('sys.color.ohos_id_color_text_primary'))
        .blockSize({ width: this.blockSizeValue, height: this.blockSizeValue })
        .trackThickness(this.trackThickness)
        .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (!this.interactive) {
            return
          }
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.isSeeking = true
            this.seekValue = value
          } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.commitSeek(value)
          }
        })

      Text(formatMs(this.totalDuration))
        .width(this.timeWidth)
        .flexShrink(0)
        .fontSize(this.fontSize)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(this.rowHeight)
    .alignItems(VerticalAlign.Center)
  }
}


@Component
struct NowPlayingCoverSection {
  @StorageLink('coverVersion') @Watch('syncCover') coverVersion: number = 0

  @Prop sizeValue: number = 0
  @Prop left: number = 0
  @Prop top: number = 0
  @Prop shadowColor: string = 'rgba(0, 0, 0, 0.16)'
  @Prop opacityValue: number = 1

  @State private coverPixelMap: image.PixelMap | null = null

  aboutToAppear(): void {
    this.syncCover()
  }

  private syncCover(): void {
    const pm = GlobalContext.getInstance().get(GCKeys.CURRENT_COVER)
    this.coverPixelMap = pm ? pm as image.PixelMap : null
  }

  build() {
    if (this.coverPixelMap) {
      Image(this.coverPixelMap)
        .width(this.sizeValue)
        .height(this.sizeValue)
        .borderRadius(this.sizeValue * 0.12)
        .objectFit(ImageFit.Cover)
        .shadow({
          radius: 36,
          color: this.shadowColor,
          offsetX: 0,
          offsetY: 0
        })
        .position({ x: this.left, y: this.top })
        .opacity(this.opacityValue)
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(this.sizeValue * 0.22)
          .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
      }
      .width(this.sizeValue)
      .height(this.sizeValue)
      .borderRadius(this.sizeValue * 0.12)
      .backgroundColor('rgba(255, 255, 255, 0.58)')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .shadow({
        radius: 36,
        color: this.shadowColor,
        offsetX: 0,
        offsetY: 0
      })
      .position({ x: this.left, y: this.top })
      .opacity(this.opacityValue)
    }
  }
}


@Component
struct NowPlayingSongInfoSection {
  @StorageLink('currentTitle') currentTitle: string = ''
  @StorageLink('currentArtist') currentArtist: string = ''

  @Prop widthValue: number = 0
  @Prop left: number = 0
  @Prop top: number = 0
  @Prop primaryColor: string = '#202020'
  @Prop secondaryColor: string = '#666666'
  @Prop opacityValue: number = 1

  build() {
    Column({ space: 4 }) {
      Text(this.currentTitle.length > 0 ? this.currentTitle : 'No song playing')
        .width('100%')
        .height(38)
        .fontSize(27)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.currentArtist.length > 0 ? this.currentArtist : 'Unknown artist')
        .width('100%')
        .height(24)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.secondaryColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(this.widthValue)
    .height(66)
    .position({ x: this.left, y: this.top })
    .opacity(this.opacityValue)
  }
}


@Component
struct NowPlayingProgressSection {
  @Prop accentColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @Prop trackColor: string = 'rgba(0, 0, 0, 0.13)'
  @Prop interactive: boolean = true

  build() {
    PlayerProgressStrip({
      accentColor: this.accentColor,
      trackColor: this.trackColor,
      interactive: this.interactive,
      timeWidth: 44,
      rowHeight: 34,
      fontSize: 13,
      trackThickness: 5,
      blockSizeValue: 12
    })
  }
}


@Component
struct PreviousTrackButton {
  @Prop iconColor: string = '#202020'
  @Prop interactive: boolean = true

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.backward_end_fill'))
        .fontSize(36)
        .fontColor([this.iconColor])
    }
    .width(64)
    .height(64)
    .borderRadius(32)
    .backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      PlayerService.getInstance().prev()
    })
  }
}


@Component
struct PlayPauseTrackButton {
  @StorageLink('isPlaying') isPlaying: boolean = false

  @Prop iconColor: string = '#202020'
  @Prop interactive: boolean = true

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(48)
        .fontColor([this.iconColor])
    }
    .width(78)
    .height(78)
    .borderRadius(39)
    .backgroundColor('rgba(255, 255, 255, 0.28)')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      PlayerService.getInstance().togglePlayPause()
    })
  }
}


@Component
struct NextTrackButton {
  @Prop iconColor: string = '#202020'
  @Prop interactive: boolean = true

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(36)
        .fontColor([this.iconColor])
    }
    .width(64)
    .height(64)
    .borderRadius(32)
    .backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      PlayerService.getInstance().next()
    })
  }
}


@Component
struct MoreMenuControlButton {
  @Prop iconColor: string = '#666666'
  @Prop interactive: boolean = true

  onAction?: () => void

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
        .fontSize(28)
        .fontColor([this.iconColor])
    }
    .width(76)
    .height(54)
    .borderRadius(27)
    .backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      if (this.onAction) {
        this.onAction()
      }
    })
  }
}


@Component
struct PlayModeControlButton {
  @StorageLink('playMode') playMode: number = PlayMode.SEQUENCE

  @Prop iconColor: string = '#666666'
  @Prop interactive: boolean = true

  private getNextPlayMode(): PlayMode {
    if (this.playMode === PlayMode.SEQUENCE) {
      return PlayMode.SINGLE
    }
    if (this.playMode === PlayMode.SINGLE) {
      return PlayMode.SHUFFLE
    }
    return PlayMode.SEQUENCE
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.repeat'))
        .fontSize(30)
        .fontColor([this.iconColor])
    }
    .width(76)
    .height(54)
    .borderRadius(27)
    .backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      PlayerService.getInstance().setPlayMode(this.getNextPlayMode())
    })
  }
}


@Component
struct PlaylistControlButton {
  @Prop iconColor: string = '#666666'
  @Prop interactive: boolean = true

  onAction?: () => void

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.music_note_list'))
        .fontSize(30)
        .fontColor([this.iconColor])
    }
    .width(76)
    .height(54)
    .borderRadius(27)
    .backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      if (this.onAction) {
        this.onAction()
      }
    })
  }
}


@Component
struct NowPlayingPanel {
  @Prop screenWidth: number = 0
  @Prop screenHeight: number = 0
  @Prop coverSize: number = 0
  @Prop coverLeft: number = 0
  @Prop coverTop: number = 0
  @Prop titleWidth: number = 0
  @Prop titleLeft: number = 0
  @Prop titleTop: number = 0
  @Prop bottomSafeHeight: number = 0
  @Prop primaryColor: string = '#202020'
  @Prop secondaryColor: string = '#666666'
  @Prop accentColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @Prop trackColor: string = 'rgba(0, 0, 0, 0.13)'
  @Prop shadowColor: string = 'rgba(0, 0, 0, 0.16)'
  @Prop contentOpacity: number = 1
  @Prop controlsInteractive: boolean = true

  onMoreClick?: () => void
  onPlaylistClick?: () => void

  private getHorizontalPadding(): number {
    return this.getScreenWidth() >= 360 ? 24 : 18
  }

  private getBottomPadding(): number {
    return Math.max(0, this.bottomSafeHeight) + 42
  }

  private getScreenWidth(): number {
    return this.screenWidth > 0 ? this.screenWidth : 360
  }

  private getScreenHeight(): number {
    return this.screenHeight > 0 ? this.screenHeight : 800
  }

  private getProgressWidth(): number {
    return Math.max(1, this.getScreenWidth() - this.getHorizontalPadding() * 2)
  }

  private getSecondaryTop(): number {
    return this.getScreenHeight() - this.getBottomPadding() - 54
  }

  private getPrimaryTop(): number {
    return this.getSecondaryTop() - 22 - this.getPrimaryPlaySize()
  }

  private getProgressTop(): number {
    return this.getPrimaryTop() - 28 - 34
  }

  private getPrimarySideSize(): number {
    return 64
  }

  private getPrimaryPlaySize(): number {
    return 78
  }

  private getPrimaryGap(): number {
    return 38
  }

  private getPrimaryPlayLeft(): number {
    return this.getScreenWidth() / 2 - this.getPrimaryPlaySize() / 2
  }

  private getPrimaryPreviousLeft(): number {
    return this.getPrimaryPlayLeft() - this.getPrimaryGap() - this.getPrimarySideSize()
  }

  private getPrimaryNextLeft(): number {
    return this.getPrimaryPlayLeft() + this.getPrimaryPlaySize() + this.getPrimaryGap()
  }

  private getPrimarySideTop(): number {
    return this.getPrimaryTop() + (this.getPrimaryPlaySize() - this.getPrimarySideSize()) / 2
  }

  private getSecondaryStartLeft(): number {
    return (this.getScreenWidth() - 296) / 2
  }

  private getSecondaryModeLeft(): number {
    return this.getSecondaryStartLeft() + 110
  }

  private getSecondaryPlaylistLeft(): number {
    return this.getSecondaryStartLeft() + 220
  }

  build() {
    Stack() {
      NowPlayingSongInfoSection({
        widthValue: this.titleWidth,
        left: this.titleLeft,
        top: this.titleTop,
        primaryColor: this.primaryColor,
        secondaryColor: this.secondaryColor,
        opacityValue: this.contentOpacity
      })

      NowPlayingCoverSection({
        sizeValue: this.coverSize,
        left: this.coverLeft,
        top: this.coverTop,
        shadowColor: this.shadowColor,
        opacityValue: 1
      })

      NowPlayingProgressSection({
        accentColor: this.accentColor,
        trackColor: this.trackColor,
        interactive: this.controlsInteractive
      })
        .width(this.getProgressWidth())
        .height(34)
        .position({ x: this.getHorizontalPadding(), y: this.getProgressTop() })
        .opacity(this.contentOpacity)

      PreviousTrackButton({
        iconColor: this.primaryColor,
        interactive: this.controlsInteractive
      })
        .position({ x: this.getPrimaryPreviousLeft(), y: this.getPrimarySideTop() })
        .opacity(this.contentOpacity)

      PlayPauseTrackButton({
        iconColor: this.primaryColor,
        interactive: this.controlsInteractive
      })
        .position({ x: this.getPrimaryPlayLeft(), y: this.getPrimaryTop() })
        .opacity(this.contentOpacity)

      NextTrackButton({
        iconColor: this.primaryColor,
        interactive: this.controlsInteractive
      })
        .position({ x: this.getPrimaryNextLeft(), y: this.getPrimarySideTop() })
        .opacity(this.contentOpacity)

      MoreMenuControlButton({
        iconColor: this.secondaryColor,
        interactive: this.controlsInteractive,
        onAction: () => {
          if (this.onMoreClick) {
            this.onMoreClick()
          }
        }
      })
        .position({ x: this.getSecondaryStartLeft(), y: this.getSecondaryTop() })
        .opacity(this.contentOpacity)

      PlayModeControlButton({
        iconColor: this.secondaryColor,
        interactive: this.controlsInteractive
      })
        .position({ x: this.getSecondaryModeLeft(), y: this.getSecondaryTop() })
        .opacity(this.contentOpacity)

      PlaylistControlButton({
        iconColor: this.secondaryColor,
        interactive: this.controlsInteractive,
        onAction: () => {
          if (this.onPlaylistClick) {
            this.onPlaylistClick()
          }
        }
      })
        .position({ x: this.getSecondaryPlaylistLeft(), y: this.getSecondaryTop() })
        .opacity(this.contentOpacity)
    }
    .width('100%')
    .height('100%')
  }
}


@Component
struct SurfacePlayerMorphHost {
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('currentTitle') currentTitle: string = ''
  @StorageLink('currentArtist') currentArtist: string = ''
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink('screenHeightVp') screenHeightVp: number = 0
  @StorageLink('coverVersion') @Watch('syncCover') coverVersion: number = 0
  @StorageLink('dominantColor') dominantColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @StorageLink('coverBackdropBaseColor') coverBackdropBaseColor: string = '#F8FAFB'
  @StorageLink('coverBackdropTopColor') coverBackdropTopColor: string = '#E8F1F2'
  @StorageLink('coverBackdropMiddleColor') coverBackdropMiddleColor: string = '#EDF2F0'
  @StorageLink('coverBackdropBottomColor') coverBackdropBottomColor: string = '#D8E2E3'
  @StorageLink('coverBackdropGlowColor') coverBackdropGlowColor: string = 'rgba(220, 238, 240, 1)'
  @StorageLink('coverBackdropAccentGlowColor') coverBackdropAccentGlowColor: string = 'rgba(238, 228, 214, 1)'
  @StorageLink('coverThemeShadowColor') coverThemeShadowColor: string = 'rgba(0, 0, 0, 0.16)'
  @StorageLink('coverThemeAccentColor') coverThemeAccentColor: string = Colors.DEFAULT_DOMINANT_COLOR

  @Prop progress: number = 0
  @Prop visible: boolean = true
  @Prop layerOpacity: number = 1
  @Prop dockBottomOffset: number = 0
  @Prop lyricsProgress: number = 0
  @Prop contentLayerProgress: number = 0
  @Prop coverGeometryId: string = ''

  onClose?: () => void

  @State private coverPixelMap: image.PixelMap | null = null

  private readonly miniLeft: number = 18
  private readonly miniRight: number = 18
  private readonly miniHeight: number = 64
  private readonly miniBottomGap: number = 20
  private readonly miniRadius: number = 30
  private readonly miniCoverSize: number = 44
  private readonly fullCoverMaxSize: number = 360
  private readonly fullCoverSizeRatio: number = 0.72

  aboutToAppear(): void {
    this.syncCover()
  }

  private syncCover(): void {
    const pixelMap = GlobalContext.getInstance().get(GCKeys.CURRENT_COVER)
    this.coverPixelMap = pixelMap ? pixelMap as image.PixelMap : null
  }

  private clamp01(value: number): number {
    return Math.max(0, Math.min(1, value))
  }

  private smooth(value: number): number {
    const t = this.clamp01(value)
    return t * t * (3 - 2 * t)
  }

  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t
  }

  private getT(): number {
    // 空间形变略早于 full 内容层完成，避免 full 封面页出现后共享封面仍在移动。
    return this.smooth(Math.max(0, Math.min(1, this.progress / 0.90)))
  }

  private getScreenW(): number {
    return this.screenWidthVp > 0 ? this.screenWidthVp : 360
  }

  private getScreenH(): number {
    return this.screenHeightVp > 0 ? this.screenHeightVp : 800
  }

  private getCardWidth(): number {
    const miniWidth = this.getScreenW() - this.miniLeft - this.miniRight
    return this.lerp(miniWidth, this.getScreenW(), this.getT())
  }

  private getCardHeight(): number {
    return this.lerp(this.miniHeight, this.getScreenH(), this.getT())
  }

  private getCardX(): number {
    return this.lerp(this.miniLeft, 0, this.getT())
  }

  private getMiniCardY(): number {
    return this.getScreenH() - this.bottomSafeHeight - this.dockBottomOffset - this.miniBottomGap - this.miniHeight
  }

  private getCardY(): number {
    return this.lerp(this.getMiniCardY(), 0, this.getT())
  }

  private getCardRadius(): number {
    return this.lerp(this.miniRadius, 0, this.getT())
  }

  private getCoverSize(): number {
    const fullSize = Math.min(this.getScreenW() * this.fullCoverSizeRatio, this.fullCoverMaxSize)
    return this.lerp(this.miniCoverSize, fullSize, this.getT())
  }

  private getCoverX(): number {
    const miniX = 12
    const fullX = (this.getCardWidth() - this.getCoverSize()) / 2
    return this.lerp(miniX, fullX, this.getT())
  }

  private getCoverY(): number {
    const miniY = 10
    const fullY = this.topSafeHeight + 196
    return this.lerp(miniY, fullY, this.getT())
  }

  private getTitleX(): number {
    return this.lerp(66, 32, this.getT())
  }

  private getTitleY(): number {
    return this.lerp(14, this.topSafeHeight + 76, this.getT())
  }

  private getTitleWidth(): number {
    return this.lerp(this.getCardWidth() - 150, this.getCardWidth() - 64, this.getT())
  }

  private getTitleFontSize(): number {
    return this.lerp(14, 24, this.getT())
  }

  private getArtistFontSize(): number {
    return this.lerp(11, 13, this.getT())
  }

  private getMiniButtonsOpacity(): number {
    return 1 - this.smooth(this.progress / 0.22)
  }

  private getFullControlsOpacity(): number {
    const fadeIn = this.smooth((this.progress - 0.52) / 0.34)
    const fadeOutForContentLayer = 1 - this.smooth((this.progress - 0.90) / 0.08)
    return fadeIn * fadeOutForContentLayer
  }

  private getCloseOpacity(): number {
    return this.smooth((this.progress - 0.70) / 0.18)
  }

  private normalizeAlpha(alpha: number): number {
    return Math.max(0, Math.min(1, alpha))
  }

  private withAlpha(color: string, alpha: number): string {
    const normalizedAlpha = this.normalizeAlpha(alpha)
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

  private getAccentColor(alpha: number): string {
    const accent = this.coverThemeAccentColor.length > 0 ? this.coverThemeAccentColor : this.dominantColor
    return this.withAlpha(accent, alpha)
  }

  private getSharedElementOpacity(): number {
    return 1 - this.smooth(this.contentLayerProgress)
  }

  @Builder
  private CoverBody() {
    if (this.coverPixelMap) {
      Image(this.coverPixelMap)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(this.lerp(20, 108, this.getT()))
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.mini_player_placeholder'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  private CoverFrame() {
    Stack() {
      this.CoverBody()
    }
    .width(this.getCoverSize())
    .height(this.getCoverSize())
    .borderRadius(this.lerp(14, 22, this.getT()))
    .clip(true)
    .position({
      x: this.getCardX() + this.getCoverX(),
      y: this.getCardY() + this.getCoverY()
    })
    .opacity(this.getSharedElementOpacity())
    .shadow({
      radius: 24 * this.getT() * this.getSharedElementOpacity(),
      color: this.coverThemeShadowColor,
      offsetX: 0,
      offsetY: 10
    })
    .renderGroup(true)
  }

  @Builder
  private CoverFrameWithGeometryTransition() {
    Stack() {
      this.CoverBody()
    }
    .width(this.getCoverSize())
    .height(this.getCoverSize())
    .borderRadius(this.lerp(14, 22, this.getT()))
    .clip(true)
    .position({
      x: this.getCardX() + this.getCoverX(),
      y: this.getCardY() + this.getCoverY()
    })
    .opacity(this.getSharedElementOpacity())
    .shadow({
      radius: 24 * this.getT() * this.getSharedElementOpacity(),
      color: this.coverThemeShadowColor,
      offsetX: 0,
      offsetY: 10
    })
    .renderGroup(true)
    .geometryTransition(this.coverGeometryId)
    .transition(TransitionEffect.OPACITY)
  }

  @Builder
  private Cover() {
    if (this.coverGeometryId.length > 0) {
      this.CoverFrameWithGeometryTransition()
    } else {
      this.CoverFrame()
    }
  }

  @Builder
  private TitleBlock() {
    Column({ space: 3 }) {
      Text(this.currentTitle.length > 0 ? this.currentTitle : 'No song playing')
        .fontSize(this.getTitleFontSize())
        .fontWeight(this.getT() > 0.55 ? FontWeight.Bold : FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.progress > 0.5 ? TextAlign.Center : TextAlign.Start)

      Text(this.currentArtist)
        .fontSize(this.getArtistFontSize())
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .opacity(this.lerp(0.70, 0.78, this.getT()))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.progress > 0.5 ? TextAlign.Center : TextAlign.Start)
    }
    .width(this.getTitleWidth())
    .position({
      x: this.getCardX() + this.getTitleX(),
      y: this.getCardY() + this.getTitleY()
    })
    .opacity(this.getSharedElementOpacity())
  }

  @Builder
  private MiniButtons() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(18)
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
      .width(34)
      .height(34)
      .backgroundColor(this.getAccentColor(0.22))
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
      .onClick(() => {
        PlayerService.getInstance().next()
      })
    }
    .position({
      x: this.getCardX() + this.getCardWidth() - 92,
      y: this.getCardY() + 15
    })
    .opacity(this.getMiniButtonsOpacity())
    .hitTestBehavior(this.contentLayerProgress < 0.05 && this.getMiniButtonsOpacity() > 0.05 ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private FullControls() {
    Column({ space: 18 }) {
      PlayerProgressStrip({
        accentColor: this.dominantColor,
        trackColor: 'rgba(0, 0, 0, 0.16)',
        interactive: false,
        timeWidth: 42,
        rowHeight: 34,
        trackThickness: 4,
        blockSizeValue: 10
      })
        .width('86%')

      Row({ space: 34 }) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.backward_end_fill'))
            .fontSize(30)
            .fontColor([$r('sys.color.ohos_id_color_text_primary')])
        }
        .width(54)
        .height(54)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          PlayerService.getInstance().prev()
        })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(42)
            .fontColor([$r('sys.color.ohos_id_color_text_primary')])
        }
        .width(74)
        .height(74)
        .backgroundColor(this.getAccentColor(0.24))
        .onClick(() => {
          PlayerService.getInstance().togglePlayPause()
        })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(30)
            .fontColor([$r('sys.color.ohos_id_color_text_primary')])
        }
        .width(54)
        .height(54)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          PlayerService.getInstance().next()
        })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width(this.getScreenW())
    .position({
      x: 0,
      y: this.getScreenH() - this.bottomSafeHeight - 210
    })
    .opacity(this.getFullControlsOpacity())
    .hitTestBehavior(HitTestMode.None)
  }

  private getCardGlowOpacity(): number {
    return this.smooth((this.progress - 0.22) / 0.70)
  }

  @Builder
  private CardSurface() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.coverBackdropBaseColor)
        .linearGradient({
          angle: 135,
          colors: [
            [this.coverBackdropTopColor, 0.0],
            [this.coverBackdropMiddleColor, 0.55],
            [this.coverBackdropBottomColor, 1.0]
          ]
        })

      Ellipse()
        .width(this.getCardWidth() * 1.12)
        .height(this.getCardWidth() * 0.72)
        .fill(this.coverBackdropGlowColor)
        .opacity(this.getCardGlowOpacity() * 0.16)
        .blur(56)
        .offset({ x: -this.getCardWidth() * 0.22, y: -this.getCardHeight() * 0.10 })
        .hitTestBehavior(HitTestMode.None)

      Ellipse()
        .width(this.getCardWidth() * 0.92)
        .height(this.getCardWidth() * 0.66)
        .fill(this.coverBackdropAccentGlowColor)
        .opacity(this.getCardGlowOpacity() * 0.12)
        .blur(62)
        .offset({ x: this.getCardWidth() * 0.28, y: this.getCardHeight() * 0.18 })
        .hitTestBehavior(HitTestMode.None)
    }
    .width(this.getCardWidth())
    .height(this.getCardHeight())
    .position({ x: this.getCardX(), y: this.getCardY() })
    .borderRadius(this.getCardRadius())
    .clip(true)
    .shadow({
      radius: 28 * (1 - this.getT()),
      color: this.withAlpha(this.coverThemeShadowColor, 0.70),
      offsetX: 0,
      offsetY: 8
    })
    .renderGroup(true)
  }

  build() {
    Stack() {
      this.CardSurface()

      this.Cover()
      this.TitleBlock()
      this.MiniButtons()
      if (this.progress > 0.48) {
        this.FullControls()
      }

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(24)
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
      .width(44)
      .height(44)
      .position({ x: 20, y: this.topSafeHeight + 10 })
      .backgroundColor('rgba(255, 255, 255, 0.18)')
      .opacity(this.getCloseOpacity())
      .hitTestBehavior(this.getCloseOpacity() > 0.05 ? HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (this.onClose) {
          this.onClose()
        }
      })
    }
    .width('100%')
    .height('100%')
    .opacity(this.visible ? this.layerOpacity : 0)
    .hitTestBehavior(this.visible && this.layerOpacity > 0.05 && this.contentLayerProgress <= 0.05 && this.progress < 0.90 ? HitTestMode.Default : HitTestMode.None)
  }
}


@Component
struct SurfaceNowPlayingView {
  @StorageLink('currentIndex') currentIndex: number = -1
  @StorageLink('totalDuration') totalDuration: number = 0
  @StorageLink('currentTitle') currentTitle: string = ''
  @StorageLink('currentArtist') currentArtist: string = ''
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenHeightVp') screenHeightVp: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @StorageLink('dominantColor') dominantColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @StorageLink('lyricLines') lyricLines: LyricLine[] = []
  @StorageLink('lyricIndex') lyricIndex: number = -1
  @StorageLink('modalOverlayActive') modalOverlayActive: boolean = false
  @StorageLink('immersiveModeActive') immersiveModeActive: boolean = false
  @StorageLink('immersiveModeProgress') immersiveModeProgress: number = 0

  @Prop activeContent: boolean = false
  onClose?: () => void
  onSwipeUpdate?: (offsetY: number) => void
  onSwipeEnd?: (velocityY: number) => void
  onLyricsProgress?: (progress: number) => void

  private shouldBuildActiveContent(): boolean {
    return this.activeContent
  }

  private canUsePlaybackControls(): boolean {
    return !this.hasLocalOverlayVisible() && !this.isImmersiveModeShowing()
  }

  private hasLocalOverlayVisible(): boolean {
    return this.isMoreSheetVisible || this.isOnlineSearchPopupVisible || this.isDetailDialogVisible ||
      this.isApiSettingsDialogVisible || this.isDeleteDialogVisible
  }

  @StorageLink('coverBackdropBaseColor') coverBackdropBaseColor: string = '#F8FAFB'
  @StorageLink('coverBackdropTopColor') coverBackdropTopColor: string = '#E8F1F2'
  @StorageLink('coverBackdropMiddleColor') coverBackdropMiddleColor: string = '#EDF2F0'
  @StorageLink('coverBackdropBottomColor') coverBackdropBottomColor: string = '#D8E2E3'
  @StorageLink('coverThemePrimaryColor') coverPagePrimaryColor: string = '#202020'
  @StorageLink('coverThemeSecondaryColor') coverPageSecondaryColor: string = 'rgba(32, 32, 32, 0.68)'
  @StorageLink('coverThemeShadowColor') coverPageShadowColor: string = 'rgba(0, 0, 0, 0.16)'
  @State private isMoreSheetVisible: boolean = false
  @State private isOnlineSearchPopupVisible: boolean = false
  @State private isDetailDialogVisible: boolean = false
  @State private isApiSettingsDialogVisible: boolean = false
  @State private isDeleteDialogVisible: boolean = false
  @State private activeOnlineSearchItem: string = ''
  @State private isDeletingSong: boolean = false
  @State private lyricApiUrl: string = ''
  @State private lyricApiKey: string = ''
  @State private coverApiUrl: string = ''
  @State private coverApiKey: string = ''
  @State private draftLyricApiUrl: string = ''
  @State private draftLyricApiKey: string = ''
  @State private draftCoverApiUrl: string = ''
  @State private draftCoverApiKey: string = ''
  @State private isMoreSheetContentVisible: boolean = true
  @State private isOnlineSearchContentVisible: boolean = true
  @State private fetchStatus: string = 'idle'
  @State private fetchMessage: string = ''
  @State private pendingOnlineSearchItem: string = ''
  @State private coverLyricPageIndex: number = 0
  private coverLyricSwiperController: SwiperController = new SwiperController()
  private readonly lrcApiConfigService: LrcApiConfigService = LrcApiConfigService.getInstance()
  private readonly playlistManager: PlaylistManager = PlaylistManager.getInstance()
  private dialogBackStack: string[] = []
  private readonly dialogParentMore: string = 'more'
  private readonly dialogParentOnlineSearch: string = 'onlineSearch'
  private readonly handleMoreImmersiveAction: () => void = () => {
    this.enterImmersiveMode()
  }
  private readonly handleMoreDetailAction: () => void = () => {
    this.openDetailDialog()
  }
  private readonly handleMoreOnlineSearchAction: () => void = () => {
    this.openOnlineSearchPopup()
  }
  private readonly handleMoreDeleteAction: () => void = () => {
    this.openDeleteDialog()
  }
  private readonly handleMoreDialogCancel: () => void = () => {
    this.dismissMoreSheet()
  }
  private readonly handleOnlineSearchAction: (itemId: string) => void = (itemId: string) => {
    this.handleSubMenuAction(itemId)
  }
  private readonly handleOnlineSearchCloseAction: () => void = () => {
    this.closeOnlineSearchPopup()
  }
  private readonly handleOnlineSearchDialogCancel: () => void = () => {
    this.dismissOnlineSearchPopup()
  }
  private readonly handleDetailCloseAction: () => void = () => {
    this.closeDetailDialog()
  }
  private readonly handleDetailDialogCancel: () => void = () => {
    this.dismissDetailDialog()
  }
  private readonly handleDeleteCancelAction: () => void = () => {
    this.closeDeleteDialog()
  }
  private readonly handleDeleteSongAction: () => void = () => {
    void this.confirmDeleteCurrentSong(false)
  }
  private readonly handleDeleteFileAction: () => void = () => {
    void this.confirmDeleteCurrentSong(true)
  }
  private readonly handleDeleteDialogCancel: () => void = () => {
    this.dismissDeleteDialog()
  }
  private readonly handleApiSettingsCancelAction: () => void = () => {
    this.closeApiSettingsDialog(false)
  }
  private readonly handleApiSettingsConfirmAction: () => void = () => {
    this.closeApiSettingsDialog(true)
  }
  private readonly handleApiSettingsDialogCancel: () => void = () => {
    this.dismissApiSettingsDialog(false)
  }
  private moreMenuDialogController: CustomDialogController = new CustomDialogController({
    builder: MoreMenuDialog({
      visible: $isMoreSheetContentVisible,
      onImmersive: this.handleMoreImmersiveAction,
      onDetail: this.handleMoreDetailAction,
      onOnlineSearch: this.handleMoreOnlineSearchAction,
      onDelete: this.handleMoreDeleteAction
    }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    autoCancel: true,
    maskColor: 'rgba(0, 0, 0, 0.2)',
    cancel: this.handleMoreDialogCancel
  })
  private onlineSearchDialogController: CustomDialogController = new CustomDialogController({
    builder: OnlineSearchDialog({
      visible: $isOnlineSearchContentVisible,
      activeItem: $activeOnlineSearchItem,
      fetchStatus: $fetchStatus,
      fetchMessage: $fetchMessage,
      onAction: this.handleOnlineSearchAction,
      onClose: this.handleOnlineSearchCloseAction
    }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    autoCancel: true,
    maskColor: 'rgba(0, 0, 0, 0)',
    cancel: this.handleOnlineSearchDialogCancel
  })
  private detailDialogController: CustomDialogController = new CustomDialogController({
    builder: DetailDialog({
      onClose: this.handleDetailCloseAction
    }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    autoCancel: true,
    maskColor: 'rgba(0, 0, 0, 0)',
    cancel: this.handleDetailDialogCancel
  })
  private deleteDialogController: CustomDialogController = new CustomDialogController({
    builder: DeleteSongDialog({
      isDeletingSong: $isDeletingSong,
      onCancel: this.handleDeleteCancelAction,
      onDeleteSong: this.handleDeleteSongAction,
      onDeleteFile: this.handleDeleteFileAction
    }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    autoCancel: true,
    maskColor: 'rgba(0, 0, 0, 0)',
    cancel: this.handleDeleteDialogCancel
  })
  private apiSettingsDialogController: CustomDialogController = new CustomDialogController({
    builder: ApiSettingsDialog({
      lyricApiUrl: $draftLyricApiUrl,
      lyricApiKey: $draftLyricApiKey,
      coverApiUrl: $draftCoverApiUrl,
      coverApiKey: $draftCoverApiKey,
      onCancel: this.handleApiSettingsCancelAction,
      onConfirm: this.handleApiSettingsConfirmAction
    }),
    customStyle: true,
    alignment: DialogAlignment.Center,
    autoCancel: true,
    maskColor: 'rgba(0, 0, 0, 0)',
    cancel: this.handleApiSettingsDialogCancel
  })
  private readonly overlayCoverPageMaxSize: number = 520
  private readonly overlayCoverPageMinSize: number = 180
  private readonly overlayCoverPageWidthRatio: number = 0.845
  private readonly overlayImmersiveCoverPageWidthRatio: number = 0.845
  private readonly overlayImmersiveCoverTopShiftRatio: number = 0.12
  private readonly overlayCoverPageHorizontalPadding: number = 48
  private readonly overlayCoverPageTopOffset: number = 174
  private readonly overlayAudioHeight: number = 82
  private readonly overlayProgressHeight: number = 44
  private readonly overlayControlsBaseHeight: number = 176
  private readonly overlayProgressControlsGap: number = 15
  private readonly overlayHeaderTopOffset: number = 8
  private readonly coverPageIndex: number = 0
  private readonly lyricsPageIndex: number = 1
  private readonly immersiveModeAnimationDuration: number = 260
  private immersiveModeHideTask: number = -1
  private apiSettingsLoaded: boolean = false

  aboutToAppear(): void {
    this.setSharedMorphHidden(false)
    this.setModalOverlayActive(false)
    this.setImmersiveModeState(false, 0)
    this.coverLyricPageIndex = this.coverPageIndex
    this.emitLyricsProgress(0)
  }

  aboutToDisappear(): void {
    this.clearImmersiveModeHideTask()
    this.closeDialogControllers()
    this.isMoreSheetVisible = false
    this.isOnlineSearchPopupVisible = false
    this.isDetailDialogVisible = false
    this.isApiSettingsDialogVisible = false
    this.isDeleteDialogVisible = false
    this.isMoreSheetContentVisible = true
    this.isOnlineSearchContentVisible = true
    this.clearDialogParents()
    this.setSharedMorphHidden(false)
    this.setModalOverlayActive(false)
    this.setImmersiveModeState(false, 0)
  }

  private setSharedMorphHidden(hidden: boolean): void {
    AppStorage.setOrCreate(StorageKeys.DETAIL_DIALOG_VISIBLE, hidden)
  }

  private setModalOverlayActive(active: boolean): void {
    AppStorage.setOrCreate(StorageKeys.MODAL_OVERLAY_ACTIVE, active)
  }

  private setImmersiveModeState(active: boolean, progress: number): void {
    AppStorage.setOrCreate(StorageKeys.IMMERSIVE_MODE_ACTIVE, active)
    AppStorage.setOrCreate(StorageKeys.IMMERSIVE_MODE_PROGRESS, Math.max(0, Math.min(1, progress)))
  }

  private restoreModalOverlayWhenIdle(): void {
    if (!this.isMoreSheetVisible && !this.isOnlineSearchPopupVisible && !this.isDetailDialogVisible &&
      !this.isApiSettingsDialogVisible && !this.isDeleteDialogVisible) {
      this.setModalOverlayActive(false)
    }
  }

  private emitLyricsProgress(progress: number): void {
    if (this.onLyricsProgress) {
      this.onLyricsProgress(Math.max(0, Math.min(1, progress)))
    }
  }

  private clearImmersiveModeHideTask(): void {
    if (this.immersiveModeHideTask >= 0) {
      clearTimeout(this.immersiveModeHideTask)
      this.immersiveModeHideTask = -1
    }
  }

  private closeDialogControllers(): void {
    this.moreMenuDialogController.close()
    this.onlineSearchDialogController.close()
    this.detailDialogController.close()
    this.deleteDialogController.close()
    this.apiSettingsDialogController.close()
  }

  private clearDialogParents(): void {
    this.dialogBackStack = []
  }

  private pushDialogParent(parent: string): void {
    if (parent.length > 0) {
      this.dialogBackStack.push(parent)
    }
  }

  private popDialogParent(): string {
    if (this.dialogBackStack.length === 0) {
      return ''
    }

    const parent: string = this.dialogBackStack[this.dialogBackStack.length - 1]
    this.dialogBackStack.splice(this.dialogBackStack.length - 1, 1)
    return parent
  }

  private hideMoreSheetForOnlineSearch(): void {
    if (!this.isMoreSheetVisible || !this.isMoreSheetContentVisible) {
      return
    }

    this.isMoreSheetContentVisible = false
    this.pushDialogParent(this.dialogParentMore)
  }

  private hideMoreSheetForChild(): void {
    if (!this.isMoreSheetVisible || !this.isMoreSheetContentVisible) {
      return
    }

    this.isMoreSheetContentVisible = false
    this.pushDialogParent(this.dialogParentMore)
  }

  private hideOnlineSearchForChild(): boolean {
    if (!this.isOnlineSearchPopupVisible || !this.isOnlineSearchContentVisible) {
      return false
    }

    this.isOnlineSearchContentVisible = false
    this.pushDialogParent(this.dialogParentOnlineSearch)
    return true
  }

  private restorePreviousDialog(): boolean {
    const parent: string = this.popDialogParent()
    if (parent === this.dialogParentOnlineSearch && this.isOnlineSearchPopupVisible) {
      this.isOnlineSearchContentVisible = true
      this.setModalOverlayActive(true)
      return true
    }

    if (parent === this.dialogParentMore && this.isMoreSheetVisible) {
      this.isMoreSheetContentVisible = true
      this.setModalOverlayActive(true)
      return true
    }

    return false
  }

  private dismissMoreSheet(): void {
    this.isMoreSheetVisible = false
    this.isMoreSheetContentVisible = true
    this.clearDialogParents()
    this.restoreModalOverlayWhenIdle()
  }

  private dismissOnlineSearchPopup(): void {
    this.isOnlineSearchPopupVisible = false
    this.isOnlineSearchContentVisible = true
    this.activeOnlineSearchItem = ''
    if (!this.restorePreviousDialog()) {
      this.restoreModalOverlayWhenIdle()
    }
  }

  private dismissDetailDialog(): void {
    this.isDetailDialogVisible = false
    if (!this.restorePreviousDialog()) {
      this.restoreModalOverlayWhenIdle()
    }
  }

  private dismissDeleteDialog(): void {
    this.isDeleteDialogVisible = false
    this.isDeletingSong = false
    if (!this.restorePreviousDialog()) {
      this.restoreModalOverlayWhenIdle()
    }
  }

  private dismissApiSettingsDialog(commit: boolean): void {
    this.isApiSettingsDialogVisible = false
    const restoredParent: boolean = this.restorePreviousDialog()
    if (commit) {
      this.retryPendingOnlineSearch()
    } else {
      this.pendingOnlineSearchItem = ''
    }
    if (!restoredParent) {
      this.restoreModalOverlayWhenIdle()
    }
  }

  private openMoreSheet(): void {
    this.closeDialogControllers()
    this.clearDialogParents()
    this.setModalOverlayActive(true)
    if (!this.apiSettingsLoaded) {
      void this.loadApiSettings()
    }
    this.isOnlineSearchPopupVisible = false
    this.isDetailDialogVisible = false
    this.isApiSettingsDialogVisible = false
    this.isDeleteDialogVisible = false
    this.isMoreSheetContentVisible = true
    this.isOnlineSearchContentVisible = true
    this.isMoreSheetVisible = true
    this.moreMenuDialogController.open()
  }

  private openPlaylistDialog(): void {
    try {
      promptAction.showToast({ message: 'Playlist dialog is not implemented yet', duration: 1200 })
    } catch (_) {
    }
  }

  private closeMoreSheet(): void {
    if (!this.hasLocalOverlayVisible()) {
      return
    }

    this.closeDialogControllers()
    this.isMoreSheetVisible = false
    this.isOnlineSearchPopupVisible = false
    this.isDetailDialogVisible = false
    this.isApiSettingsDialogVisible = false
    this.isDeleteDialogVisible = false
    this.isMoreSheetContentVisible = true
    this.isOnlineSearchContentVisible = true
    this.clearDialogParents()
    this.setSharedMorphHidden(false)
    this.setModalOverlayActive(false)
    this.isDeletingSong = false
    this.activeOnlineSearchItem = ''
  }

  private getImmersiveProgress(): number {
    return Math.max(0, Math.min(1, this.immersiveModeProgress))
  }

  private getImmersiveHiddenOpacity(): number {
    return 1 - this.getImmersiveProgress()
  }

  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t
  }

  private isImmersiveModeShowing(): boolean {
    return this.immersiveModeActive || this.getImmersiveProgress() > 0.01
  }

  private enterImmersiveMode(): void {
    if (this.isImmersiveModeShowing()) {
      this.closeMoreSheet()
      return
    }

    this.clearImmersiveModeHideTask()
    this.coverLyricPageIndex = this.coverPageIndex
    this.emitLyricsProgress(0)
    this.closeMoreSheet()
    this.setImmersiveModeState(true, 0)
    try {
      promptAction.showToast({
        message: '点按歌曲封面即可退出沉浸模式',
        duration: 2200
      })
    } catch (_) {
    }
    animateTo({
      duration: this.immersiveModeAnimationDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.immersiveModeProgress = 1
    })
  }

  private exitImmersiveMode(): void {
    if (!this.isImmersiveModeShowing()) {
      return
    }

    this.clearImmersiveModeHideTask()
    animateTo({
      duration: this.immersiveModeAnimationDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.immersiveModeProgress = 0
    })
    this.immersiveModeHideTask = setTimeout(() => {
      this.setImmersiveModeState(false, 0)
      this.immersiveModeHideTask = -1
    }, this.immersiveModeAnimationDuration) as number
  }

  private openOnlineSearchPopup(): void {
    this.hideMoreSheetForOnlineSearch()
    this.setModalOverlayActive(true)
    this.isOnlineSearchContentVisible = true
    this.isOnlineSearchPopupVisible = true
    this.onlineSearchDialogController.open()
  }

  private closeOnlineSearchPopup(): void {
    if (!this.isOnlineSearchPopupVisible) {
      return
    }

    this.onlineSearchDialogController.close()
    this.dismissOnlineSearchPopup()
  }

  private openDetailDialog(): void {
    this.hideOnlineSearchPopupImmediately()
    this.hideMoreSheetForChild()
    this.setModalOverlayActive(true)
    this.isDetailDialogVisible = true
    this.detailDialogController.open()
  }

  private closeDetailDialog(): void {
    if (!this.isDetailDialogVisible) {
      return
    }

    this.detailDialogController.close()
    this.dismissDetailDialog()
  }

  private openDeleteDialog(): void {
    this.hideOnlineSearchPopupImmediately()
    this.hideMoreSheetForChild()
    this.setModalOverlayActive(true)
    this.isDeleteDialogVisible = true
    this.deleteDialogController.open()
  }

  private closeDeleteDialog(): void {
    if (!this.isDeleteDialogVisible) {
      return
    }

    this.deleteDialogController.close()
    this.dismissDeleteDialog()
  }

  private hideOnlineSearchPopupImmediately(): void {
    this.onlineSearchDialogController.close()
    this.isOnlineSearchPopupVisible = false
    this.isOnlineSearchContentVisible = true
    this.activeOnlineSearchItem = ''
  }

  private async loadApiSettings(): Promise<void> {
    const settings = await this.lrcApiConfigService.loadSettings()
    this.applyApiSettings(settings)
    this.apiSettingsLoaded = true
  }

  private applyApiSettings(settings: LrcApiSettings): void {
    this.lyricApiUrl = settings.lyricsApiUrl
    this.lyricApiKey = settings.lyricsApiKey
    this.coverApiUrl = settings.coverApiUrl
    this.coverApiKey = settings.coverApiKey
  }

  private async openApiSettingsDialog(): Promise<void> {
    if (!this.hideOnlineSearchForChild()) {
      this.hideMoreSheetForChild()
    }
    this.setModalOverlayActive(true)
    if (!this.apiSettingsLoaded) {
      await this.loadApiSettings()
    }
    const currentSettings = new LrcApiSettings(
      this.lyricApiUrl.length > 0 ? this.lyricApiUrl : this.lrcApiConfigService.getDefaultSettings().lyricsApiUrl,
      this.lyricApiKey,
      this.coverApiUrl.length > 0 ? this.coverApiUrl : this.lrcApiConfigService.getDefaultSettings().coverApiUrl,
      this.coverApiKey
    )
    this.draftLyricApiUrl = currentSettings.lyricsApiUrl
    this.draftLyricApiKey = currentSettings.lyricsApiKey
    this.draftCoverApiUrl = currentSettings.coverApiUrl
    this.draftCoverApiKey = currentSettings.coverApiKey
    this.isApiSettingsDialogVisible = true
    this.apiSettingsDialogController.open()
  }

  private closeApiSettingsDialog(commit: boolean): void {
    if (!this.isApiSettingsDialogVisible) {
      return
    }

    if (commit) {
      this.lyricApiUrl = this.draftLyricApiUrl
      this.lyricApiKey = this.draftLyricApiKey
      this.coverApiUrl = this.draftCoverApiUrl
      this.coverApiKey = this.draftCoverApiKey
      void this.persistApiSettings()
    }

    this.apiSettingsDialogController.close()
    this.dismissApiSettingsDialog(commit)
  }

  private async persistApiSettings(): Promise<void> {
    await this.lrcApiConfigService.saveSettings(new LrcApiSettings(
      this.lyricApiUrl,
      this.lyricApiKey,
      this.coverApiUrl,
      this.coverApiKey
    ))
  }

  private retryPendingOnlineSearch(): void {
    if (this.pendingOnlineSearchItem.length === 0) {
      return
    }

    const itemId = this.pendingOnlineSearchItem
    this.pendingOnlineSearchItem = ''
    this.handleSubMenuAction(itemId)
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

  private getCurrentSong() {
    return PlayerService.getInstance().getCurrentSong()
  }

  private getCoverShadowColor(): string {
    return this.coverPageShadowColor
  }

  private getOverlayScreenWidth(): number {
    return this.screenWidthVp > 0 ? this.screenWidthVp : 360
  }

  private getOverlayScreenHeight(): number {
    return this.screenHeightVp > 0 ? this.screenHeightVp : 800
  }

  private getOverlayProgressReserveHeight(): number {
    return this.overlayControlsBaseHeight + this.bottomSafeHeight + this.overlayProgressControlsGap
  }

  private getOverlayCoverTopLimit(): number {
    return this.topSafeHeight + this.overlayCoverPageTopOffset
  }

  private getOverlayCoverSlotBottom(): number {
    return this.getProgressSectionTop() - this.overlayAudioHeight
  }

  private getOverlayCoverSize(): number {
    const screenW = this.getOverlayScreenWidth()
    const widthLimit = Math.min(
      screenW - this.overlayCoverPageHorizontalPadding,
      screenW * this.overlayCoverPageWidthRatio
    )
    const heightLimit = this.getOverlayCoverSlotBottom() - this.getOverlayCoverTopLimit()
    const targetSize = Math.min(this.overlayCoverPageMaxSize, widthLimit, heightLimit)
    const adaptiveMinSize = Math.min(this.overlayCoverPageMinSize, Math.max(120, heightLimit))
    return Math.max(adaptiveMinSize, targetSize)
  }

  private getOverlayCoverTop(): number {
    const topLimit = this.getOverlayCoverTopLimit()
    const coverSize = this.getOverlayCoverSize()
    const availableHeight = this.getOverlayCoverSlotBottom() - topLimit
    if (availableHeight <= coverSize) {
      return topLimit
    }
    return topLimit + (availableHeight - coverSize) / 2
  }

  private getOverlayImmersiveCoverSize(): number {
    const screenW = this.getOverlayScreenWidth()
    return Math.min(
      screenW - this.overlayCoverPageHorizontalPadding,
      screenW * this.overlayImmersiveCoverPageWidthRatio
    )
  }

  private getOverlayCoverTargetSize(): number {
    return this.lerp(this.getOverlayCoverSize(), this.getOverlayImmersiveCoverSize(), this.getImmersiveProgress())
  }

  private getOverlayCoverTargetTop(): number {
    const normalSize = this.getOverlayCoverSize()
    const targetSize = this.getOverlayCoverTargetSize()
    return this.getOverlayCoverTop() - (targetSize - normalSize) * this.overlayImmersiveCoverTopShiftRatio
  }

  private getOverlayCoverTargetLeft(): number {
    return (this.getOverlayScreenWidth() - this.getOverlayCoverTargetSize()) / 2
  }

  private getOverlayTitleTop(): number {
    const topLimit = this.topSafeHeight + this.overlayHeaderTopOffset
    const coverTop = this.getOverlayCoverTop()
    return this.topSafeHeight + ((coverTop - topLimit) - 68) / 2
  }

  private getOverlayTitleWidth(): number {
    return Math.min(this.getOverlayScreenWidth() - 48, this.getOverlayCoverSize() + 28)
  }

  private getOverlayTitleLeft(): number {
    return (this.getOverlayScreenWidth() - this.getOverlayTitleWidth()) / 2
  }

  private getProgressSectionTop(): number {
    return this.getOverlayScreenHeight() - this.getProgressBottomSpacerHeight() - this.overlayProgressHeight
  }

  private getProgressBottomSpacerHeight(): number {
    return this.getOverlayProgressReserveHeight()
  }

  private isLyricsPageVisible(): boolean {
    return this.coverLyricPageIndex === this.lyricsPageIndex
  }

  private canHandlePageSwipe(): boolean {
    return !this.isImmersiveModeShowing() && !this.isMoreSheetVisible && !this.isOnlineSearchPopupVisible &&
      !this.isDetailDialogVisible && !this.isApiSettingsDialogVisible && !this.isDeleteDialogVisible
  }

  private handlePageSwipeUpdate(offsetY: number): void {
    if (!this.canHandlePageSwipe() || offsetY <= 0 || !this.onSwipeUpdate) {
      return
    }
    this.onSwipeUpdate(offsetY)
  }

  private handlePageSwipeEnd(velocityY: number): void {
    if (!this.canHandlePageSwipe() || !this.onSwipeEnd) {
      return
    }
    this.onSwipeEnd(velocityY)
  }

  private handleSubMenuAction(itemId: string): void {
    // 设置按钮：始终打开 API 设置弹窗
    if (itemId === 'settings') {
      this.pendingOnlineSearchItem = ''
      this.activeOnlineSearchItem = ''
      void this.openApiSettingsDialog()
      return
    }

    // 无 API 配置时：任意选项弹出 API 设置弹窗
    if (itemId === 'lyrics' && this.lyricApiUrl.length === 0) {
      this.pendingOnlineSearchItem = itemId
      this.activeOnlineSearchItem = ''
      void this.openApiSettingsDialog()
      return
    }
    if (itemId === 'cover' && this.coverApiUrl.length === 0) {
      this.pendingOnlineSearchItem = itemId
      this.activeOnlineSearchItem = ''
      void this.openApiSettingsDialog()
      return
    }

    // 有 API 配置时：执行在线查找
    if (itemId === 'lyrics') {
      this.executeFetchLyrics()
    } else if (itemId === 'cover') {
      this.executeFetchCover()
    }
  }

  private executeFetchLyrics(): void {
    const song = this.getCurrentSong()
    if (!song) {
      return
    }

    // 缓存检查：歌词已获取过则跳过网络请求
    if (song.lyrics.length > 0) {
      this.fetchStatus = 'success'
      this.fetchMessage = '歌词已缓存'
      this.scheduleFetchReset()
      return
    }

    this.fetchStatus = 'loading'
    this.activeOnlineSearchItem = 'lyrics'
    this.fetchMessage = ''

    const service = LrcApiService.getInstance()
    service.fetchLyrics(
      this.lyricApiUrl, song.title, song.artist, song.album, this.lyricApiKey
    ).then((lrc: string) => {
      if (lrc.length > 0) {
        song.lyrics = lrc
        this.playlistManager.persistPlaylist()
        this.fetchStatus = 'success'
        this.fetchMessage = '歌词获取成功'
      } else if (service.isLastRequestTimedOut()) {
        this.fetchStatus = 'error'
        this.fetchMessage = '歌词接口超时，请稍后重试'
      } else if (service.isLastRequestTransportError()) {
        this.fetchStatus = 'error'
        this.fetchMessage = '歌词接口响应异常'
      } else {
        this.fetchStatus = 'error'
        this.fetchMessage = '未找到歌词'
      }
      this.activeOnlineSearchItem = ''
      this.scheduleFetchReset()
    })
  }

  private executeFetchCover(): void {
    const song = this.getCurrentSong()
    if (!song) {
      return
    }

    // 缓存检查：已有在线封面 URL 则跳过网络请求
    if (song.coverUri.length > 0 && /^https?:\/\//i.test(song.coverUri)) {
      this.fetchStatus = 'success'
      this.fetchMessage = '封面已缓存'
      this.scheduleFetchReset()
      return
    }

    this.fetchStatus = 'loading'
    this.activeOnlineSearchItem = 'cover'
    this.fetchMessage = ''

    const service = LrcApiService.getInstance()
    service.fetchCover(
      this.coverApiUrl, song.title, song.artist, song.album, this.coverApiKey
    ).then((coverResult: LrcApiCoverResult) => {
      if (coverResult.pixelMap) {
        if (coverResult.coverUrl.length > 0) {
          song.coverUri = coverResult.coverUrl
          this.playlistManager.persistPlaylist()
        }
        void AudioScanner.updateCurrentCoverFromPixelMap(coverResult.pixelMap)
        this.fetchStatus = 'success'
        this.fetchMessage = '封面获取成功'
      } else if (service.isLastRequestTimedOut()) {
        this.fetchStatus = 'error'
        this.fetchMessage = '封面接口超时，请稍后重试'
      } else if (service.isLastRequestTransportError()) {
        this.fetchStatus = 'error'
        this.fetchMessage = '封面接口响应异常'
      } else {
        this.fetchStatus = 'error'
        this.fetchMessage = '未找到封面'
      }
      this.activeOnlineSearchItem = ''
      this.scheduleFetchReset()
    })
  }

  private scheduleFetchReset(): void {
    setTimeout(() => {
      this.fetchStatus = 'idle'
      this.fetchMessage = ''
    }, 2000)
  }

  private async confirmDeleteCurrentSong(deleteFile: boolean): Promise<void> {
    if (this.isDeletingSong) {
      return
    }

    this.isDeletingSong = true
    const deleted: boolean = await PlayerService.getInstance().deleteCurrentSong(deleteFile)
    this.isDeletingSong = false

    if (!deleted) {
      this.closeDeleteDialog()
      return
    }

    const hasCurrentSong: boolean = PlayerService.getInstance().getCurrentSong() !== null
    this.closeMoreSheet()
    if (!hasCurrentSong && this.onClose) {
      this.onClose()
    }
  }

  @Builder
  private CoverPageContent() {
    NowPlayingPanel({
      screenWidth: this.getOverlayScreenWidth(),
      screenHeight: this.getOverlayScreenHeight(),
      coverSize: this.getOverlayCoverTargetSize(),
      coverLeft: this.getOverlayCoverTargetLeft(),
      coverTop: this.getOverlayCoverTargetTop(),
      titleWidth: this.getOverlayTitleWidth(),
      titleLeft: this.getOverlayTitleLeft(),
      titleTop: this.getOverlayTitleTop(),
      bottomSafeHeight: this.bottomSafeHeight,
      primaryColor: this.coverPagePrimaryColor,
      secondaryColor: this.coverPageSecondaryColor,
      accentColor: this.dominantColor,
      trackColor: 'rgba(0, 0, 0, 0.13)',
      shadowColor: this.getCoverShadowColor(),
      contentOpacity: this.getImmersiveHiddenOpacity(),
      controlsInteractive: this.canUsePlaybackControls(),
      onMoreClick: () => {
        this.openMoreSheet()
      },
      onPlaylistClick: () => {
        this.openPlaylistDialog()
      }
    })
      .zIndex(20)
  }

  @Builder
  private ImmersiveCoverExitLayer() {
    Row()
      .width(this.getOverlayCoverTargetSize())
      .height(this.getOverlayCoverTargetSize())
      .position({ x: this.getOverlayCoverTargetLeft(), y: this.getOverlayCoverTargetTop() })
      .backgroundColor(this.withAlpha('#000000', 0.001))
      .hitTestBehavior(HitTestMode.Default)
      .onClick(() => {
        this.exitImmersiveMode()
      })
      .zIndex(60)
  }

  @Builder
  private LyricsPageContent() {
    LyricView({
      lyricLines: this.lyricLines,
      currentIndex: this.lyricIndex,
      dominantColor: this.dominantColor,
      isDarkMode: this.isDarkMode
    })
      .width('100%')
      .height('100%')
      .padding({ top: this.topSafeHeight + 4 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }


  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.coverBackdropBaseColor)
        .linearGradient({
          angle: 160,
          colors: [
            [this.coverBackdropTopColor, 0.0],
            [this.coverBackdropMiddleColor, 0.46],
            [this.coverBackdropBottomColor, 1.0]
          ]
        })
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.shouldBuildActiveContent()) {
        if (this.currentIndex < 0 || this.currentTitle.length === 0) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(72)
              .fontColor([this.coverPageSecondaryColor])

            Text('Select a song to start playback')
              .fontSize(16)
              .fontColor(this.coverPageSecondaryColor)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Swiper(this.coverLyricSwiperController) {
            this.CoverPageContent()
            this.LyricsPageContent()
          }
          .index(this.coverLyricPageIndex)
          .indicator(false)
          .loop(false)
          .disableSwipe(this.isImmersiveModeShowing())
          .duration(240)
          .curve(Curve.EaseInOut)
          .width('100%')
          .height('100%')
          .gesture(
            PanGesture({ direction: PanDirection.Vertical, distance: 6 })
              .onActionUpdate((event: GestureEvent) => {
                this.handlePageSwipeUpdate(event.offsetY)
              })
              .onActionEnd((event: GestureEvent) => {
                this.handlePageSwipeEnd(event.velocityY)
              })
          )
          .onContentDidScroll((_selectedIndex: number, index: number, position: number, _mainAxisLength: number) => {
            if (index === this.coverPageIndex) {
              this.emitLyricsProgress(-position)
            }
          })
          .onChange((index: number) => {
            this.coverLyricPageIndex = index
            this.emitLyricsProgress(index === this.lyricsPageIndex ? 1 : 0)
          })
        }
      }

      if (this.isImmersiveModeShowing() && !this.isLyricsPageVisible()) {
        this.ImmersiveCoverExitLayer()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}


@Component
export struct PlayerSurface {
  @Prop progress: number = 0
  @Prop mounted: boolean = false
  @Prop canOpen: boolean = false
  @Prop dockBottomOffset: number = 0
  @Prop miniDockBottomOffset: number = 0
  @Prop lyricsProgress: number = 0
  @Prop contentLayerProgress: number = 0
  @Prop miniLayerOpacity: number = 1
  @Prop morphLayerOpacity: number = 0
  @Prop miniInteractive: boolean = false

  onOpen?: () => void
  onClose?: () => void
  onSwipeUpdate?: (offsetY: number) => void
  onSwipeEnd?: (velocityY: number) => void
  onLyricsProgress?: (progress: number) => void

  private readonly coverGeometryTransitionId: string = 'player_cover_image'

  private getContentOpacity(): number {
    return Math.max(0, Math.min(1, this.contentLayerProgress))
  }

  private isMorphHitTestEnabled(): boolean {
    // 形变层只在 mini -> full 的早期过渡阶段接管点击。
    // 一旦真实 full 内容层开始可交互，morph 视觉层必须彻底退出命中测试，
    // 否则底部按钮会被 morph 里的 Row/Column 接收，SurfaceNowPlayingView 无法收到点击。
    return this.mounted && this.morphLayerOpacity > 0.05 && this.getContentOpacity() <= 0.05 && this.progress < 0.90
  }

  private isMiniHitTestEnabled(): boolean {
    return !this.mounted && this.miniInteractive
  }

  private getContentLayerZIndex(): number {
    return this.getContentOpacity() > 0.05 ? 120 : 20
  }

  private getMorphLayerZIndex(): number {
    return this.isMorphHitTestEnabled() ? 30 : 5
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      SurfacePlayerMorphHost({
        progress: this.progress,
        visible: this.mounted,
        layerOpacity: this.morphLayerOpacity,
        dockBottomOffset: this.dockBottomOffset,
        lyricsProgress: this.lyricsProgress,
        contentLayerProgress: this.contentLayerProgress,
        coverGeometryId: this.mounted ? this.coverGeometryTransitionId : '',
        onClose: () => {
          if (this.onClose) {
            this.onClose()
          }
        }
      })
        .width('100%')
        .height('100%')
        .hitTestBehavior(this.isMorphHitTestEnabled() ? HitTestMode.Default : HitTestMode.None)
        .zIndex(this.getMorphLayerZIndex())

      SurfaceNowPlayingView({
        activeContent: this.mounted,
        onClose: () => {
          if (this.onClose) {
            this.onClose()
          }
        },
        onSwipeUpdate: (offsetY: number) => {
          if (this.onSwipeUpdate) {
            this.onSwipeUpdate(offsetY)
          }
        },
        onSwipeEnd: (velocityY: number) => {
          if (this.onSwipeEnd) {
            this.onSwipeEnd(velocityY)
          }
        },
        onLyricsProgress: (progress: number) => {
          if (this.onLyricsProgress) {
            this.onLyricsProgress(progress)
          }
        }
      })
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .clip(true)
      .opacity(this.getContentOpacity())
      .hitTestBehavior(this.getContentOpacity() > 0.05 ? HitTestMode.Default : HitTestMode.None)
      .zIndex(this.getContentLayerZIndex())

      if (this.miniLayerOpacity > 0.001 || this.miniInteractive) {
        SurfaceMiniPlayer({
          visible: this.canOpen && (this.miniLayerOpacity > 0.001 || !this.mounted),
          opacityValue: this.miniLayerOpacity,
          interactive: this.miniInteractive,
          dockBottomOffset: this.miniDockBottomOffset,
          coverGeometryId: this.mounted ? '' : this.coverGeometryTransitionId,
          onOpen: () => {
            if (this.miniInteractive && this.onOpen) {
              this.onOpen()
            }
          }
        })
        .width('100%')
        .hitTestBehavior(this.isMiniHitTestEnabled() ? HitTestMode.Default : HitTestMode.None)
        .zIndex(this.isMiniHitTestEnabled() ? 140 : 0)
      }

    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.mounted || this.miniInteractive ? HitTestMode.Default : HitTestMode.None)
  }
}
