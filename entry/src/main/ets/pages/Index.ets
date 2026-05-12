import { Colors, StorageKeys } from '../common/Constants'
import { SongListView } from '../components/SongListView'
import { FavoriteView } from '../components/FavoriteView'
import { FloatingTab } from '../components/FloatingTab'
import { PlayerSurface } from '../components/PlayerSurface'
import { GlobalContext, GCKeys } from '../common/GlobalContext'
import { image } from '@kit.ImageKit'
import { PlayerService } from '../service/PlayerService'
import { AudioPicker } from '../service/AudioPicker'
import { PlaylistManager } from '../service/PlaylistManager'
import { common } from '@kit.AbilityKit'
import { CoverThemeService, CoverPageTheme } from '../service/CoverThemeService'


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

  @State private playerMounted: boolean = false
  @State private playerProgress: number = 0
  @State private playerDockBottomOffset: number = 0
  @State private coverPixelMap: image.PixelMap | null = null
  @State private isLoading: boolean = false
  @State private loadingStatus: string = ''
  @State private loadingProgress: string = ''
  @State private lyricsProgress: number = 0

  private readonly playerOpenDuration: number = 460
  private readonly playerCloseDuration: number = 360
  private readonly tabSwitchDuration: number = 250
  private readonly dragThreshold: number = 300
  private playerHideTask: number = -1
  private playerOpenTask: number = -1
  private coverThemeTaskToken: number = 0
  private readonly coverThemeService: CoverThemeService = CoverThemeService.getInstance()

  aboutToAppear(): void {
    AppStorage.setOrCreate(StorageKeys.MODAL_OVERLAY_ACTIVE, false)
    AppStorage.setOrCreate(StorageKeys.IMMERSIVE_MODE_ACTIVE, false)
    AppStorage.setOrCreate(StorageKeys.IMMERSIVE_MODE_PROGRESS, 0)
    const count: number = AppStorage.get<number>(StorageKeys.SONG_COUNT) ?? 0
    if (count === 0) {
      AppStorage.setOrCreate(StorageKeys.SCAN_STATUS, 'idle')
    }
    void this.initCoverThemeService()
    this.syncCover()
  }

  aboutToDisappear(): void {
    this.clearPlayerHideTask()
    this.clearPlayerOpenTask()
  }

  private async initCoverThemeService(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      await this.coverThemeService.init(context)
      this.syncCover()
    } catch (error) {
      console.error('Index', `Init cover theme service failed: ${JSON.stringify(error)}`)
    }
  }

  private syncCover(): void {
    const pm = GlobalContext.getInstance().get(GCKeys.CURRENT_COVER)
    this.coverPixelMap = pm ? pm as image.PixelMap : null
    this.coverThemeTaskToken += 1
    const taskToken: number = this.coverThemeTaskToken
    const cacheKey: string = this.getCoverThemeCacheKey()
    void this.applyCoverTheme(cacheKey, this.coverPixelMap, taskToken)
  }

  private getCoverThemeCacheKey(): string {
    const song = PlayerService.getInstance().getCurrentSong()
    if (song) {
      if (song.coverUri.length > 0) {
        return `cover:${song.coverUri}`
      }
      if (song.id.length > 0) {
        return `song:${song.id}`
      }
      if (song.uri.length > 0) {
        return `uri:${song.uri}`
      }
    }
    return `version:${this.coverVersion}`
  }

  private async applyCoverTheme(cacheKey: string, pixelMap: image.PixelMap | null, taskToken: number): Promise<void> {
    const cachedTheme: CoverPageTheme | null = await this.coverThemeService.loadCachedTheme(cacheKey)
    if (taskToken !== this.coverThemeTaskToken) {
      return
    }

    if (cachedTheme) {
      this.coverThemeService.applyTheme(cachedTheme)
    }

    if (!pixelMap) {
      if (!cachedTheme && this.coverThemeService.isInitialized()) {
        this.coverThemeService.applyTheme(this.coverThemeService.getFallbackTheme(this.isDarkMode))
        AppStorage.setOrCreate(StorageKeys.DOMINANT_COLOR, Colors.DEFAULT_DOMINANT_COLOR)
      }
      return
    }

    const theme: CoverPageTheme = await this.coverThemeService.computeAndCacheTheme(cacheKey, pixelMap, this.isDarkMode)
    if (taskToken !== this.coverThemeTaskToken) {
      return
    }

    this.coverThemeService.applyTheme(theme)
    AppStorage.setOrCreate(StorageKeys.DOMINANT_COLOR, theme.glowColor)
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
      console.error('Index', `Choose audio files failed: ${JSON.stringify(error)}`)
    } finally {
      this.isLoading = false
      this.loadingStatus = ''
      this.loadingProgress = ''
    }
  }

  private clearPlayerHideTask(): void {
    if (this.playerHideTask >= 0) {
      clearTimeout(this.playerHideTask)
      this.playerHideTask = -1
    }
  }

  private clearPlayerOpenTask(): void {
    if (this.playerOpenTask >= 0) {
      clearTimeout(this.playerOpenTask)
      this.playerOpenTask = -1
    }
  }

  private canOpenNowPlaying(): boolean {
    return this.currentIndex >= 0 && this.currentTitle.length > 0
  }

  private clampProgress(value: number): number {
    return Math.max(0, Math.min(1, value))
  }

  private getNowPlayingContentOpacity(): number {
    return this.transitionT(0.78, 0.96)
  }

  private getMiniLayerOpacity(): number {
    if (!this.canOpenNowPlaying()) {
      return 0
    }
    if (!this.playerMounted) {
      return 1
    }
    return 1 - this.transitionT(0.00, 0.08)
  }

  private getMorphLayerOpacity(): number {
    if (!this.playerMounted) {
      return 0
    }

    const fadeIn: number = this.transitionT(0.00, 0.08)
    const fadeOut: number = 1 - this.transitionT(0.88, 0.98)
    return fadeIn * fadeOut
  }

  private isMiniInteractive(): boolean {
    return !this.playerMounted && this.playerProgress <= 0.001
  }

  private getMiniDockBottomOffset(): number {
    if (this.playerMounted) {
      return this.playerDockBottomOffset
    }
    return this.shouldReserveFloatingTabSpace() ? 78 : 0
  }

  private getPageContentScale(): number {
    return 1 - 0.035 * this.transitionT(0.04, 0.68)
  }

  private getPageContentOpacity(): number {
    return 1 - 0.44 * this.transitionT(0.04, 0.70)
  }

  private getPageContentBlur(): number {
    return 8 * this.transitionT(0.06, 0.78)
  }

  private transitionT(start: number, end: number): number {
    const t = this.clampProgress((this.playerProgress - start) / (end - start))
    return t * t * (3 - 2 * t)
  }

  private getFloatingTabOpacity(): number {
    if (this.songCount <= 0) {
      return 0
    }
    return 1 - this.transitionT(0.02, 0.36)
  }

  private isFloatingTabInteractive(): boolean {
    return this.songCount > 0 && !this.playerMounted && this.playerProgress < 0.05 && this.getFloatingTabOpacity() > 0.9
  }

  private getPlayerSurfaceZIndex(): number {
    return this.playerProgress > 0.05 ? 60 : 30
  }

  private getFloatingTabVisibility(): Visibility {
    return this.songCount > 0 && this.getFloatingTabOpacity() > 0.001 ? Visibility.Visible : Visibility.None
  }

  private switchTab(tabIndex: number): void {
    if (this.currentTab === tabIndex) {
      return
    }

    animateTo({
      duration: this.tabSwitchDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.currentTab = tabIndex
    })
  }

  private openNowPlaying(): void {
    if (!this.canOpenNowPlaying()) {
      return
    }

    this.clearPlayerOpenTask()
    this.clearPlayerHideTask()

    this.playerDockBottomOffset = this.getMiniDockBottomOffset()
    this.playerProgress = 0

    this.playerOpenTask = setTimeout(() => {
      this.playerOpenTask = -1
      animateTo({
        duration: this.playerOpenDuration,
        curve: Curve.Friction
      }, () => {
        this.playerMounted = true
        this.playerProgress = 1
      })
    }, 16) as number
  }

  private closeNowPlaying(): void {
    if (!this.playerMounted) {
      return
    }

    this.clearPlayerOpenTask()
    this.clearPlayerHideTask()
    this.lyricsProgress = 0

    animateTo({
      duration: this.playerCloseDuration,
      curve: Curve.Friction
    }, () => {
      this.playerProgress = 0
    })

    this.playerHideTask = setTimeout(() => {
      this.lyricsProgress = 0
      this.playerMounted = false
      this.playerHideTask = -1
    }, this.playerCloseDuration + 80) as number
  }

  private updateNowPlayingSwipe(offsetY: number): void {
    if (offsetY > 0) {
      this.playerProgress = this.clampProgress(1 - offsetY / this.dragThreshold)
      return
    }

    const boost: number = Math.min(1, this.playerProgress + Math.abs(offsetY) / (this.dragThreshold * 2))
    this.playerProgress = this.clampProgress(boost)
  }

  private snapNowPlaying(velocityY: number): void {
    this.clearPlayerOpenTask()
    const p = this.playerProgress
    const shouldOpen: boolean = p > 0.45 || velocityY < -400
    const shouldClose: boolean = p < 0.40 || velocityY > 400

    if (shouldOpen && !shouldClose) {
      this.clearPlayerHideTask()
      animateTo({ duration: this.playerOpenDuration, curve: Curve.Friction }, () => {
        this.playerProgress = 1
      })
      return
    }

    if (shouldClose && !shouldOpen) {
      this.closeNowPlaying()
      return
    }

    if (p >= 0.5) {
      this.clearPlayerHideTask()
      animateTo({ duration: this.playerOpenDuration, curve: Curve.Friction }, () => {
        this.playerProgress = 1
      })
    } else {
      this.closeNowPlaying()
    }
  }

  onBackPress(): boolean | void {
    if (this.playerMounted || this.playerProgress > 0.01) {
      this.closeNowPlaying()
      return true
    }

    if (this.currentTab !== 0) {
      this.switchTab(0)
      return true
    }

    return false
  }

  @Builder
  private PageContentBuilder() {
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
        Stack() {
          SongListView({
            onSelectMusic: () => {
              this.pickAudioFiles()
            }
          })
            .width('100%')
            .height('100%')
            .opacity(this.currentTab === 0 ? 1 : 0)
            .translate({ x: this.currentTab === 0 ? 0 : -24, y: 0 })
            .hitTestBehavior(this.currentTab === 0 ? HitTestMode.Default : HitTestMode.None)
            .zIndex(this.currentTab === 0 ? 1 : 0)

          FavoriteView()
            .width('100%')
            .height('100%')
            .opacity(this.currentTab === 1 ? 1 : 0)
            .translate({ x: this.currentTab === 1 ? 0 : 24, y: 0 })
            .hitTestBehavior(this.currentTab === 1 ? HitTestMode.Default : HitTestMode.None)
            .zIndex(this.currentTab === 1 ? 1 : 0)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  private shouldReserveFloatingTabSpace(): boolean {
    return this.songCount > 0 && !this.playerMounted && this.playerProgress <= 0.001
  }

  private shouldBuildPlayerSurface(): boolean {
    return this.playerMounted || this.playerProgress > 0.001 || this.canOpenNowPlaying()
  }

  @Builder
  private PlayerContainer() {
    PlayerSurface({
      progress: this.playerProgress,
      mounted: this.playerMounted,
      canOpen: this.canOpenNowPlaying(),
      dockBottomOffset: this.playerDockBottomOffset,
      miniDockBottomOffset: this.getMiniDockBottomOffset(),
      lyricsProgress: this.lyricsProgress,
      contentLayerProgress: this.getNowPlayingContentOpacity(),
      miniLayerOpacity: this.getMiniLayerOpacity(),
      morphLayerOpacity: this.getMorphLayerOpacity(),
      miniInteractive: this.isMiniInteractive(),
      onOpen: () => {
        this.openNowPlaying()
      },
      onClose: () => {
        this.closeNowPlaying()
      },
      onSwipeUpdate: (offsetY: number) => {
        this.updateNowPlayingSwipe(offsetY)
      },
      onSwipeEnd: (velocityY: number) => {
        this.snapNowPlaying(velocityY)
      },
      onLyricsProgress: (progress: number) => {
        this.lyricsProgress = progress
      }
    })
      .width('100%')
      .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.PageContentBuilder()
      }
      .width('100%')
      .height('100%')
      .scale({
        x: this.getPageContentScale(),
        y: this.getPageContentScale(),
        centerX: '50%',
        centerY: '50%'
      })
      .opacity(this.getPageContentOpacity())
      .blur(this.getPageContentBlur())

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.10)')
        .opacity(this.playerMounted ? this.playerProgress : 0)
        .hitTestBehavior(HitTestMode.None)
        .zIndex(10)

      if (this.shouldBuildPlayerSurface()) {
        Stack() {
          this.PlayerContainer()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(this.getPlayerSurfaceZIndex())
      }

      Column() {
        FloatingTab({
          currentTab: this.currentTab,
          dominantColor: this.dominantColor,
          isDarkMode: this.isDarkMode,
          onTabChange: (tabIndex: number) => {
            this.switchTab(tabIndex)
          }
        })
      }
      .width('100%')
      .padding({
        left: 18,
        right: 18,
        bottom: this.bottomSafeHeight + 24
      })
      .opacity(this.getFloatingTabOpacity())
      .visibility(this.getFloatingTabVisibility())
      .hitTestBehavior(this.isFloatingTabInteractive() ? HitTestMode.Default : HitTestMode.None)
      .zIndex(40)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
