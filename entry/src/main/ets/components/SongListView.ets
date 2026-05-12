import { SongInfo } from '../model/SongInfo'
import { StorageKeys } from '../common/Constants'
import { PlayerService } from '../service/PlayerService'
import { PlaylistManager } from '../service/PlaylistManager'
import { FavoriteManager } from '../service/FavoriteManager'
import { SongItem } from './SongItem'
import { SearchBar } from './SearchBar'

class SongDataSource implements IDataSource {
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
export struct SongListView {
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('currentIndex') currentIndex: number = -1
  @StorageLink('songCount') @Watch('onSongCountChange') songCount: number = 0
  @StorageLink('scanStatus') scanStatus: string = 'idle'
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('favoriteIds') favoriteIdsStr: string = '[]'

  @State private isSearchActive: boolean = false
  @State private searchKeyword: string = ''
  @State private searchResultIndices: number[] = []

  onSelectMusic?: () => void

  private dataSource: SongDataSource = new SongDataSource()
  private allSongs: SongInfo[] = []

  aboutToAppear(): void {
    AppStorage.setOrCreate(StorageKeys.MINI_PLAYER_SCROLL_OFFSET, 0)
    this.loadPlaylist()
  }

  onSongCountChange(): void {
    if (this.songCount > 0) {
      this.loadPlaylist()
    }
  }

  private loadPlaylist(): void {
    this.allSongs = PlaylistManager.getInstance().getPlaylist()
    if (this.allSongs.length > 0) {
      this.dataSource.setData(this.allSongs)
    }
  }

  private parseFavoriteIds(): Set<string> {
    try {
      const arr = JSON.parse(this.favoriteIdsStr) as string[]
      return new Set(arr)
    } catch (_) {
      return new Set()
    }
  }

  private handleSearch(keyword: string): void {
    this.searchKeyword = keyword
    if (keyword.trim().length === 0) {
      this.searchResultIndices = []
      this.dataSource.setData(this.allSongs)
      return
    }

    const results = PlaylistManager.getInstance().searchSongs(keyword)
    const indices: number[] = []
    for (const song of results) {
      const globalIdx = this.allSongs.findIndex((s: SongInfo) => s.id === song.id)
      if (globalIdx >= 0) {
        indices.push(globalIdx)
      }
    }
    this.searchResultIndices = indices
    this.dataSource.setData(results)
  }

  private openSearch(): void {
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.isSearchActive = true
    })
  }

  private closeSearch(): void {
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.isSearchActive = false
    })
    this.searchKeyword = ''
    this.searchResultIndices = []
    this.dataSource.setData(this.allSongs)
  }

  private updateMiniPlayerScrollOffset(scrollOffset: number): void {
    const currentOffset: number = AppStorage.get<number>(StorageKeys.MINI_PLAYER_SCROLL_OFFSET) ?? 0
    const nextOffset: number = Math.max(0, currentOffset + scrollOffset)
    AppStorage.setOrCreate(StorageKeys.MINI_PLAYER_SCROLL_OFFSET, nextOffset)
  }

  build() {
    Column() {
      Column() {
        if (this.isSearchActive) {
          Row() {
            SearchBar({
              onSearch: (keyword: string) => {
                this.handleSearch(keyword)
              },
              onClose: () => {
                this.closeSearch()
              }
            })
          }
          .width('100%')
          .padding({ top: this.topSafeHeight + 16, bottom: 12, left: 4 })
        } else {
          Row() {
            Text('本地音乐')
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))

            Blank()

            if (this.songCount > 0) {
              Button({ type: ButtonType.Normal }) {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(18)
                  .fontColor([$r('sys.color.ohos_id_color_text_primary')])
              }
              .width(36)
              .height(36)
              .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
              .borderRadius(18)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
              .onClick(() => {
                this.openSearch()
              })
            }

            Button({ type: ButtonType.Normal }) {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.folder_badge_plus'))
                  .fontSize(16)
                  .fontColor([$r('sys.color.ohos_id_color_text_primary')])
                Text('选择音乐')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
              }
            }
            .height(36)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .borderRadius(18)
            .padding({ left: 14, right: 14 })
            .shadow(ShadowStyle.OUTER_FLOATING_SM)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
            .onClick(() => {
              if (this.onSelectMusic) {
                this.onSelectMusic()
              }
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ top: this.topSafeHeight + 16, bottom: 12 })

          if (this.songCount > 0) {
            Row() {
              Text(`共 ${this.songCount} 首歌曲`)
                .fontSize(14)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))

              Blank()

              Button({ type: ButtonType.Capsule }) {
                Row() {
                  SymbolGlyph($r('sys.symbol.play_fill'))
                    .fontSize(16)
                    .fontColor([Color.White])
                  Text('全部播放')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                    .margin({ left: 4 })
                }
              }
              .height(32)
              .padding({ left: 16, right: 16 })
              .backgroundColor($r('sys.color.ohos_id_color_emphasize'))
              .shadow(ShadowStyle.OUTER_FLOATING_SM)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
              .onClick(() => {
                PlayerService.getInstance().playAt(0)
              })

              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.shuffle'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
                SymbolGlyph($r('sys.symbol.repeat'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
              }
              .margin({ left: 16 })
            }
            .width('100%')
            .padding({ bottom: 16 })
          } else {
            Row() {
              Text('暂无音乐，点击右上角添加')
                .fontSize(14)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            }
            .width('100%')
            .padding({ bottom: 16 })
          }
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .backgroundColor($r('sys.color.ohos_id_color_background'))
      .zIndex(10)

      if (this.songCount === 0) {
        Column({ space: 20 }) {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(72)
            .fontColor([$r('sys.color.ohos_id_color_text_secondary')])

          Text('未添加音乐')
            .fontSize(18)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .fontWeight(FontWeight.Medium)

          Text('点击上方"选择音乐"按钮添加')
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 32, right: 32 })
      } else if (this.isSearchActive && this.searchKeyword.trim().length > 0 &&
        this.dataSource.totalCount() === 0) {
        Column({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(48)
            .fontColor([$r('sys.color.ohos_id_color_text_secondary')])

          Text('未找到匹配歌曲')
            .fontSize(16)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 0 }) {
          LazyForEach(this.dataSource, (song: SongInfo, i: number) => {
            ListItem() {
              SongItem({
                song: song,
                index: i,
                isPlaying: this.isPlaying,
                isCurrentSong: i === this.currentIndex,
                isFavorite: this.parseFavoriteIds().has(song.id),
                showFavorite: true,
                globalIndex: this.searchResultIndices.length > 0 && i < this.searchResultIndices.length
                  ? this.searchResultIndices[i]
                  : i,
                onFavoriteToggle: () => {
                  void FavoriteManager.getInstance().toggleFavorite(song)
                }
              })
            }
          }, (song: SongInfo) => song.id)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .onDidScroll((scrollOffset: number) => {
          this.updateMiniPlayerScrollOffset(scrollOffset)
        })
        .divider({
          strokeWidth: 0.5,
          color: $r('sys.color.ohos_id_color_list_separator'),
          startMargin: 20,
          endMargin: 20
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  }
}
