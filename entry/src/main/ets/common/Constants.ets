/**
 * 全局常量与工具函数
 */

/** 播放模式 */
export enum PlayMode {
  SEQUENCE = 0,  // 列表循环
  SINGLE = 1,    // 单曲循环
  SHUFFLE = 2    // 随机播放
}

/** AppStorage 键名（使用 string literals 保证类型安全） */
export class StorageKeys {
  static readonly IS_PLAYING: string = 'isPlaying'
  static readonly CURRENT_INDEX: string = 'currentIndex'
  static readonly CURRENT_POSITION: string = 'currentPosition'
  static readonly TOTAL_DURATION: string = 'totalDuration'
  static readonly PLAY_MODE: string = 'playMode'
  static readonly SONG_COUNT: string = 'songCount'
  static readonly CURRENT_TITLE: string = 'currentTitle'
  static readonly CURRENT_ARTIST: string = 'currentArtist'
  static readonly CURRENT_ALBUM: string = 'currentAlbum'
  static readonly COVER_VERSION: string = 'coverVersion'
  static readonly TOP_SAFE_HEIGHT: string = 'topSafeHeight'
  static readonly BOTTOM_SAFE_HEIGHT: string = 'bottomSafeHeight'
  static readonly SCREEN_HEIGHT_VP: string = 'screenHeightVp'
  static readonly SCREEN_WIDTH_VP: string = 'screenWidthVp'
  static readonly IS_DARK_MODE: string = 'isDarkMode'
  static readonly SCAN_STATUS: string = 'scanStatus'  // 'idle'|'scanning'|'done'|'empty'
  static readonly DOMINANT_COLOR: string = 'dominantColor'
  static readonly COVER_THEME_PRIMARY_COLOR: string = 'coverThemePrimaryColor'
  static readonly COVER_THEME_SECONDARY_COLOR: string = 'coverThemeSecondaryColor'
  static readonly MINI_PLAYER_SCROLL_OFFSET: string = 'miniPlayerScrollOffset'
  static readonly CURRENT_LYRIC: string = 'currentLyric'
  static readonly LYRIC_LINES: string = 'lyricLines'
  static readonly LYRIC_INDEX: string = 'lyricIndex'
  static readonly FAVORITE_IDS: string = 'favoriteIds'
  static readonly FAVORITE_COUNT: string = 'favoriteCount'
  static readonly CURRENT_TAB: string = 'currentTab'
  static readonly DETAIL_DIALOG_VISIBLE: string = 'detailDialogVisible'
  static readonly NOW_PLAYING_OVERLAY_ACTIVE: string = 'nowPlayingOverlayActive'
  static readonly IMMERSIVE_MODE_ACTIVE: string = 'immersiveModeActive'
  static readonly IMMERSIVE_MODE_PROGRESS: string = 'immersiveModeProgress'
}

/** 格式化毫秒为 mm:ss */
export function formatMs(ms: number): string {
  if (!ms || ms <= 0) {
    return '00:00'
  }
  const totalSec: number = Math.floor(ms / 1000)
  const min: number = Math.floor(totalSec / 60)
  const sec: number = totalSec % 60
  const minStr: string = min < 10 ? `0${min}` : `${min}`
  const secStr: string = sec < 10 ? `0${sec}` : `${sec}`
  return `${minStr}:${secStr}`
}

/** 根据播放模式获取对应的 SymbolGlyph 名称 */
export function getPlayModeIcon(mode: PlayMode): Resource {
  if (mode === PlayMode.SINGLE) {
    return $r('sys.symbol.repeat_1')
  } else if (mode === PlayMode.SHUFFLE) {
    return $r('sys.symbol.shuffle')
  }
  return $r('sys.symbol.repeat')
}

/** 颜色常量 */
export class Colors {
  static readonly PRIMARY_BG: string = '#0A0A14'
  static readonly SURFACE: string = 'rgba(255,255,255,0.08)'
  static readonly TEXT_PRIMARY: string = '#FFFFFF'
  static readonly TEXT_SECONDARY: string = 'rgba(255,255,255,0.6)'
  static readonly TEXT_HINT: string = 'rgba(255,255,255,0.35)'
  static readonly ACCENT: string = '#7B7FFF'
  static readonly ACCENT_LIGHT: string = 'rgba(123,127,255,0.3)'
  static readonly BLUR_BG: string = 'rgba(12,12,24,0.55)'
  static readonly DIVIDER: string = 'rgba(255,255,255,0.08)'
  static readonly DEFAULT_DOMINANT_COLOR: string = '#7B7FFF'
  static readonly UNKNOWN_ARTIST: string = '未知歌手'
  static readonly UNKNOWN_TITLE: string = '未知曲目'
}
