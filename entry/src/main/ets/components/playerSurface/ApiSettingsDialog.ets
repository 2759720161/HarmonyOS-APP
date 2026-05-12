@CustomDialog
export struct ApiSettingsDialog {
  controller?: CustomDialogController

  @Link lyricApiUrl: string
  @Link lyricApiKey: string
  @Link coverApiUrl: string
  @Link coverApiKey: string
  @StorageLink('screenWidthVp') screenWidthVp: number = 0

  onCancel?: () => void
  onConfirm?: () => void

  private getDialogWidth(): number {
    const width: number = this.screenWidthVp > 0 ? this.screenWidthVp : 360
    return Math.max(280, Math.min(560, width - 40))
  }

  @Builder
  private ApiTextField(label: string, placeholder: string, value: string, fieldId: string) {
    Column({ space: label.length > 0 ? 10 : 0 }) {
      if (label.length > 0) {
        Text(label)
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.now_playing_primary_icon'))
      }

      TextInput({ text: value, placeholder })
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .fontSize(15)
        .fontColor($r('app.color.now_playing_primary_icon'))
        .placeholderColor($r('app.color.now_playing_secondary_icon'))
        .backgroundColor($r('app.color.online_search_api_input_bg'))
        .borderRadius(16)
        .onChange((inputValue: string) => {
          if (fieldId === 'lyrics_api') {
            this.lyricApiUrl = inputValue
            return
          }
          if (fieldId === 'lyrics_key') {
            this.lyricApiKey = inputValue
            return
          }
          if (fieldId === 'cover_api') {
            this.coverApiUrl = inputValue
            return
          }
          this.coverApiKey = inputValue
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ApiFieldSection(title: string, apiValue: string, apiFieldId: string, keyValue: string, keyFieldId: string) {
    Column({ space: 12 }) {
      this.ApiTextField(title, title, apiValue, apiFieldId)
      this.ApiTextField('', '密钥（可为空）', keyValue, keyFieldId)
    }
    .width('100%')
  }

  build() {
    Column({ space: 20 }) {
      Text('API设置')
        .width('100%')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.now_playing_primary_icon'))

      Column({ space: 6 }) {
        Text('设置 API 后可以使用在线查找功能')
          .width('100%')
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.now_playing_primary_icon'))

        Text('注意，此功能需要连接网络，且使用前您需要保证您拥有相关著作人的授权，否则可能导致法律纠纷，本软件对此不负任何责任。')
          .width('100%')
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.online_search_api_warning'))

        Text('目前支持的协议（点击跳转）：')
          .width('100%')
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.now_playing_primary_icon'))

        Text('https://github.com/hisatri/LrcAPI')
          .width('100%')
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.online_search_api_link'))
      }
      .width('100%')

      Column({ space: 22 }) {
        this.ApiFieldSection('歌词', this.lyricApiUrl, 'lyrics_api', this.lyricApiKey, 'lyrics_key')
        this.ApiFieldSection('封面', this.coverApiUrl, 'cover_api', this.coverApiKey, 'cover_key')
      }
      .width('100%')

      Row({ space: 16 }) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text('取消')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.now_playing_primary_icon'))
        }
        .layoutWeight(1)
        .height(52)
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .onClick(() => {
          if (this.onCancel) {
            this.onCancel()
          }
        })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text('确定')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.now_playing_primary_icon'))
        }
        .layoutWeight(1)
        .height(52)
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .onClick(() => {
          if (this.onConfirm) {
            this.onConfirm()
          }
        })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width(this.getDialogWidth())
    .padding({ left: 24, right: 24, top: 26, bottom: 20 })
    .backgroundColor($r('app.color.online_search_api_dialog_surface'))
    .backgroundBlurStyle(BlurStyle.Thick, { colorMode: ThemeColorMode.SYSTEM })
    .borderRadius(30)
    .shadow({
      radius: 36,
      color: 'rgba(108, 120, 153, 0.18)',
      offsetX: 0,
      offsetY: 16
    })
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
    )
  }
}
