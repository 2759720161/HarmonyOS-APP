@CustomDialog
export struct MoreMenuDialog {
  controller?: CustomDialogController
  @Link visible: boolean
  onImmersive?: () => void
  onDetail?: () => void
  onOnlineSearch?: () => void
  onDelete?: () => void

  @Builder
  private MenuItem(icon: Resource, label: string, onTap?: () => void, color?: ResourceColor) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([color ? color : $r('sys.color.ohos_id_color_text_primary')])
        .width(24)
        .height(24)
        .margin({ left: 20, right: 16 })

      Text(label)
        .layoutWeight(1)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(color ? color : $r('sys.color.ohos_id_color_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(56)
    .borderRadius(16)
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
    .stateStyles({
      pressed: {
        .backgroundColor('rgba(0, 0, 0, 0.05)')
      },
      normal: {
        .backgroundColor(Color.Transparent)
      }
    })
    .onClick(() => {
      if (onTap) {
        onTap()
      }
    })
  }

  build() {
    Column() {
      Text('更多选项')
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 10 })
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .textAlign(TextAlign.Start)

      Column({ space: 4 }) {
        this.MenuItem($r('sys.symbol.fullscreen'), '沉浸模式', this.onImmersive)
        this.MenuItem($r('sys.symbol.info_circle'), '歌曲详情', this.onDetail)
        this.MenuItem($r('sys.symbol.magnifyingglass'), '在线查找歌词/封面', this.onOnlineSearch)
        this.MenuItem($r('sys.symbol.trash'), '删除歌曲', this.onDelete, $r('sys.color.ohos_id_color_warning'))
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 14 })
    }
    .width('90%')
    .constraintSize({ maxWidth: 360, maxHeight: 360 })
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
