import { image } from '@kit.ImageKit'
import { Colors, formatMs } from '../common/Constants'
import { GlobalContext, GCKeys } from '../common/GlobalContext'
import { PlayerService } from '../service/PlayerService'

@Component
export struct PlayerMorphHost {
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('currentTitle') currentTitle: string = ''
  @StorageLink('currentArtist') currentArtist: string = ''
  @StorageLink('currentPosition') currentPosition: number = 0
  @StorageLink('totalDuration') totalDuration: number = 0
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
    return this.smooth(this.progress)
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

  private getProgressPercent(): number {
    if (this.totalDuration <= 0) {
      return 0
    }
    return this.clamp01(this.currentPosition / this.totalDuration) * 100
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
  private Cover() {
    Stack() {
      if (this.coverPixelMap) {
        Image(this.coverPixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
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
    .hitTestBehavior(this.getMiniButtonsOpacity() > 0.05 ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private MorphProgressBar() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(4)
        .backgroundColor('rgba(0, 0, 0, 0.16)')
        .borderRadius(2)

      Row()
        .width(`${this.getProgressPercent()}%`)
        .height(4)
        .backgroundColor(this.dominantColor)
        .borderRadius(2)
    }
    .width('100%')
    .height(8)
  }

  @Builder
  private FullControls() {
    Column({ space: 18 }) {
      Row() {
        Text(formatMs(this.currentPosition))
          .width(42)
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))

        Column() {
          this.MorphProgressBar()
        }
        .layoutWeight(1)

        Text(formatMs(this.totalDuration))
          .width(42)
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .textAlign(TextAlign.End)
      }
      .width('86%')
      .alignItems(VerticalAlign.Center)

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
    .hitTestBehavior(this.getFullControlsOpacity() > 0.05 ? HitTestMode.Default : HitTestMode.None)
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
    .hitTestBehavior(this.visible && this.layerOpacity > 0.05 ? HitTestMode.Default : HitTestMode.None)
  }
}
