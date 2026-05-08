import { Colors, StorageKeys } from '../common/Constants'

@Component
export struct FloatingTab {
  @Prop currentTab: number = 0
  @Prop dominantColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @Prop isDarkMode: boolean = false
  onTabChange?: (tabIndex: number) => void

  private readonly tabs: string[] = ['歌曲', '收藏']

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

  build() {
    Row() {
      ForEach(this.tabs, (tabName: string, index: number) => {
        Column({ space: 2 }) {
          SymbolGlyph(index === 0 ? $r('sys.symbol.music') : $r('sys.symbol.heart'))
            .fontSize(18)
            .fontColor([this.currentTab === index ? $r('sys.color.ohos_id_color_text_primary') :
              $r('sys.color.ohos_id_color_text_secondary')])

          Text(tabName)
            .fontSize(14)
            .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.currentTab === index ? $r('sys.color.ohos_id_color_text_primary') :
              $r('sys.color.ohos_id_color_text_secondary'))
        }
        .width('50%')
        .height(52)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(26)
        .backgroundColor(this.currentTab === index ? this.withAlpha(this.dominantColor, this.isDarkMode ? 0.22 : 0.18) :
          Color.Transparent)
        .onClick(() => {
          const tabChange = this.onTabChange
          if (this.currentTab !== index && tabChange) {
            animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
              tabChange(index)
            })
          }
        })
      }, (tabName: string, index: number) => `${index}`)
    }
    .width('100%')
    .height(66)
    .padding({ left: 7, right: 7, top: 7, bottom: 7 })
    .borderRadius(33)
    .linearGradient({
      angle: 90,
      colors: this.isDarkMode ? [
        [this.withAlpha(this.dominantColor, 0.18), 0.0],
        ['rgba(255,255,255,0.06)', 0.44],
        ['rgba(255,255,255,0.03)', 1.0]
      ] : [
        [this.withAlpha(this.dominantColor, 0.22), 0.0],
        ['rgba(255,255,255,0.72)', 0.44],
        ['rgba(255,255,255,0.48)', 1.0]
      ]
    })
    .backgroundBlurStyle(BlurStyle.Regular, { colorMode: ThemeColorMode.SYSTEM })
    .border({
      width: 0.5,
      color: this.isDarkMode ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)'
    })
    .shadow(ShadowStyle.OUTER_FLOATING_SM)
  }
}
