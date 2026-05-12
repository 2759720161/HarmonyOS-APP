import { fileIo } from '@kit.CoreFileKit'
import { formatMs } from '../../common/Constants'
import { PlayerService } from '../../service/PlayerService'

@CustomDialog
export struct DetailDialog {
  controller?: CustomDialogController

  @StorageLink('currentTitle') currentTitle: string = ''
  @StorageLink('currentArtist') currentArtist: string = ''
  @StorageLink('totalDuration') totalDuration: number = 0
  @StorageLink('screenHeightVp') screenHeightVp: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('isDarkMode') isDarkMode: boolean = false

  onClose?: () => void

  private getCurrentSong() {
    return PlayerService.getInstance().getCurrentSong()
  }

  private getCenteredDialogWidth(maxWidth: number): number {
    const width: number = this.screenWidthVp > 0 ? this.screenWidthVp : 360
    return Math.max(280, Math.min(maxWidth, width - 40))
  }

  private getDetailDialogMaxHeight(): number {
    let screenHeight: number = 800
    if (this.screenHeightVp > 0) {
      screenHeight = this.screenHeightVp
    }
    return Math.max(520, screenHeight - this.topSafeHeight - this.bottomSafeHeight - 88)
  }

  private getDetailContentMaxHeight(): number {
    return Math.max(320, this.getDetailDialogMaxHeight() - 116)
  }

  private getDetailAlbumLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.album.length === 0) {
      return 'Unknown'
    }
    return song.album
  }

  private getDetailSampleRateLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.sampleRate <= 0) {
      return 'Unknown'
    }
    return `${song.sampleRate}Hz`
  }

  private getDetailBitrateLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.bitrate <= 0) {
      return 'Unknown'
    }
    return `${Math.round(song.bitrate / 1000)}kbps`
  }

  private getSongFileName(): string {
    const song = this.getCurrentSong()
    if (!song) {
      return 'Unknown'
    }

    const pathWithoutQuery = song.uri.split('?')[0]
    let fileName = pathWithoutQuery.split('/').pop() || pathWithoutQuery.split('\\').pop() || 'Unknown'
    try {
      fileName = decodeURIComponent(fileName)
    } catch (_) {
    }

    const managedNameMatch = fileName.match(/^[0-9a-f]{6,8}_+(.+)$/i)
    if (managedNameMatch && managedNameMatch[1]) {
      return managedNameMatch[1]
    }
    return fileName
  }

  private getAudioFormatLabel(): string {
    const song = this.getCurrentSong()
    if (!song) {
      return 'AUDIO'
    }

    const codecMimeType = song.codecMimeType.toLowerCase()
    if (codecMimeType.startsWith('audio/')) {
      return codecMimeType.substring('audio/'.length).toUpperCase()
    }

    const mimeType = song.mimeType.toLowerCase()
    if (mimeType.startsWith('audio/')) {
      const formatLabel = mimeType.substring('audio/'.length)
      if (formatLabel === 'mpeg') {
        return 'MPEG'
      }
      return formatLabel.toUpperCase()
    }

    const fileName: string = song.uri.split('?')[0]
    const extension: string = fileName.includes('.')
      ? (fileName.split('.').pop() ?? '')
      : ''

    switch (extension.toLowerCase()) {
      case 'mp3':
        return 'MPEG'
      case 'm4a':
        return 'M4A'
      case 'flac':
        return 'FLAC'
      case 'wav':
        return 'WAV'
      case 'aac':
        return 'AAC'
      case 'ogg':
        return 'OGG'
      default:
        return extension.length > 0 ? extension.toUpperCase() : 'AUDIO'
    }
  }

  private getSongFileSizeLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.uri.length === 0) {
      return 'Unknown'
    }

    try {
      const stat = fileIo.statSync(song.uri)
      return `${(stat.size / 1024 / 1024).toFixed(2)} MB`
    } catch (_) {
      return 'Unknown'
    }
  }

  private getSongAddedDateLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.uri.length === 0) {
      return 'Unknown'
    }

    try {
      const stat = fileIo.statSync(song.uri)
      const timestamp = stat.ctime > 0 ? stat.ctime : stat.mtime
      return this.formatDate(timestamp)
    } catch (_) {
      return 'Unknown'
    }
  }

  private formatDate(timestamp: number): string {
    if (timestamp <= 0) {
      return 'Unknown'
    }

    const normalizedTimestamp = timestamp < 1000000000000 ? timestamp * 1000 : timestamp
    const date = new Date(normalizedTimestamp)
    const month = date.getMonth() + 1
    const day = date.getDate()
    const monthText = month < 10 ? `0${month}` : `${month}`
    const dayText = day < 10 ? `0${day}` : `${day}`
    return `${date.getFullYear()}.${monthText}.${dayText}`
  }

  @Builder
  private DetailRow(label: string, value: string) {
    Row() {
      Text(`${label}：`)
        .width(86)
        .fontSize(14)
        .lineHeight(21)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .flexShrink(0)

      Text(value)
        .layoutWeight(1)
        .fontSize(14)
        .lineHeight(21)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Column({ space: 8 }) {
      Text(this.currentTitle.length > 0 ? this.currentTitle : 'Unknown')
        .width('100%')
        .fontSize(22)
        .lineHeight(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Scroll() {
        Column({ space: 6 }) {
          this.DetailRow('艺术家', this.currentArtist.length > 0 ? this.currentArtist : 'Unknown')
          this.DetailRow('专辑', this.getDetailAlbumLabel())
          this.DetailRow('专辑艺术家', 'Unknown')
          this.DetailRow('作曲家', 'Unknown')
          this.DetailRow('音轨号', '000')
          this.DetailRow('碟号', 'Unknown')
          this.DetailRow('流派', 'Unknown')
          this.DetailRow('格式', this.getAudioFormatLabel())
          this.DetailRow('采样率', this.getDetailSampleRateLabel())
          this.DetailRow('比特率', this.getDetailBitrateLabel())
          this.DetailRow('时长', formatMs(this.totalDuration))
          this.DetailRow('大小', this.getSongFileSizeLabel())
          this.DetailRow('添加时间', this.getSongAddedDateLabel())
          this.DetailRow('文件名', this.getSongFileName())
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: this.getDetailContentMaxHeight() })
      .edgeEffect(EdgeEffect.Spring)

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text('确定')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_emphasize'))
      }
      .width('100%')
      .height(40)
      .backgroundColor(Color.Transparent)
      .borderRadius(18)
      .onClick(() => {
        if (this.onClose) {
          this.onClose()
        }
      })
    }
    .width(this.getCenteredDialogWidth(430))
    .constraintSize({ maxHeight: this.getDetailDialogMaxHeight() })
    .padding({ left: 22, right: 22, top: 22, bottom: 12 })
    .backgroundColor(this.isDarkMode ? 'rgba(32, 34, 40, 1.0)' : 'rgba(255, 255, 255, 1.0)')
    .backgroundBlurStyle(BlurStyle.Thick, { colorMode: ThemeColorMode.SYSTEM })
    .borderRadius(34)
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
