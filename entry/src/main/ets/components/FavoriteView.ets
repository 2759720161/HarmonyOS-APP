import { SongInfo } from '../model/SongInfo'
import { StorageKeys } from '../common/Constants'
import { PlayerService } from '../service/PlayerService'
import { PlaylistManager } from '../service/PlaylistManager'
import { FavoriteManager } from '../service/FavoriteManager'
import { SongItem } from './SongItem'

class FavoriteDataSource implements IDataSource {
  private songs: SongInfo[] = []
  private listeners: DataChangeListener[] = []

  setData(songs: SongInfo[]): void {
    this.songs = songs
    this.notifyDataReload()
  }

  totalCount(): number {
    return this.songs.length
  }

  getData(index: number): SongInfo {
    return this.songs[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener)
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx: number = this.listeners.indexOf(listener)
    if (idx >= 0) {
      this.listeners.splice(idx, 1)
    }
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded())
  }
}

@Component
export struct FavoriteView {
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('currentIndex') currentIndex: number = -1
  @StorageLink('favoriteCount') @Watch('onFavoriteCountChange') favoriteCount: number = 0
  @StorageLink('favoriteIds') favoriteIdsStr: string = '[]'
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0

  private dataSource: FavoriteDataSource = new FavoriteDataSource()

  aboutToAppear(): void {
    this.loadFavorites()
  }

  onFavoriteCountChange(): void {
    this.loadFavorites()
  }

  private loadFavorites(): void {
    void this.doLoadFavorites()
  }

  private async doLoadFavorites(): Promise<void> {
    const list = await FavoriteManager.getInstance().getFavoriteList()
    this.dataSource.setData(list)
  }

  private parseFavoriteIds(): Set<string> {
    try {
      const arr = JSON.parse(this.favoriteIdsStr) as string[]
      return new Set(arr)
    } catch (_) {
      return new Set()
    }
  }

  build() {
    Column() {
      Column({ space: 10 }) {
        Text('收藏')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .width('100%')

        Text(`共 ${this.favoriteCount} 首歌曲`)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
      }
      .width('100%')
      .padding({
        left: 20,
        right: 20,
        top: this.topSafeHeight + 16,
        bottom: 16
      })
      .backgroundColor($r('sys.color.ohos_id_color_background'))
      .zIndex(10)

      if (this.favoriteCount > 0) {
        List({ space: 0 }) {
          LazyForEach(this.dataSource, (song: SongInfo, i: number) => {
            ListItem() {
              SongItem({
                song: song,
                index: i,
                isPlaying: this.isPlaying,
                isCurrentSong: song.id === this.getCurrentSongId(),
                isFavorite: true,
                showFavorite: true,
                globalIndex: PlaylistManager.getInstance().findIndex(song.id),
                onFavoriteToggle: () => {
                  void FavoriteManager.getInstance().toggleFavorite(song).then(() => {
                    this.loadFavorites()
                  })
                }
              })
            }
          }, (song: SongInfo) => song.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          bottom: this.bottomSafeHeight + 230
        })
        .edgeEffect(EdgeEffect.Spring)
        .divider({
          strokeWidth: 0.5,
          color: $r('sys.color.ohos_id_color_list_separator'),
          startMargin: 20,
          endMargin: 20
        })
      } else {
        Column({ space: 20 }) {
          SymbolGlyph($r('sys.symbol.heart'))
            .fontSize(64)
            .fontColor([$r('sys.color.ohos_id_color_text_secondary')])

          Text('暂无收藏歌曲')
            .fontSize(18)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .fontWeight(FontWeight.Medium)

          Text('在歌曲列表中点击爱心按钮收藏')
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 32, right: 32 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  }

  private getCurrentSongId(): string {
    const song = PlayerService.getInstance().getCurrentSong()
    return song ? song.id : ''
  }
}
