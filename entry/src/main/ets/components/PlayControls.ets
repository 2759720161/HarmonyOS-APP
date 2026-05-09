import { PlayMode, Colors, getPlayModeIcon } from '../common/Constants'
import { PlayerService } from '../service/PlayerService'

@Component
export struct PlayControls {
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('playMode') playMode: number = PlayMode.SEQUENCE
  @StorageLink('dominantColor') dominantColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @Prop bottomSafe: number = 0
  @Prop immersiveProgress: number = 0
  @Prop primaryColor: string = '#1B2554'
  @Prop secondaryColor: string = '#6A7397'
  @Prop accentColor: string = Colors.DEFAULT_DOMINANT_COLOR
  onMoreClick?: () => void

  private getImmersiveProgress(): number {
    return Math.max(0, Math.min(1, this.immersiveProgress))
  }

  private getSecondaryOpacity(): number {
    return 1 - this.getImmersiveProgress()
  }

  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t
  }

  private getPrimaryControlsMaxWidth(): number {
    return 268
  }

  private getSecondaryControlsMaxWidth(): number {
    return this.lerp(392, 360, this.getImmersiveProgress())
  }

  private getSideButtonSize(): number {
    return this.lerp(84, 68, this.getImmersiveProgress())
  }

  private getCenterButtonSize(): number {
    return 78
  }

  private getSideIconSize(): number {
    return this.lerp(44, 36, this.getImmersiveProgress())
  }

  private getCenterIconSize(): number {
    return 50
  }

  private getAccentColor(): string {
    return this.accentColor.length > 0 ? this.accentColor : this.dominantColor
  }

  @Builder
  private MoreIcon() {
    Column({ space: 5 }) {
      ForEach([0, 1, 2], (item: number) => {
        Circle()
          .width(4)
          .height(4)
          .fill(this.secondaryColor)
      }, (item: number) => item.toString())
    }
    .width(20)
    .height(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PlaylistIcon() {
    Column({ space: 5 }) {
      Row()
        .width(22)
        .height(2)
        .backgroundColor(this.secondaryColor)
        .borderRadius(1)

      Row()
        .width(22)
        .height(2)
        .backgroundColor(this.secondaryColor)
        .borderRadius(1)

      Row()
        .width(14)
        .height(2)
        .backgroundColor(this.secondaryColor)
        .borderRadius(1)
    }
    .width(24)
    .height(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 10 * this.getSecondaryOpacity() }) {
      Row() {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.backward_end_fill'))
            .fontSize(this.getSideIconSize())
            .fontColor([this.primaryColor])
        }
        .width(this.getSideButtonSize())
        .height(this.getSideButtonSize())
        .backgroundColor(Color.Transparent)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
        .onClick(() => {
          PlayerService.getInstance().prev()
        })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(this.getCenterIconSize())
            .fontColor([this.primaryColor])
        }
        .width(this.getCenterButtonSize())
        .height(this.getCenterButtonSize())
        .backgroundColor(Color.Transparent)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
        .onClick(() => {
          PlayerService.getInstance().togglePlayPause()
        })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(this.getSideIconSize())
            .fontColor([this.primaryColor])
        }
        .width(this.getSideButtonSize())
        .height(this.getSideButtonSize())
        .backgroundColor(Color.Transparent)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
        .onClick(() => {
          PlayerService.getInstance().next()
        })
      }
      .width(this.getPrimaryControlsMaxWidth())
      .justifyContent(FlexAlign.SpaceEvenly)
      .alignItems(VerticalAlign.Center)

      Row() {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          this.MoreIcon()
        }
        .width(84)
        .height(40)
        .backgroundColor(Color.Transparent)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
        .onClick(() => {
          if (this.onMoreClick) {
            this.onMoreClick()
          }
        })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph(getPlayModeIcon(this.playMode as PlayMode))
            .fontSize(28)
            .fontColor([this.playMode === PlayMode.SEQUENCE
              ? this.secondaryColor
              : this.getAccentColor()])
        }
        .width(96)
        .height(40)
        .backgroundColor(Color.Transparent)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
        .onClick(() => {
          const next: PlayMode = this.getNextPlayMode()
          PlayerService.getInstance().setPlayMode(next)
        })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          this.PlaylistIcon()
        }
        .width(84)
        .height(40)
        .backgroundColor(Color.Transparent)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      }
      .width(this.getSecondaryControlsMaxWidth())
      .height(40 * this.getSecondaryOpacity())
      .justifyContent(FlexAlign.SpaceEvenly)
      .alignItems(VerticalAlign.Center)
      .opacity(this.getSecondaryOpacity())
      .scale({
        x: 1,
        y: this.getSecondaryOpacity(),
        centerX: '50%',
        centerY: '50%'
      })
      .clip(true)
      .hitTestBehavior(this.getImmersiveProgress() > 0.05 ? HitTestMode.None : HitTestMode.Default)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: 28,
      right: 28,
      top: 12,
      bottom: this.bottomSafe + 4
    })
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
