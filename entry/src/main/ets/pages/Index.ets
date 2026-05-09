import { Colors, StorageKeys } from '../common/Constants'
import { SongListView } from '../components/SongListView'
import { FavoriteView } from '../components/FavoriteView'
import { FloatingTab } from '../components/FloatingTab'
import { NowPlayingView } from '../components/NowPlayingView'
import { MiniPlayer } from '../components/MiniPlayer'
import { GlobalContext, GCKeys } from '../common/GlobalContext'
import { image } from '@kit.ImageKit'
import { PlayerService } from '../service/PlayerService'
import { AudioPicker } from '../service/AudioPicker'
import { PlaylistManager } from '../service/PlaylistManager'
import { common } from '@kit.AbilityKit'

@Entry
@Component
struct Index {
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('currentIndex') currentIndex: number = -1
  @StorageLink('currentTitle') currentTitle: string = ''
  @StorageLink('currentArtist') currentArtist: string = ''
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('coverVersion') @Watch('syncCover') coverVersion: number = 0
  @StorageLink('currentPosition') currentPosition: number = 0
  @StorageLink('totalDuration') totalDuration: number = 0
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @StorageLink('dominantColor') dominantColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @StorageLink('songCount') songCount: number = 0
  @StorageLink('currentTab') currentTab: number = 0
  @StorageLink('nowPlayingOverlayActive') nowPlayingOverlayActive: boolean = false

  @State private nowPlayingProgress: number = 0
  @State private coverPixelMap: image.PixelMap | null = null
  @State private isLoading: boolean = false
  @State private loadingStatus: string = ''
  @State private loadingProgress: string = ''
  @State private lyricsProgress: number = 0

  private readonly openDuration: number = 560
  private readonly openMorphDuration: number = 300
  private readonly openContentDuration: number = 360
  private readonly openSettleProgress: number = 0.60
  private readonly closeDuration: number = 340
  private readonly openMountProgress: number = 0.002
  private nowPlayingHideTask: number = -1
  private nowPlayingOpenTask: number = -1
  private readonly dragThreshold: number = 300

  aboutToAppear(): void {
    AppStorage.setOrCreate(StorageKeys.NOW_PLAYING_OVERLAY_ACTIVE, false)
    AppStorage.setOrCreate(StorageKeys.IMMERSIVE_MODE_ACTIVE, false)
    AppStorage.setOrCreate(StorageKeys.IMMERSIVE_MODE_PROGRESS, 0)
    const count: number = AppStorage.get<number>(StorageKeys.SONG_COUNT) ?? 0
    if (count === 0) {
      AppStorage.setOrCreate(StorageKeys.SCAN_STATUS, 'idle')
    }
    this.syncCover()
  }

  aboutToDisappear(): void {
    this.clearNowPlayingHideTask()
    this.clearNowPlayingOpenTask()
  }

  private syncCover(): void {
    const pm = GlobalContext.getInstance().get(GCKeys.CURRENT_COVER)
    this.coverPixelMap = pm ? pm as image.PixelMap : null

    if (!this.coverPixelMap) {
      AppStorage.setOrCreate(StorageKeys.DOMINANT_COLOR, Colors.DEFAULT_DOMINANT_COLOR)
    }
  }

  private async pickAudioFiles(): Promise<void> {
    try {
      this.isLoading = true
      const context = getContext(this) as common.UIAbilityContext
      const audioPicker = AudioPicker.getInstance()

      const songList = await audioPicker.pickAudioFiles(
        context,
        (status: string, current: number, total: number) => {
          this.loadingStatus = status
          this.loadingProgress = total > 0 ? `${current}/${total}` : ''
        }
      )

      if (songList.length > 0) {
        const playerService = PlayerService.getInstance()
        playerService.setSongList(PlaylistManager.getInstance().getPlaylist())
      }
    } catch (error) {
      console.error('Index', `选择文件失败: ${JSON.stringify(error)}`)
    } finally {
      this.isLoading = false
      this.loadingStatus = ''
      this.loadingProgress = ''
    }
  }

  @Builder
  NowPlayingBuilder() {
    NowPlayingView({
      expandProgress: this.nowPlayingProgress,
      onClose: () => {
        this.closeNowPlaying()
      },
      onSwipeUpdate: (offsetY: number) => {
        if (offsetY > 0) {
          this.nowPlayingProgress = Math.max(0, 1 - offsetY / this.dragThreshold)
        } else {
          const boost: number = Math.min(1, this.nowPlayingProgress + Math.abs(offsetY) / (this.dragThreshold * 2))
          this.nowPlayingProgress = Math.min(1, boost)
        }
      },
      onSwipeEnd: (velocityY: number) => {
        this.snapNowPlaying(velocityY)
      },
      onLyricsProgress: (progress: number) => {
        this.lyricsProgress = progress
      }
    })
  }

  @Builder
  PageContentBuilder() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('sys.color.ohos_id_color_emphasize'))

          Text(this.loadingStatus)
            .fontSize(14)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .margin({ top: 12 })

          if (this.loadingProgress.length > 0) {
            Text(this.loadingProgress)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .margin({ top: 4 })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        if (this.currentTab === 0) {
          SongListView({
            onSelectMusic: () => {
              this.pickAudioFiles()
            }
          })
            .width('100%')
            .height('100%')
        } else {
          FavoriteView()
            .width('100%')
            .height('100%')
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  private clearNowPlayingHideTask(): void {
    if (this.nowPlayingHideTask >= 0) {
      clearTimeout(this.nowPlayingHideTask)
      this.nowPlayingHideTask = -1
    }
  }

  private clearNowPlayingOpenTask(): void {
    if (this.nowPlayingOpenTask >= 0) {
      clearTimeout(this.nowPlayingOpenTask)
      this.nowPlayingOpenTask = -1
    }
  }

  private canOpenNowPlaying(): boolean {
    return this.currentIndex >= 0 && this.currentTitle.length > 0
  }

  private clampProgress(value: number): number {
    return Math.max(0, Math.min(1, value))
  }

  private updateMiniSwipe(offsetY: number): void {
    if (!this.canOpenNowPlaying()) {
      return
    }

    this.clearNowPlayingOpenTask()

    if (offsetY < 0) {
      this.nowPlayingProgress = this.clampProgress(Math.abs(offsetY) / this.dragThreshold)
    } else {
      this.nowPlayingProgress = this.clampProgress(1 - offsetY / this.dragThreshold)
    }
  }

  private animateOpenNowPlaying(): void {
    // 第一阶段：封面与歌名形变上移（progress 0 → morphEnd），此时其它按钮/信息仍为 0 透明度
    animateTo({
      duration: this.openMorphDuration,
      curve: Curve.EaseOut
    }, () => {
      this.nowPlayingProgress = this.openSettleProgress
    })
    // 第二阶段：进度推到 1，驱动 TopBar / SongHeader / ProgressSection / PlayControls 依阈值从底部淡入
    this.clearNowPlayingOpenTask()
    this.nowPlayingOpenTask = setTimeout(() => {
      this.nowPlayingOpenTask = -1
      animateTo({
        duration: this.openContentDuration,
        curve: Curve.EaseOut
      }, () => {
        this.nowPlayingProgress = 1
      })
    }, this.openMorphDuration) as number
  }

  private openNowPlaying(): void {
    if (!this.canOpenNowPlaying()) {
      return
    }
    this.clearNowPlayingOpenTask()
    this.clearNowPlayingHideTask()

    if (this.nowPlayingProgress <= 0.001) {
      this.nowPlayingProgress = this.openMountProgress
      this.nowPlayingOpenTask = setTimeout(() => {
        this.nowPlayingOpenTask = -1
        this.animateOpenNowPlaying()
      }, 16) as number
      return
    }

    this.animateOpenNowPlaying()
  }

  private closeNowPlaying(): void {
    if (this.nowPlayingProgress <= 0) {
      return
    }
    this.clearNowPlayingOpenTask()
    this.clearNowPlayingHideTask()
    animateTo({
      duration: this.closeDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.nowPlayingProgress = 0
    })
    this.nowPlayingHideTask = setTimeout(() => {
      this.lyricsProgress = 0
      this.nowPlayingHideTask = -1
    }, this.closeDuration) as number
  }

  private snapNowPlaying(velocityY: number): void {
    this.clearNowPlayingOpenTask()
    const p = this.nowPlayingProgress
    const shouldOpen: boolean = p > 0.4 || velocityY < -400
    const shouldClose: boolean = p < 0.35 || velocityY > 400

    if (shouldOpen && !shouldClose) {
      this.clearNowPlayingHideTask()
      animateTo({ duration: this.openDuration, curve: Curve.EaseOut }, () => {
        this.nowPlayingProgress = 1
      })
    } else if (shouldClose && !shouldOpen) {
      this.clearNowPlayingHideTask()
      animateTo({ duration: this.closeDuration, curve: Curve.EaseInOut }, () => {
        this.nowPlayingProgress = 0
      })
      this.nowPlayingHideTask = setTimeout(() => {
        this.lyricsProgress = 0
        this.nowPlayingHideTask = -1
      }, this.closeDuration) as number
    } else if (p >= 0.5) {
      this.clearNowPlayingHideTask()
      animateTo({ duration: this.openDuration, curve: Curve.EaseOut }, () => {
        this.nowPlayingProgress = 1
      })
    } else {
      this.clearNowPlayingHideTask()
      animateTo({ duration: this.closeDuration, curve: Curve.EaseInOut }, () => {
        this.nowPlayingProgress = 0
      })
      this.nowPlayingHideTask = setTimeout(() => {
        this.lyricsProgress = 0
        this.nowPlayingHideTask = -1
      }, this.closeDuration) as number
    }
  }

  onBackPress(): boolean | void {
    if (this.nowPlayingProgress > 0.01) {
      this.closeNowPlaying()
      return true
    }
    return false
  }

  private getMiniPlayerTitle(): string {
    if (this.currentTitle.length > 0) {
      return this.currentTitle
    }
    return '未在播放'
  }

  @Builder
  MiniPlayerFloatingNav() {
    MiniPlayer({
      expandProgress: this.nowPlayingProgress,
      lyricsProgress: this.lyricsProgress,
      dockBottomOffset: this.shouldShowFloatingTab() ? 78 : 0,
      onOpen: () => {
        this.openNowPlaying()
      },
      onSwipeUpdate: (offsetY: number) => {
        this.updateMiniSwipe(offsetY)
      },
      onSwipeEnd: (velocityY: number) => {
        this.snapNowPlaying(velocityY)
      }
    })
  }

  private shouldShowFloatingTab(): boolean {
    return this.songCount > 0 && this.nowPlayingProgress < 0.05
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.PageContentBuilder()

      if (this.nowPlayingProgress > 0.001) {
        Stack({ alignContent: Alignment.Bottom }) {
          this.NowPlayingBuilder()
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .clip(true)
        .hitTestBehavior(this.nowPlayingProgress < 0.85 ? HitTestMode.None : HitTestMode.Default)
        .zIndex(this.nowPlayingOverlayActive ? 30 : 0)
      }

      Column() {
        this.MiniPlayerFloatingNav()
      }
      .width('100%')
      .hitTestBehavior(this.nowPlayingProgress > 0.05 ? HitTestMode.Transparent : HitTestMode.Default)
      .zIndex(this.nowPlayingOverlayActive ? 10 : 20)

      if (this.shouldShowFloatingTab()) {
        Column() {
          FloatingTab({
            currentTab: this.currentTab,
            dominantColor: this.dominantColor,
            isDarkMode: this.isDarkMode,
            onTabChange: (tabIndex: number) => {
              this.currentTab = tabIndex
            }
          })
        }
        .width('100%')
        .padding({
          left: 18,
          right: 18,
          bottom: this.bottomSafeHeight + 24
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
