import { Colors, PlayMode, getPlayModeIcon } from '../common/Constants'
import { PlayerService } from '../service/PlayerService'

@Component
export struct CoverPageControls {
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('playMode') playMode: number = PlayMode.SEQUENCE
  @StorageLink('dominantColor') dominantColor: string = Colors.DEFAULT_DOMINANT_COLOR

  @Prop bottomSafe: number = 0
  @Prop immersiveProgress: number = 0
  @Prop primaryColor: string = '#1B2554'
  @Prop secondaryColor: string = '#6A7397'
  @Prop accentColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @Prop controlsEnabled: boolean = true

  onMoreClick?: () => void
  onPlaylistClick?: () => void

  private clamp01(value: number): number {
    return Math.max(0, Math.min(1, value))
  }

  private getImmersiveProgress(): number {
    return this.clamp01(this.immersiveProgress)
  }

  private getSecondaryOpacity(): number {
    return 1 - this.getImmersiveProgress()
  }

  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t
  }

  private getPrimarySideSize(): number {
    return this.lerp(82, 66, this.getImmersiveProgress())
  }

  private getPrimaryCenterSize(): number {
    return this.lerp(82, 70, this.getImmersiveProgress())
  }

  private getPrimarySideIconSize(): number {
    return this.lerp(42, 34, this.getImmersiveProgress())
  }

  private getPrimaryCenterIconSize(): number {
    return this.lerp(50, 42, this.getImmersiveProgress())
  }

  private getSecondaryButtonWidth(): number {
    return 92
  }

  private getSecondaryButtonHeight(): number {
    return 56
  }

  private getBottomPadding(): number {
    return Math.max(0, this.bottomSafe)
  }

  private getTotalHeight(): number {
    return this.getPrimarySideSize() + 12 + this.getSecondaryButtonHeight() * this.getSecondaryOpacity() + this.getBottomPadding()
  }

  private getAccentColor(): string {
    return this.accentColor.length > 0 ? this.accentColor : this.dominantColor
  }

  private isPrimaryInteractive(): boolean {
    return this.controlsEnabled
  }

  private isSecondaryInteractive(): boolean {
    return this.controlsEnabled && this.getSecondaryOpacity() > 0.05
  }

  @Builder
  private PrevButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.backward_end_fill'))
        .fontSize(this.getPrimarySideIconSize())
        .fontColor([this.primaryColor])
    }
    .width(this.getPrimarySideSize())
    .height(this.getPrimarySideSize())
    .backgroundColor(Color.Transparent)
    .borderRadius(this.getPrimarySideSize() / 2)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.isPrimaryInteractive() ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      PlayerService.getInstance().prev()
    })
  }

  @Builder
  private PlayButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(this.getPrimaryCenterIconSize())
        .fontColor([this.primaryColor])
    }
    .width(this.getPrimaryCenterSize())
    .height(this.getPrimaryCenterSize())
    .backgroundColor(Color.Transparent)
    .borderRadius(this.getPrimaryCenterSize() / 2)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.isPrimaryInteractive() ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      PlayerService.getInstance().togglePlayPause()
    })
  }

  @Builder
  private NextButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(this.getPrimarySideIconSize())
        .fontColor([this.primaryColor])
    }
    .width(this.getPrimarySideSize())
    .height(this.getPrimarySideSize())
    .backgroundColor(Color.Transparent)
    .borderRadius(this.getPrimarySideSize() / 2)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.isPrimaryInteractive() ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      PlayerService.getInstance().next()
    })
  }

  @Builder
  private MoreButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Text('•••')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.secondaryColor)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width(this.getSecondaryButtonWidth())
    .height(this.getSecondaryButtonHeight())
    .backgroundColor(Color.Transparent)
    .borderRadius(this.getSecondaryButtonHeight() / 2)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.isSecondaryInteractive() ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      if (this.onMoreClick) {
        this.onMoreClick()
      }
    })
  }

  @Builder
  private ModeButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph(getPlayModeIcon(this.playMode as PlayMode))
        .fontSize(30)
        .fontColor([this.playMode === PlayMode.SEQUENCE ? this.secondaryColor : this.getAccentColor()])
    }
    .width(this.getSecondaryButtonWidth())
    .height(this.getSecondaryButtonHeight())
    .backgroundColor(Color.Transparent)
    .borderRadius(this.getSecondaryButtonHeight() / 2)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.isSecondaryInteractive() ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      const next: PlayMode = this.getNextPlayMode()
      PlayerService.getInstance().setPlayMode(next)
    })
  }

  @Builder
  private PlaylistButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Text('☰')
        .fontSize(30)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.secondaryColor)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width(this.getSecondaryButtonWidth())
    .height(this.getSecondaryButtonHeight())
    .backgroundColor(Color.Transparent)
    .borderRadius(this.getSecondaryButtonHeight() / 2)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .hitTestBehavior(this.isSecondaryInteractive() ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => {
      if (this.onPlaylistClick) {
        this.onPlaylistClick()
      }
    })
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 26 }) {
        this.PrevButton()
        this.PlayButton()
        this.NextButton()
      }
      .width('100%')
      .height(this.getPrimarySideSize())
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(this.isPrimaryInteractive() ? HitTestMode.Default : HitTestMode.None)

      Row({ space: 22 }) {
        this.MoreButton()
        this.ModeButton()
        this.PlaylistButton()
      }
      .width('100%')
      .height(this.getSecondaryButtonHeight())
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .opacity(this.getSecondaryOpacity())
      .hitTestBehavior(this.isSecondaryInteractive() ? HitTestMode.Default : HitTestMode.None)

      Blank()
        .height(this.getBottomPadding())
    }
    .width('100%')
    .height(this.getTotalHeight())
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .hitTestBehavior(this.controlsEnabled ? HitTestMode.Default : HitTestMode.None)
  }

  private getNextPlayMode(): PlayMode {
    if (this.playMode === PlayMode.SEQUENCE) {
      return PlayMode.SINGLE
    }
    if (this.playMode === PlayMode.SINGLE) {
      return PlayMode.SHUFFLE
    }
    return PlayMode.SEQUENCE
  }
}
