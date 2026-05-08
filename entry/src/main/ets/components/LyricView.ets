import { LyricLine } from '../service/LyricParser'

@Component
export struct LyricView {
  @Prop lyricLines: LyricLine[] = []
  @Prop @Watch('onCurrentIndexChange') currentIndex: number = -1
  @Prop dominantColor: string = '#7B7FFF'
  @Prop isDarkMode: boolean = false
  @State private viewportHeight: number = 0
  private scroller: Scroller = new Scroller()
  private itemHeight: number = 108
  private topSpacerHeight: number = 96

  onCurrentIndexChange(): void {
    if (this.currentIndex >= 0 && this.lyricLines.length > 0) {
      this.scrollCurrentLineToCenterAfterThreshold()
    }
  }

  private scrollCurrentLineToCenterAfterThreshold(): void {
    if (this.viewportHeight <= 0) {
      return
    }

    const currentLineCenterY: number = this.topSpacerHeight + this.currentIndex * this.itemHeight + this.itemHeight / 2
    const viewportCenterY: number = this.viewportHeight / 2
    const yOffset: number = Math.max(0, currentLineCenterY - viewportCenterY)
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: yOffset,
      animation: { duration: 320, curve: Curve.EaseOut }
    })
  }

  private getBottomSpacerHeight(): number {
    if (this.viewportHeight <= 0) {
      return this.itemHeight
    }

    return Math.max(this.itemHeight, this.viewportHeight / 2 - this.itemHeight / 2)
  }

  build() {
    if (this.lyricLines.length === 0) {
      Column() {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(48)
          .fontColor([$r('app.color.now_playing_secondary_icon')])
          .opacity(0.5)

        Text('暂无歌词')
          .fontSize(16)
          .fontColor($r('app.color.now_playing_secondary_icon'))
          .opacity(0.7)
          .margin({ top: 16 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      List({ space: 0, initialIndex: 0, scroller: this.scroller }) {
        ListItem()
          .height(this.topSpacerHeight)

        ForEach(this.lyricLines, (line: LyricLine, index: number) => {
          ListItem() {
            this.LyricLineItem(line, index)
          }
          .height(this.itemHeight)
        }, (line: LyricLine, index: number) => `${line.timeMs}_${index}`)

        ListItem()
          .height(this.getBottomSpacerHeight())
      }
      .width('100%')
      .height('100%')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.viewportHeight = Number(newValue.height)
        if (this.currentIndex >= 0 && this.lyricLines.length > 0) {
          this.scrollCurrentLineToCenterAfterThreshold()
        }
      })
      .listDirection(Axis.Vertical)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .alignListItem(ListItemAlign.Center)
    }
  }

  @Builder
  private LyricLineItem(line: LyricLine, index: number) {
    Row() {
      Text(line.text.length > 0 ? line.text : '♪')
        .width('100%')
        .fontSize(index === this.currentIndex ? 28 : 22)
        .lineHeight(index === this.currentIndex ? 40 : 32)
        .fontWeight(index === this.currentIndex ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.getLineTextColor(index))
        .opacity(this.getLineOpacity(index))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding({ left: 36, right: 36 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .scale({
      x: this.getLineScale(index),
      y: this.getLineScale(index),
      centerX: '50%',
      centerY: '50%'
    })
    .translate({ x: 0, y: this.getLineTranslateY(index) })
    .blur(this.getLineBlurRadius(index))
    .animation({
      duration: 320,
      curve: Curve.EaseOut
    })
  }

  private getLineTextColor(index: number): ResourceColor {
    return $r('app.color.now_playing_primary_icon')
  }

  private getLineOpacity(index: number): number {
    if (this.currentIndex < 0) {
      return 0.26
    }
    if (index === this.currentIndex) {
      return 1.0
    }
    const distance = Math.abs(index - this.currentIndex)
    if (distance === 1) {
      return 0.4
    }
    if (distance === 2) {
      return 0.3
    }
    return 0.22
  }

  private getLineBlurRadius(index: number): number {
    if (this.currentIndex < 0) {
      return 10
    }
    if (index === this.currentIndex) {
      return 0
    }

    const distance = Math.abs(index - this.currentIndex)
    if (distance === 1) {
      return 4
    }
    if (distance === 2) {
      return 7
    }
    return 10
  }

  private getLineScale(index: number): number {
    if (this.currentIndex < 0) {
      return 0.94
    }
    if (index === this.currentIndex) {
      return 1
    }
    const distance = Math.abs(index - this.currentIndex)
    if (distance === 1) {
      return 0.95
    }
    if (distance === 2) {
      return 0.92
    }
    return 0.9
  }

  private getLineTranslateY(index: number): number {
    if (this.currentIndex < 0 || index === this.currentIndex) {
      return 0
    }

    const direction: number = index < this.currentIndex ? -1 : 1
    const distance = Math.abs(index - this.currentIndex)
    if (distance === 1) {
      return 6 * direction
    }
    if (distance === 2) {
      return 10 * direction
    }
    return 14 * direction
  }
}
