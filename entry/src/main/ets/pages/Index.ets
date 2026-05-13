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

  @State private isPlayerExpanded: boolean = false
  @State private coverPixelMap: image.PixelMap | null = null
  @State private isLoading: boolean = false
  @State private loadingStatus: string = ''
  @State private loadingProgress: string = ''
  @State private lyricsProgress: number = 0
  @State private hdsMiniBarCompactContent: boolean = false
  @State private hdsMiniBarAnimating: boolean = false
  @State private immersiveMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE

  private readonly tabSwitchDuration: number = 250
  private readonly hdsTabBarHeight: number = 66
  private readonly hdsTabBottomMargin: number = 24
  private readonly hdsMiniBarSmallWidth: number = 240
  private readonly hdsMiniBarMediumWidth: number = 260
  private readonly hdsMiniBarLargeWidth: number = 320
  private readonly hdsMiniBarClickGuardDuration: number = 760
  private readonly coverGeometryTransitionId: string = 'player_cover_image'
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

    if (this.isPlayerExpanded) {
      return
    }

    if (this.hdsMiniBarCompactContent || this.hdsMiniBarAnimating || this.isHdsMiniBarClickGuardActive()) {
      return
    }

    this.lyricsProgress = 0
    animateTo({
      curve: curves.springMotion(0.4, 0.8)
    }, () => {
      this.isPlayerExpanded = true
    })
  }

  private closeNowPlaying(): void {
    if (!this.isPlayerExpanded) {
      return
    }

    this.lyricsProgress = 0
    animateTo({
      curve: curves.springMotion(0.4, 0.85)
    }, () => {
      this.isPlayerExpanded = false
    })
  }

  onBackPress(): boolean | void {
    if (this.isPlayerExpanded) {
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
    return this.canOpenNowPlaying() && !this.isPlayerExpanded
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
      coverGeometryId: this.shouldShowHdsMiniBar() ? this.coverGeometryTransitionId : '',
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

  private shouldUseFullPlayerLayer(): boolean {
    return this.isPlayerExpanded
  }

  private shouldMountPlayerLayer(): boolean {
    return this.shouldUseFullPlayerLayer()
  }

  @Builder
  private PlayerContainer() {
    PlayerSurface({
      activeContent: this.isPlayerExpanded,
      coverGeometryId: this.coverGeometryTransitionId,
      onClose: () => {
        this.closeNowPlaying()
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
        x: this.isPlayerExpanded ? 0.975 : 1,
        y: this.isPlayerExpanded ? 0.975 : 1,
        centerX: '50%',
        centerY: '50%'
      })
      .opacity(this.isPlayerExpanded ? 0.72 : 1)

      if (this.isPlayerExpanded) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.10)')
          .hitTestBehavior(HitTestMode.Transparent)
          .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseInOut }))
          .zIndex(10)
      }

      if (this.shouldMountPlayerLayer()) {
        Stack() {
          this.PlayerContainer()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Default)
        .transition(
          TransitionEffect.translate({ y: '100%' })
            .combine(TransitionEffect.OPACITY)
            .animation({ curve: curves.springMotion(0.4, 0.8) })
        )
        .zIndex(30)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
