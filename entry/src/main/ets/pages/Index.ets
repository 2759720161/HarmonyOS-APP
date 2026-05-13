import { Colors, StorageKeys } from '../common/Constants'
import { SongListView } from '../components/SongListView'
import { FavoriteView } from '../components/FavoriteView'
import { PlayerSurface, SurfaceMiniPlayer } from '../components/PlayerSurface'
import { GlobalContext, GCKeys } from '../common/GlobalContext'
import { image } from '@kit.ImageKit'
import { PlayerService } from '../service/PlayerService'
import { AudioPicker } from '../service/AudioPicker'
import { PlaylistManager } from '../service/PlaylistManager'
import { common } from '@kit.AbilityKit'
import { CoverThemeService, CoverPageTheme } from '../service/CoverThemeService'
import { curves } from '@kit.ArkUI'
import {
  HdsNavigation,
  HdsBarStyle,
  HdsTabs,
  HdsTabsBarChangeMode,
  HdsTabsController,
  HdsTabsFloatingStyle,
  SystemMaterialParams,
  hdsMaterial
} from '@kit.UIDesignKit'


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
  @State private hdsMiniBarCompactContent: boolean = false
  @State private hdsMiniBarAnimating: boolean = false
  @State private immersiveMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE

  private readonly playerOpenDuration: number = 520
  private readonly playerCloseDuration: number = 430
  private readonly tabSwitchDuration: number = 250
  private readonly hdsTabBarHeight: number = 66
  private readonly hdsTabBottomMargin: number = 24
  private readonly hdsMiniBarSmallWidth: number = 240
  private readonly hdsMiniBarMediumWidth: number = 260
  private readonly hdsMiniBarLargeWidth: number = 320
  private readonly hdsMiniBarClickGuardDuration: number = 760
  private readonly dragThreshold: number = 300
  private playerHideTask: number = -1
  private playerOpenTask: number = -1
  private hdsMiniBarGuardTask: number = -1
  private hdsMiniBarStateTask: number = -1
  private hdsMiniBarGuardUntil: number = 0
  private pendingHdsMiniBarCollapsed: boolean = false
  private coverThemeTaskToken: number = 0
  private tabsController: HdsTabsController = new HdsTabsController()
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
    this.resolveImmersiveMaterialLevel()
    this.syncCover()
  }

  aboutToDisappear(): void {
    this.clearPlayerHideTask()
    this.clearPlayerOpenTask()
    this.clearHdsMiniBarGuardTask()
    this.clearHdsMiniBarStateTask()
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

  private clearHdsMiniBarGuardTask(): void {
    if (this.hdsMiniBarGuardTask >= 0) {
      clearTimeout(this.hdsMiniBarGuardTask)
      this.hdsMiniBarGuardTask = -1
    }
  }

  private clearHdsMiniBarStateTask(): void {
    if (this.hdsMiniBarStateTask >= 0) {
      clearTimeout(this.hdsMiniBarStateTask)
      this.hdsMiniBarStateTask = -1
    }
  }

  private canOpenNowPlaying(): boolean {
    return this.currentIndex >= 0 && this.currentTitle.length > 0
  }

  private clampProgress(value: number): number {
    return Math.max(0, Math.min(1, value))
  }

  private getNowPlayingContentOpacity(): number {
    // 全屏内容层延后到 morph 空间动画基本落位后再显现。
    // 避免封面页已经出现时，morph 层里的封面/歌名/歌手仍继续向上飞。
    const t = this.clampProgress((this.playerProgress - 0.90) / 0.08)
    return t * t * (3 - 2 * t)
  }

  private getMiniLayerOpacity(): number {
    if (!this.canOpenNowPlaying()) {
      return 0
    }
    if (!this.playerMounted) {
      return 1
    }
    return 1 - this.transitionT(0.00, 0.10)
  }

  private getMorphLayerOpacity(): number {
    if (!this.playerMounted) {
      return 0
    }

    // morph 层在展开初段淡入，在 full 内容接管前淡出。
    // 这样 full 封面页和 morph 封面不会重叠造成“往上飞”的残影。
    const fadeIn = this.transitionT(0.00, 0.10)
    const fadeOut = 1 - this.transitionT(0.94, 0.995)
    return fadeIn * fadeOut
  }

  private isMiniInteractive(): boolean {
    return !this.playerMounted && this.playerProgress <= 0.001
  }

  private getMiniDockBottomOffset(): number {
    // Keep the transition mini aligned with the HDS miniBar start position.
    if (this.playerMounted) {
      return this.playerDockBottomOffset
    }
    return Math.max(0, this.hdsTabBottomMargin - 20)
  }

  private getPageContentScale(): number {
    return 1 - 0.025 * this.playerProgress
  }

  private getPageContentOpacity(): number {
    return 1 - 0.42 * this.playerProgress
  }

  private transitionT(start: number, end: number): number {
    const t = this.clampProgress((this.playerProgress - start) / (end - start))
    return t * t * (3 - 2 * t)
  }

  private switchTab(tabIndex: number): void {
    if (this.currentTab === tabIndex) {
      return
    }

    this.tabsController.changeIndex(tabIndex)
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

    if (this.hdsMiniBarCompactContent || this.hdsMiniBarAnimating || this.isHdsMiniBarClickGuardActive()) {
      return
    }

    this.clearPlayerOpenTask()
    this.clearPlayerHideTask()

    this.playerDockBottomOffset = this.getMiniDockBottomOffset()
    this.playerMounted = true
    this.playerProgress = 0

    this.playerOpenTask = setTimeout(() => {
      this.playerOpenTask = -1
      animateTo({
        duration: this.playerOpenDuration,
        curve: Curve.Friction
      }, () => {
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

  private getInactiveTabColor(): ResourceColor {
    return this.isDarkMode ? 'rgba(255, 255, 255, 0.62)' : '#6F5963'
  }

  private getTabItemColor(tabIndex: number): ResourceColor {
    return this.currentTab === tabIndex ? this.dominantColor : this.getInactiveTabColor()
  }

  private resolveImmersiveMaterialLevel(): void {
    const materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes()
    if (materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) < 0) {
      this.immersiveMaterialLevel = hdsMaterial.MaterialLevel.SMOOTH
      return
    }
    this.immersiveMaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE
  }

  private buildAdaptiveMaterialEffect(): SystemMaterialParams {
    return {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: this.immersiveMaterialLevel
    }
  }

  private shouldShowHdsMiniBar(): boolean {
    return this.canOpenNowPlaying() && !this.shouldUseFullPlayerLayer()
  }

  private updateHdsMiniBarStyle(style: HdsBarStyle): void {
    this.deferHdsMiniBarState(style, true)
  }

  private onHdsMiniBarAnimationStart(style: HdsBarStyle): void {
    this.deferHdsMiniBarState(style, true)
  }

  private onHdsMiniBarAnimationEnd(style: HdsBarStyle): void {
    this.deferHdsMiniBarState(style, false)
  }

  private isHdsMiniBarClickGuardActive(): boolean {
    return Date.now() < this.hdsMiniBarGuardUntil
  }

  private extendHdsMiniBarClickGuard(): void {
    this.hdsMiniBarGuardUntil = Date.now() + this.hdsMiniBarClickGuardDuration
    this.clearHdsMiniBarGuardTask()
    this.hdsMiniBarGuardTask = setTimeout(() => {
      this.hdsMiniBarGuardTask = -1
      if (!this.isHdsMiniBarClickGuardActive()) {
        this.hdsMiniBarAnimating = false
      }
    }, this.hdsMiniBarClickGuardDuration) as number
  }

  private deferHdsMiniBarState(style: HdsBarStyle, guardClick: boolean): void {
    this.pendingHdsMiniBarCollapsed = style === HdsBarStyle.COLLAPSE
    if (guardClick) {
      this.extendHdsMiniBarClickGuard()
    }

    if (this.hdsMiniBarStateTask >= 0) {
      return
    }

    this.hdsMiniBarStateTask = setTimeout(() => {
      this.hdsMiniBarStateTask = -1
      this.hdsMiniBarCompactContent = this.pendingHdsMiniBarCollapsed
      this.hdsMiniBarAnimating = this.isHdsMiniBarClickGuardActive()
    }, 0) as number
  }

  private buildHdsTabFloatingStyle(): HdsTabsFloatingStyle {
    const floatingStyle: HdsTabsFloatingStyle = {
      barSideMargin: 18,
      barBottomMargin: this.bottomSafeHeight + this.hdsTabBottomMargin,
      thermoCtrl: true,
      systemMaterialEffect: this.buildAdaptiveMaterialEffect()
    }

    if (this.shouldShowHdsMiniBar()) {
      floatingStyle.miniBar = {
        miniBarBuilder: () => {
          this.HdsMiniPlayerBarBuilder()
        },
        miniBarWidth: {
          smallWidth: this.hdsMiniBarSmallWidth,
          mediumWidth: this.hdsMiniBarMediumWidth,
          largeWidth: this.hdsMiniBarLargeWidth
        },
        enableMiniBarBackground: true,
        enableMiniBarClip: true,
        onBarStyleChange: (
          miniBarStyle: HdsBarStyle,
          _tabBarStyle: HdsBarStyle,
          _miniBarWidth: number,
          _tabBarWidth: number,
          _mode: HdsTabsBarChangeMode
        ) => {
          this.updateHdsMiniBarStyle(miniBarStyle)
        },
        onMiniBarAnimationStart: (style: HdsBarStyle, _width: number) => {
          this.onHdsMiniBarAnimationStart(style)
        },
        onMiniBarAnimationEnd: (style: HdsBarStyle) => {
          this.onHdsMiniBarAnimationEnd(style)
        }
      }
    }

    return floatingStyle
  }

  @Builder
  private HdsMiniPlayerBarBuilder() {
    SurfaceMiniPlayer({
      visible: this.canOpenNowPlaying(),
      opacityValue: this.shouldShowHdsMiniBar() ? 1 : 0,
      interactive: this.shouldShowHdsMiniBar(),
      dockBottomOffset: 0,
      embeddedInHdsMaterial: true,
      compactMode: this.hdsMiniBarCompactContent,
      animating: this.hdsMiniBarAnimating,
      coverGeometryId: this.shouldShowHdsMiniBar() ? 'player_cover_image' : '',
      onOpen: () => {
        this.openNowPlaying()
      }
    })
      .height(this.hdsTabBarHeight)
  }

  @Builder
  private customTabBar(tabIndex: number, icon: Resource, text: string): void {
    Column({ space: 3 }) {
      SymbolGlyph(icon)
        .fontSize(23)
        .fontColor([this.getTabItemColor(tabIndex)])

      Text(text)
        .fontSize(11)
        .fontWeight(this.currentTab === tabIndex ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.getTabItemColor(tabIndex))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .scale({
      x: this.currentTab === tabIndex ? 1.06 : 0.96,
      y: this.currentTab === tabIndex ? 1.06 : 0.96
    })
    .translate({ y: this.currentTab === tabIndex ? -2 : 0 })
    .opacity(this.currentTab === tabIndex ? 1 : 0.82)
    .animation({ duration: 320, curve: curves.springMotion() })
  }

  @Builder
  private PageContentBuilder() {
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
      HdsNavigation() {
        HdsTabs({ controller: this.tabsController, index: this.currentTab }) {
          TabContent() {
            SongListView({
              onSelectMusic: () => {
                this.pickAudioFiles()
              }
            })
              .width('100%')
              .height('100%')
          }
          .width('100%')
          .height('100%')
          .tabBar(this.customTabBar(0, $r('sys.symbol.music'), '歌曲'))

          TabContent() {
            FavoriteView()
              .width('100%')
              .height('100%')
          }
          .width('100%')
          .height('100%')
          .tabBar(this.customTabBar(1, $r('sys.symbol.heart'), '收藏'))
        }
        .width('100%')
        .height('100%')
        .vertical(false)
        .barPosition(BarPosition.End)
        .barMode(BarMode.Fixed)
        .scrollable(true)
        .animationDuration(240)
        .barHeight(this.hdsTabBarHeight)
        .barOverlap(true)
        .barFloatingStyle(this.buildHdsTabFloatingStyle())
        .onChange((index: number) => {
          this.currentTab = index
        })
      }
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .hideTitleBar(true)
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_background'))
    }
  }

  private shouldReserveHdsTabSpace(): boolean {
    return this.songCount > 0 && !this.playerMounted && this.playerProgress <= 0.001
  }

  private shouldUseFullPlayerLayer(): boolean {
    return this.playerMounted || this.playerProgress > 0.001
  }

  private shouldMountPlayerLayer(): boolean {
    return this.shouldUseFullPlayerLayer()
  }

  private getMiniPlayerLayerHeight(): number {
    if (!this.canOpenNowPlaying()) {
      return 0
    }
    return this.bottomSafeHeight + 20 + this.getMiniDockBottomOffset() + 64
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

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.10)')
        .opacity(this.playerMounted ? this.playerProgress : 0)
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(10)

      if (this.shouldMountPlayerLayer()) {
        Stack() {
          this.PlayerContainer()
        }
        .width('100%')
        .height(this.shouldUseFullPlayerLayer() ? '100%' : this.getMiniPlayerLayerHeight())
        .hitTestBehavior(this.shouldUseFullPlayerLayer() ? HitTestMode.Default : HitTestMode.Transparent)
        .zIndex(30)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
