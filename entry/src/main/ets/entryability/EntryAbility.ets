import { AbilityConstant, UIAbility, Want, abilityAccessCtrl, common, ConfigurationConstant } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { display } from '@kit.ArkUI'
import { StorageKeys } from '../common/Constants'
import { GlobalContext, GCKeys } from '../common/GlobalContext'
import { PlayerService } from '../service/PlayerService'
import { LrcApiConfigService } from '../service/LrcApiConfigService'
import { PlaylistManager } from '../service/PlaylistManager'
import { FavoriteManager } from '../service/FavoriteManager'
import { Configuration } from '@kit.AbilityKit'

const DOMAIN = 0x1001

export default class EntryAbility extends UIAbility {

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'MusicPlayer', 'Ability onCreate')
    GlobalContext.getInstance().set(GCKeys.ABILITY_CONTEXT, this.context)
    AppStorage.setOrCreate(StorageKeys.TOP_SAFE_HEIGHT, 0)
    AppStorage.setOrCreate(StorageKeys.BOTTOM_SAFE_HEIGHT, 0)
    AppStorage.setOrCreate(StorageKeys.SCAN_STATUS, 'idle')
    AppStorage.setOrCreate(StorageKeys.SONG_COUNT, 0)
    AppStorage.setOrCreate(StorageKeys.IS_PLAYING, false)
    AppStorage.setOrCreate(StorageKeys.CURRENT_INDEX, -1)
    AppStorage.setOrCreate(StorageKeys.CURRENT_TITLE, '')
    AppStorage.setOrCreate(StorageKeys.CURRENT_ARTIST, '')
    AppStorage.setOrCreate(StorageKeys.CURRENT_ALBUM, '')
    AppStorage.setOrCreate(StorageKeys.CURRENT_POSITION, 0)
    AppStorage.setOrCreate(StorageKeys.TOTAL_DURATION, 0)
    AppStorage.setOrCreate(StorageKeys.COVER_VERSION, 0)
    AppStorage.setOrCreate(StorageKeys.MINI_PLAYER_SCROLL_OFFSET, 0)
    AppStorage.setOrCreate(StorageKeys.FAVORITE_IDS, '[]')
    AppStorage.setOrCreate(StorageKeys.FAVORITE_COUNT, 0)
    AppStorage.setOrCreate(StorageKeys.CURRENT_TAB, 0)
    AppStorage.setOrCreate(
      StorageKeys.IS_DARK_MODE,
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    )

    // 设置应用跟随系统深浅色模式
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'MusicPlayer', 'Ability onDestroy')
    PlayerService.getInstance().release()
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, 'MusicPlayer', 'onWindowStageCreate')

    const windowClass: window.Window = await windowStage.getMainWindow()
    GlobalContext.getInstance().set(GCKeys.WINDOW_CLASS, windowClass)

    // 全屏沉浸式
    await windowClass.setWindowLayoutFullScreen(true)

    // 启动时根据当前系统配置刷新状态栏颜色
    await this.refreshSystemBars(this.context.config.colorMode)

    // 使用 display 模块获取屏幕密度（WindowProperties 中无此属性）
    const currentDisplay: display.Display = display.getDefaultDisplaySync()
    const density: number = currentDisplay.densityPixels > 0 ? currentDisplay.densityPixels : 3.0

    AppStorage.setOrCreate(StorageKeys.SCREEN_WIDTH_VP, currentDisplay.width / density)
    AppStorage.setOrCreate(StorageKeys.SCREEN_HEIGHT_VP, currentDisplay.height / density)

    // 监听避让区变化
    windowClass.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
        AppStorage.setOrCreate(StorageKeys.TOP_SAFE_HEIGHT,
          data.area.topRect.height / density)
        AppStorage.setOrCreate(StorageKeys.BOTTOM_SAFE_HEIGHT,
          data.area.bottomRect.height / density)
      }
    })

    // 立即获取当前避让区
    const systemArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
    AppStorage.setOrCreate(StorageKeys.TOP_SAFE_HEIGHT, systemArea.topRect.height / density)
    AppStorage.setOrCreate(StorageKeys.BOTTOM_SAFE_HEIGHT, systemArea.bottomRect.height / density)

    // 初始化在线歌词/封面 API 配置
    await LrcApiConfigService.getInstance().init(this.context as common.UIAbilityContext)

    // 加载页面
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'MusicPlayer', `加载页面失败: ${JSON.stringify(err)}`)
        return
      }
      hilog.info(DOMAIN, 'MusicPlayer', '页面加载成功')
    })

    // 初始化播放服务
    await PlayerService.getInstance().init(this.context)

    // 初始化播放列表管理器
    await PlaylistManager.getInstance().init(this.context as common.UIAbilityContext)

    // 初始化收藏管理器
    await FavoriteManager.getInstance().init(this.context as common.UIAbilityContext)

    // 从持久化存储加载播放列表
    const playlist = PlaylistManager.getInstance().getPlaylist()
    if (playlist.length > 0) {
      PlayerService.getInstance().setSongList(playlist)
      hilog.info(DOMAIN, 'MusicPlayer', `加载播放列表成功，共 ${playlist.length} 首`)

      // 同步收藏列表（移除已不存在的歌曲）
      await FavoriteManager.getInstance().syncWithPlaylist(playlist)

      const savedState = await PlayerService.getInstance().loadPersistedState()
      if (savedState) {
        PlayerService.getInstance().restoreFromPersistence(savedState)
        hilog.info(DOMAIN, 'MusicPlayer',
          `恢复上次播放: songId=${savedState.songId}, position=${savedState.position}ms`)
      }
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'MusicPlayer', 'onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'MusicPlayer', 'onForeground')
    this.refreshSystemBars(this.context.config.colorMode)
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'MusicPlayer', 'onBackground')
  }

  // 重构该方法，实现真正的动态适配
  private async refreshSystemBars(colorMode?: number): Promise<void> {
    try {
      const winClass = GlobalContext.getInstance().get(GCKeys.WINDOW_CLASS) as window.Window
      if (winClass) {
        // 如果没有传入 colorMode，则取当前上下文的配置
        const currentMode = colorMode ?? this.context.config.colorMode
        // 判断当前是否为深色模式
        const isDark = currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        // 深色模式下文字为白色，浅色模式下文字为黑色
        AppStorage.setOrCreate(StorageKeys.IS_DARK_MODE, isDark)
        const contentColor = isDark ? '#FFFFFFFF' : '#FF000000'

        // 状态栏透明，内容颜色动态适配
        await winClass.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: contentColor,
          navigationBarColor: '#00000000',
          navigationBarContentColor: contentColor
        })
      }
    } catch (_) {
      hilog.error(DOMAIN, 'MusicPlayer', 'Failed to set system bar properties')
    }
  }

  // 监听系统配置变化（包括深浅色模式切换）
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, 'MusicPlayer', `onConfigurationUpdate colorMode: ${newConfig.colorMode}`)
    this.refreshSystemBars(newConfig.colorMode)
  }
}
