@Component
export struct SearchBar {
  @State private keyword: string = ''
  onSearch?: (keyword: string) => void
  onClose?: () => void

  build() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => {
        this.keyword = ''
        if (this.onSearch) {
          this.onSearch('')
        }
        if (this.onClose) {
          this.onClose()
        }
      })

      Search({ value: this.keyword, placeholder: '搜索歌曲或歌手' })
        .width('100%')
        .height(36)
        .textFont({ size: 15 })
        .placeholderFont({ size: 15 })
        .placeholderColor($r('sys.color.ohos_id_color_text_hint'))
        .caretStyle({ width: 2 })
        .onChange((value: string) => {
          this.keyword = value
          if (this.onSearch) {
            this.onSearch(value)
          }
        })
        .onSubmit((value: string) => {
          if (this.onSearch) {
            this.onSearch(value)
          }
        })

      if (this.keyword.length > 0) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
        }
        .width(28)
        .height(28)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.keyword = ''
          if (this.onSearch) {
            this.onSearch('')
          }
        })
      }
    }
    .width('100%')
    .padding({ right: 16 })
  }
}
