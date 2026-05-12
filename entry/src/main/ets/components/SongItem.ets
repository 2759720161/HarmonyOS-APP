import { image } from '@kit.ImageKit'
import { SongInfo } from '../model/SongInfo'
import { formatMs } from '../common/Constants'
import { PlayerService } from '../service/PlayerService'
import { AudioScanner } from '../service/AudioScanner'

@Component
struct SongCoverThumb {
  @Prop song: SongInfo = new SongInfo('', '', '', '', 0, '')
  @Prop isPlaying: boolean = false
  @Prop isCurrentSong: boolean = false

  @State private coverPixelMap: image.PixelMap | null = null
  private loadToken: number = 0
  private readonly coverSize: number = 44

  aboutToAppear(): void {
    void this.loadCover()
  }

  aboutToDisappear(): void {
    this.loadToken += 1
    this.releaseCover()
  }

  private releaseCover(): void {
    if (this.coverPixelMap) {
      this.coverPixelMap.release()
      this.coverPixelMap = null
    }
  }

  private async loadCover(): Promise<void> {
    const token: number = this.loadToken + 1
    this.loadToken = token
    this.releaseCover()

    if (this.song.coverUri.length > 0 || this.song.uri.length === 0) {
      return
    }

    const pixelMap = await AudioScanner.extractAlbumCover(this.song.uri)
    if (!pixelMap) {
      return
    }

    if (token !== this.loadToken) {
      pixelMap.release()
      return
    }

    this.coverPixelMap = await this.createThumbPixelMap(pixelMap)
  }

  private async createThumbPixelMap(pixelMap: image.PixelMap): Promise<image.PixelMap> {
    try {
      const imageInfo = await pixelMap.getImageInfo()
      const width: number = Math.max(1, imageInfo.size.width)
      const height: number = Math.max(1, imageInfo.size.height)
      const maxSide: number = Math.max(width, height)
      const thumbSize: number = 96
      if (maxSide <= thumbSize) {
        return pixelMap
      }

      const scale: number = thumbSize / maxSide
      const thumbPixelMap = await pixelMap.createScaledPixelMap(scale, scale)
      pixelMap.release()
      return thumbPixelMap
    } catch (_) {
      return pixelMap
    }
  }

  @Builder
  private PlayingBars() {
    Row({ space: 2 }) {
      ForEach([0, 1, 2], (i: number) => {
        Column()
          .width(3)
          .height(this.isPlaying ? this.getBarHeight(i) : '4vp')
          .backgroundColor(Color.White)
          .borderRadius(2)
          .animation(this.isPlaying ? {
            duration: 600,
            curve: Curve.EaseInOut,
            delay: i * 150,
            iterations: -1,
            playMode: PlayMode.Alternate
          } : {
            duration: 300,
            curve: Curve.EaseOut
          })
      })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private CoverContent() {
    if (this.song.coverUri.length > 0) {
      Image(this.song.coverUri)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else if (this.coverPixelMap) {
      Image(this.coverPixelMap)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(21)
          .fontColor([this.isCurrentSong ? '#D9FFFFFF' : $r('sys.color.ohos_id_color_text_secondary')])
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.isCurrentSong ? 'rgba(255, 255, 255, 0.18)' : $r('app.color.mini_player_placeholder'))
    }
  }

  build() {
    Stack() {
      this.CoverContent()

      if (this.isCurrentSong) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.28)')

        this.PlayingBars()
      }
    }
    .width(this.coverSize)
    .height(this.coverSize)
    .borderRadius(10)
    .clip(true)
  }

  private getBarHeight(index: number): string {
    if (index === 0) return '18vp'
    if (index === 1) return '10vp'
    return '24vp'
  }
}

@Component
export struct SongItem {
  @Prop song: SongInfo = new SongInfo('', '', '', '', 0, '')
  @Prop index: number = 0
  @Prop isPlaying: boolean = false
  @Prop isCurrentSong: boolean = false
  @Prop isFavorite: boolean = false
  @Prop showFavorite: boolean = true
  @Prop globalIndex: number = -1
  onFavoriteToggle?: () => void

  @State private favoriteScale: number = 1.0

  build() {
    Row({ space: 12 }) {
      SongCoverThumb({
        song: this.song,
        isPlaying: this.isPlaying,
        isCurrentSong: this.isCurrentSong
      })

      Column({ space: 4 }) {
        Text(this.song.title)
          .fontSize(15)
          .fontColor(this.isCurrentSong ? Color.White : $r('sys.color.ohos_id_color_text_primary'))
          .fontWeight(this.isCurrentSong ? 600 : FontWeight.Regular)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.song.artist)
          .fontSize(12)
          .fontColor(this.isCurrentSong ? '#D9FFFFFF' : $r('sys.color.ohos_id_color_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.showFavorite) {
        SymbolGlyph(this.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(18)
          .fontColor([this.isFavorite ? '#FF3B30' : $r('sys.color.ohos_id_color_text_secondary')])
          .scale({ x: this.favoriteScale, y: this.favoriteScale })
          .onClick(() => {
            animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
              this.favoriteScale = 0.8
            })
            setTimeout(() => {
              animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                this.favoriteScale = 1.1
              })
              setTimeout(() => {
                animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
                  this.favoriteScale = 1.0
                })
              }, 200)
            }, 150)
            if (this.onFavoriteToggle) {
              this.onFavoriteToggle()
            }
          })
      }

      Text(formatMs(this.song.duration))
        .fontSize(12)
        .fontColor(this.isCurrentSong ? '#D9FFFFFF' : $r('sys.color.ohos_id_color_text_secondary'))
        .flexShrink(0)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 14 })
    .backgroundColor(this.isCurrentSong
      ? $r('sys.color.ohos_id_color_component_activated')
      : Color.Transparent)
    .borderRadius(12)
    .onClick(() => {
      const playIndex = this.globalIndex >= 0 ? this.globalIndex : this.index
      PlayerService.getInstance().playAt(playIndex)
    })
  }

}
