@CustomDialog
export struct OnlineSearchDialog {
  controller?: CustomDialogController

  @Link visible: boolean
  @Link activeItem: string
  @Link fetchStatus: string
  @Link fetchMessage: string

  onAction?: (itemId: string) => void
  onClose?: () => void

  private getItemBackground(itemId: string): string {
    if (this.activeItem === itemId) {
      return 'rgba(0, 0, 0, 0.06)'
    }
    return 'rgba(0, 0, 0, 0)'
  }

  private getStatusColor(): ResourceColor {
    if (this.fetchStatus === 'success') {
      return '#34C759'
    }
    if (this.fetchStatus === 'error') {
      return '#FF6B6B'
    }
    return $r('sys.color.ohos_id_color_text_secondary')
  }

  @Builder
  private SearchMenuItem(itemId: string, icon: Resource, label: string) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([$r('sys.color.ohos_id_color_text_primary')])
        .width(24)
        .height(24)
        .margin({ left: 20, right: 16 })

      Text(label)
        .layoutWeight(1)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.fetchStatus === 'loading' && this.activeItem === itemId) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ right: 20 })
      }
    }
    .width('100%')
    .height(56)
    .borderRadius(16)
    .backgroundColor(this.getItemBackground(itemId))
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
    .stateStyles({
      pressed: {
        .backgroundColor('rgba(0, 0, 0, 0.05)')
      }
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.activeItem = itemId
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.fetchStatus !== 'loading') {
          this.activeItem = ''
        }
      }
    })
    .onClick(() => {
      if (this.onAction) {
        this.onAction(itemId)
      }
    })
  }

  @Builder
  private CloseItem() {
    Row() {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(20)
        .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
        .width(24)
        .height(24)
        .margin({ left: 20, right: 16 })

      Text('取消')
        .layoutWeight(1)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .height(56)
    .borderRadius(16)
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
    .stateStyles({
      pressed: {
        .backgroundColor('rgba(0, 0, 0, 0.05)')
      }
    })
    .onClick(() => {
      if (this.onClose) {
        this.onClose()
      }
    })
  }

  build() {
    Column() {
      Text('在线查找')
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 10 })
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .textAlign(TextAlign.Start)

      Column({ space: 4 }) {
        this.SearchMenuItem('lyrics', $r('sys.symbol.doc_text'), '查找歌词')
        this.SearchMenuItem('cover', $r('sys.symbol.music'), '查找封面')
        this.SearchMenuItem('settings', $r('sys.symbol.dot_grid_1x2'), '接口设置')

        if (this.fetchMessage.length > 0) {
          Text(this.fetchMessage)
            .width('100%')
            .padding({ left: 20, right: 20, top: 6, bottom: 6 })
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getStatusColor())
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        this.CloseItem()
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 14 })
    }
    .width('90%')
    .constraintSize({ maxWidth: 360, maxHeight: 420 })
    .backgroundColor('rgba(255, 255, 255, 0.75)')
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, { colorMode: ThemeColorMode.SYSTEM })
    .border({
      width: 0.5,
      color: 'rgba(255, 255, 255, 0.38)'
    })
    .borderRadius(32)
    .clip(true)
    .visibility(this.visible ? Visibility.Visible : Visibility.Hidden)
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
    .shadow(ShadowStyle.OUTER_FLOATING_SM)
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
    )
  }
}
