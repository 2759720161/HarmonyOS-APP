@CustomDialog
export struct DeleteSongDialog {
  controller?: CustomDialogController

  @Link isDeletingSong: boolean
  @StorageLink('currentTitle') currentTitle: string = ''
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink('isDarkMode') isDarkMode: boolean = false

  onCancel?: () => void
  onDeleteSong?: () => void

  private getCenteredDialogWidth(maxWidth: number): number {
    const width: number = this.screenWidthVp > 0 ? this.screenWidthVp : 360
    return Math.max(280, Math.min(maxWidth, width - 40))
  }

  private getDeleteConfirmMessage(): string {
    const title = this.currentTitle.length > 0 ? this.currentTitle : '当前歌曲'
    return `确定要从歌曲列表中删除「${title}」吗？`
  }

  build() {
    Column() {
      Text('删除歌曲')
        .width('100%')
        .fontSize(22)
        .lineHeight(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))

      Text(this.getDeleteConfirmMessage())
        .width('100%')
        .fontSize(15)
        .lineHeight(22)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 18, bottom: 20 })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text('取消')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_emphasize'))
      }
      .width('100%')
      .height(42)
      .backgroundColor(Color.Transparent)
      .borderRadius(18)
      .enabled(!this.isDeletingSong)
      .onClick(() => {
        if (this.onCancel) {
          this.onCancel()
        }
      })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        if (this.isDeletingSong) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color('#FF3B30')
        } else {
          Text('从列表删除')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF3B30')
        }
      }
      .width('100%')
      .height(42)
      .backgroundColor(Color.Transparent)
      .borderRadius(18)
      .enabled(!this.isDeletingSong)
      .onClick(() => {
        if (this.onDeleteSong) {
          this.onDeleteSong()
        }
      })
    }
    .width(this.getCenteredDialogWidth(360))
    .padding({ left: 24, right: 24, top: 24, bottom: 22 })
    .backgroundColor(this.isDarkMode ? 'rgba(32, 34, 40, 1.0)' : 'rgba(255, 255, 255, 1.0)')
    .borderRadius(28)
    .shadow({
      radius: 40,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.28)' : 'rgba(108, 120, 153, 0.18)',
      offsetX: 0,
      offsetY: 16
    })
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
    )
  }
}
