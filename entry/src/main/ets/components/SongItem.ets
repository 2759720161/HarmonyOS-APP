import { SongInfo } from '../model/SongInfo'
import { formatMs } from '../common/Constants'
import { PlayerService } from '../service/PlayerService'

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
      Stack() {
        if (this.isCurrentSong) {
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
          .width(36)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        } else {
          Text(`${this.index + 1}`)
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .width(36)
        }
      }
      .width(36)
      .height(36)

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

  private getBarHeight(index: number): string {
    if (index === 0) return '18vp'
    if (index === 1) return '10vp'
    return '24vp'
  }
}
