import { image } from '@kit.ImageKit'
import { effectKit } from '@kit.ArkGraphics2D'
import { fileIo } from '@kit.CoreFileKit'
import promptAction from '@ohos.promptAction'
import { Colors, formatMs, StorageKeys } from '../common/Constants'
import { GlobalContext, GCKeys } from '../common/GlobalContext'
import { PlayerService } from '../service/PlayerService'
import { PlaylistManager } from '../service/PlaylistManager'
import { FavoriteManager } from '../service/FavoriteManager'
import { AudioScanner } from '../service/AudioScanner'
import { LrcApiConfigService, LrcApiSettings } from '../service/LrcApiConfigService'
import { LrcApiCoverResult, LrcApiService } from '../service/LrcApiService'
import { PlayControls } from './PlayControls'
import { LyricView } from './LyricView'
import { LyricLine } from '../service/LyricParser'

interface CoverThemeRgb {
  red: number
  green: number
  blue: number
}

interface CoverPageTheme {
  baseColor: string
  topColor: string
  middleColor: string
  bottomColor: string
  veilColor: string
  glowColor: string
  glowAccentColor: string
  primaryColor: string
  secondaryColor: string
  tertiaryColor: string
  progressTrackColor: string
  shadowColor: string
}

const CoverPageThemeCache: Map<string, CoverPageTheme> = new Map<string, CoverPageTheme>()

@Component
export struct NowPlayingView {
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('currentIndex') currentIndex: number = -1
  @StorageLink('currentPosition') @Watch('onPositionChange') currentPosition: number = 0
  @StorageLink('totalDuration') @Watch('onDurationChange') totalDuration: number = 0
  @StorageLink('currentTitle') currentTitle: string = ''
  @StorageLink('currentArtist') currentArtist: string = ''
  @StorageLink('coverVersion') @Watch('syncCover') coverVersion: number = 0
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenHeightVp') screenHeightVp: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink('isDarkMode') isDarkMode: boolean = false
  @StorageLink('dominantColor') dominantColor: string = Colors.DEFAULT_DOMINANT_COLOR
  @StorageLink('lyricLines') lyricLines: LyricLine[] = []
  @StorageLink('lyricIndex') lyricIndex: number = -1
  @StorageLink('favoriteIds') favoriteIdsStr: string = '[]'
  @StorageLink('modalOverlayActive') modalOverlayActive: boolean = false
  @StorageLink('immersiveModeActive') immersiveModeActive: boolean = false
  @StorageLink('immersiveModeProgress') immersiveModeProgress: number = 0

  @Prop expandProgress: number = 1
  onClose?: () => void
  onSwipeUpdate?: (offsetY: number) => void
  onSwipeEnd?: (velocityY: number) => void
  onLyricsProgress?: (progress: number) => void

  private getContentOpacity(threshold: number): number {
    const p = this.expandProgress
    if (p < threshold) {
      return 0
    }
    return Math.min(1, (p - threshold) / (1 - threshold))
  }

  private getContentTranslateY(threshold: number, distance: number = 30): number {
    const p = this.expandProgress
    if (p < threshold) {
      return distance
    }
    return distance * (1 - Math.min(1, (p - threshold) / (1 - threshold)))
  }

  // 背景提前接管，避免 MiniPlayer shell 淡出前后出现透明空档。
  private getBgOpacity(): number {
    const p = Math.max(0, Math.min(1, this.expandProgress))
    if (p <= 0.20) {
      return 0
    }
    if (p >= 0.75) {
      return 1
    }
    return (p - 0.20) / 0.55
  }

  @State private coverPixelMap: image.PixelMap | null = null
  @State private coverBackdropBaseColor: string = '#F8FAFB'
  @State private coverBackdropTopColor: string = '#E8F1F2'
  @State private coverBackdropMiddleColor: string = '#EDF2F0'
  @State private coverBackdropBottomColor: string = '#D8E2E3'
  @State private coverBackdropVeilColor: string = 'rgba(255, 255, 255, 0.02)'
  @State private coverBackdropGlowColor: string = 'rgba(232, 241, 242, 1)'
  @State private coverBackdropAccentGlowColor: string = 'rgba(216, 226, 227, 1)'
  @State private coverPagePrimaryColor: string = '#202020'
  @State private coverPageSecondaryColor: string = 'rgba(32, 32, 32, 0.68)'
  @State private coverPageTertiaryColor: string = 'rgba(32, 32, 32, 0.46)'
  @State private coverPageProgressTrackColor: string = 'rgba(32, 32, 32, 0.18)'
  @State private coverPageShadowColor: string = 'rgba(0, 0, 0, 0.16)'
  @State private isSeeking: boolean = false
  @State private seekValue: number = 0
  @State private progressPercent: number = 0
  @State private isMoreSheetVisible: boolean = false
  @State private isOnlineSearchPopupVisible: boolean = false
  @State private isDetailDialogVisible: boolean = false
  @State private isApiSettingsDialogVisible: boolean = false
  @State private isDeleteDialogVisible: boolean = false
  @State private activeOnlineSearchItem: string = ''
  @State private moreSheetProgress: number = 0
  @State private onlineSearchPopupProgress: number = 0
  @State private detailDialogProgress: number = 0
  @State private apiSettingsDialogProgress: number = 0
  @State private deleteDialogProgress: number = 0
  @State private isDeletingSong: boolean = false
  @State private lyricApiUrl: string = ''
  @State private lyricApiKey: string = ''
  @State private coverApiUrl: string = ''
  @State private coverApiKey: string = ''
  @State private draftLyricApiUrl: string = ''
  @State private draftLyricApiKey: string = ''
  @State private draftCoverApiUrl: string = ''
  @State private draftCoverApiKey: string = ''
  @State private fetchStatus: string = 'idle'
  @State private fetchMessage: string = ''
  @State private pendingOnlineSearchItem: string = ''
  @State private coverLyricPageIndex: number = 0
  private coverLyricSwiperController: SwiperController = new SwiperController()
  private isComponentReady: boolean = false
  private readonly lrcApiConfigService: LrcApiConfigService = LrcApiConfigService.getInstance()
  private readonly playlistManager: PlaylistManager = PlaylistManager.getInstance()
  private readonly controlsFloatingOffset: number = 36
  private readonly overlayCoverPageMaxSize: number = 520
  private readonly overlayCoverPageMinSize: number = 180
  private readonly overlayCoverPageWidthRatio: number = 0.845
  private readonly overlayImmersiveCoverPageWidthRatio: number = 0.845
  private readonly overlayImmersiveCoverTopShiftRatio: number = 0.12
  private readonly overlayCoverPageHorizontalPadding: number = 48
  private readonly overlayCoverPageTopOffset: number = 174
  private readonly overlayAudioHeight: number = 82
  private readonly overlayProgressHeight: number = 44
  private readonly overlayControlsBaseHeight: number = 176
  private readonly overlayProgressControlsGap: number = 15
  private readonly overlayHeaderTopOffset: number = 8
  private readonly overlayTitleLineHeight: number = 32
  private readonly overlayArtistLineHeight: number = 20
  private readonly overlayTextGap: number = 4
  private readonly overlayTitleFont: number = 24
  private readonly overlayArtistFont: number = 13
  private readonly progressTimeLabelWidth: number = 38
  private readonly progressInlineGap: number = 10
  private readonly coverPageIndex: number = 0
  private readonly lyricsPageIndex: number = 1
  private readonly moreSheetAnimationDuration: number = 300
  private readonly onlineSearchAnimationDuration: number = 250
  private readonly detailDialogAnimationDuration: number = 220
  private readonly apiSettingsDialogAnimationDuration: number = 220
  private readonly deleteDialogAnimationDuration: number = 220
  private readonly immersiveModeAnimationDuration: number = 260
  @State private sheetDragOffsetY: number = 0
  private sheetStartY: number = 0
  private moreSheetHideTask: number = -1
  private onlineSearchPopupHideTask: number = -1
  private detailDialogHideTask: number = -1
  private apiSettingsDialogHideTask: number = -1
  private deleteDialogHideTask: number = -1
  private immersiveModeHideTask: number = -1
  private coverThemeTaskToken: number = 0

  aboutToAppear(): void {
    this.setSharedMorphHidden(false)
    this.setModalOverlayActive(false)
    this.setImmersiveModeState(false, 0)
    this.coverLyricPageIndex = this.coverPageIndex
    this.emitLyricsProgress(0)
    this.syncCover()
    this.updateProgressPercent()
    void this.loadApiSettings()
    this.isComponentReady = true
  }

  aboutToDisappear(): void {
    this.clearImmersiveModeHideTask()
    this.setImmersiveModeState(false, 0)
  }

  private setSharedMorphHidden(hidden: boolean): void {
    AppStorage.setOrCreate(StorageKeys.DETAIL_DIALOG_VISIBLE, hidden)
  }

  private setModalOverlayActive(active: boolean): void {
    AppStorage.setOrCreate(StorageKeys.MODAL_OVERLAY_ACTIVE, active)
  }

  private setImmersiveModeState(active: boolean, progress: number): void {
    AppStorage.setOrCreate(StorageKeys.IMMERSIVE_MODE_ACTIVE, active)
    AppStorage.setOrCreate(StorageKeys.IMMERSIVE_MODE_PROGRESS, Math.max(0, Math.min(1, progress)))
  }

  private restoreModalOverlayWhenIdle(): void {
    if (!this.isMoreSheetVisible && !this.isOnlineSearchPopupVisible && !this.isDetailDialogVisible &&
      !this.isApiSettingsDialogVisible && !this.isDeleteDialogVisible) {
      this.setModalOverlayActive(false)
    }
  }

  private emitLyricsProgress(progress: number): void {
    if (this.onLyricsProgress) {
      this.onLyricsProgress(Math.max(0, Math.min(1, progress)))
    }
  }

  private syncCover(): void {
    const pixelMap = GlobalContext.getInstance().get(GCKeys.CURRENT_COVER)
    this.coverPixelMap = pixelMap ? pixelMap as image.PixelMap : null
    this.coverThemeTaskToken += 1
    void this.updateCoverPageTheme(this.coverPixelMap, this.coverThemeTaskToken)
  }

  private async updateCoverPageTheme(pixelMap: image.PixelMap | null, taskToken: number): Promise<void> {
    if (!pixelMap) {
      this.applyCoverPageTheme(this.getFallbackCoverPageTheme())
      return
    }

    const cacheKey: string = this.getCoverThemeCacheKey()
    const cachedTheme = CoverPageThemeCache.get(cacheKey)
    if (cachedTheme) {
      this.applyCoverPageTheme(cachedTheme)
      return
    }

    let themePixelMap: image.PixelMap | null = null
    let shouldReleaseThemePixelMap: boolean = false
    try {
      const sampledPixelMap = await this.createThemePixelMap(pixelMap)
      themePixelMap = sampledPixelMap
      shouldReleaseThemePixelMap = sampledPixelMap !== pixelMap

      const colorPicker = await effectKit.createColorPicker(sampledPixelMap)
      if (taskToken !== this.coverThemeTaskToken) {
        return
      }

      const mainColor = colorPicker.getMainColorSync() as CoverThemeRgb
      const averageColor = colorPicker.getAverageColor() as CoverThemeRgb
      const saturationColor = colorPicker.getHighestSaturationColor() as CoverThemeRgb
      const edgeColor = await this.getEdgeAverageColor(sampledPixelMap)
      if (taskToken !== this.coverThemeTaskToken) {
        return
      }

      const safeMainColor = this.isUsableThemeColor(mainColor) ? mainColor : this.hexToRgb(Colors.DEFAULT_DOMINANT_COLOR)
      const safeAverageColor = this.isUsableThemeColor(averageColor) ? averageColor : safeMainColor
      const safeSaturationColor = this.isUsableThemeColor(saturationColor) ? saturationColor : safeMainColor
      const safeEdgeColor = this.isUsableThemeColor(edgeColor) ? edgeColor : safeAverageColor

      console.info('ThemeColor',
        `main=${this.colorToText(safeMainColor)} average=${this.colorToText(safeAverageColor)} ` +
          `edge=${this.colorToText(safeEdgeColor)} saturation=${this.colorToText(safeSaturationColor)}`)

      const theme = this.buildCoverPageTheme(safeMainColor, safeAverageColor, safeEdgeColor, safeSaturationColor)

      CoverPageThemeCache.set(cacheKey, theme)
      this.applyCoverPageTheme(theme)
    } catch (error) {
      console.error('NowPlayingView', `Cover theme extraction failed: ${JSON.stringify(error)}`)
      this.applyCoverPageTheme(this.getFallbackCoverPageTheme())
    } finally {
      if (shouldReleaseThemePixelMap && themePixelMap) {
        themePixelMap.release()
      }
    }
  }

  private getCoverThemeCacheKey(): string {
    const song = this.getCurrentSong()
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

  private applyCoverPageTheme(theme: CoverPageTheme): void {
    this.coverBackdropBaseColor = theme.baseColor
    this.coverBackdropTopColor = theme.topColor
    this.coverBackdropMiddleColor = theme.middleColor
    this.coverBackdropBottomColor = theme.bottomColor
    this.coverBackdropVeilColor = theme.veilColor
    this.coverBackdropGlowColor = theme.glowColor
    this.coverBackdropAccentGlowColor = theme.glowAccentColor
    this.coverPagePrimaryColor = theme.primaryColor
    this.coverPageSecondaryColor = theme.secondaryColor
    this.coverPageTertiaryColor = theme.tertiaryColor
    this.coverPageProgressTrackColor = theme.progressTrackColor
    this.coverPageShadowColor = theme.shadowColor
    AppStorage.setOrCreate(StorageKeys.COVER_THEME_PRIMARY_COLOR, theme.primaryColor)
    AppStorage.setOrCreate(StorageKeys.COVER_THEME_SECONDARY_COLOR, theme.secondaryColor)
  }

  private getFallbackCoverPageTheme(): CoverPageTheme {
    if (this.isDarkMode) {
      return {
        baseColor: '#080A0F',
        topColor: 'rgba(123, 127, 255, 0.85)',
        middleColor: 'rgba(88, 96, 156, 0.92)',
        bottomColor: 'rgba(58, 68, 110, 0.95)',
        veilColor: 'rgba(0, 0, 0, 0.06)',
        glowColor: 'rgba(123, 127, 255, 1)',
        glowAccentColor: 'rgba(88, 96, 156, 1)',
        primaryColor: '#FFFFFF',
        secondaryColor: 'rgba(255, 255, 255, 0.74)',
        tertiaryColor: 'rgba(255, 255, 255, 0.52)',
        progressTrackColor: 'rgba(255, 255, 255, 0.24)',
        shadowColor: 'rgba(0, 0, 0, 0.34)'
      }
    }

    return {
      baseColor: '#F8FAFB',
      topColor: '#E8F1F2',
      middleColor: '#EDF2F0',
      bottomColor: '#D8E2E3',
      veilColor: 'rgba(255, 255, 255, 0.02)',
      glowColor: 'rgba(220, 238, 240, 1)',
      glowAccentColor: 'rgba(238, 228, 214, 1)',
      primaryColor: '#202020',
      secondaryColor: 'rgba(32, 32, 32, 0.68)',
      tertiaryColor: 'rgba(32, 32, 32, 0.46)',
      progressTrackColor: 'rgba(32, 32, 32, 0.18)',
      shadowColor: 'rgba(0, 0, 0, 0.16)'
    }
  }

  private async createThemePixelMap(pixelMap: image.PixelMap): Promise<image.PixelMap> {
    const imageInfo = await pixelMap.getImageInfo()
    const width: number = Math.max(1, imageInfo.size.width)
    const height: number = Math.max(1, imageInfo.size.height)
    const maxSide: number = Math.max(width, height)
    const sampleSize: number = 96

    if (maxSide <= sampleSize) {
      return pixelMap
    }

    const scale: number = sampleSize / maxSide
    return await pixelMap.createScaledPixelMap(scale, scale)
  }

  private async getEdgeAverageColor(pixelMap: image.PixelMap): Promise<CoverThemeRgb> {
    const imageInfo = await pixelMap.getImageInfo()
    const width: number = Math.max(1, imageInfo.size.width)
    const height: number = Math.max(1, imageInfo.size.height)
    const buffer = new ArrayBuffer(width * height * 4)
    await pixelMap.readPixelsToBuffer(buffer)

    const data = new Uint8Array(buffer)
    const edgeSize: number = Math.max(1, Math.floor(Math.min(width, height) * 0.12))
    let redTotal: number = 0
    let greenTotal: number = 0
    let blueTotal: number = 0
    let count: number = 0

    for (let y = 0; y < height; y += 2) {
      for (let x = 0; x < width; x += 2) {
        const isEdge: boolean = x < edgeSize || x >= width - edgeSize || y < edgeSize || y >= height - edgeSize
        if (!isEdge) {
          continue
        }

        const index: number = (y * width + x) * 4
        if (index + 2 >= data.length) {
          continue
        }

        redTotal += data[index]
        greenTotal += data[index + 1]
        blueTotal += data[index + 2]
        count += 1
      }
    }

    if (count === 0) {
      return { red: 238, green: 238, blue: 238 }
    }

    return {
      red: Math.round(redTotal / count),
      green: Math.round(greenTotal / count),
      blue: Math.round(blueTotal / count)
    }
  }

  private buildCoverPageTheme(
    mainColor: CoverThemeRgb,
    averageColor: CoverThemeRgb,
    edgeColor: CoverThemeRgb,
    saturationColor: CoverThemeRgb
  ): CoverPageTheme {
    const rawSeedColor = this.selectSafeSeedColor(mainColor, averageColor, edgeColor, saturationColor)
    const seedColor = this.normalizeSeedColor(rawSeedColor, edgeColor)
    const mixedColor = this.mixColor(seedColor, edgeColor, 0.42)
    const seedLuminance: number = this.getLuminance(seedColor)
    const isDarkTheme: boolean = seedLuminance < 115

    const bgTop = isDarkTheme
      ? this.toDarkBackground(seedColor, 0.22, 0.82)
      : this.ensureColorfulEnough(this.toPastelBackground(seedColor, 0.16, 1), seedColor)
    const bgMiddle = isDarkTheme
      ? this.toDarkBackground(edgeColor, 0.28, 0.76)
      : this.ensureColorfulEnough(this.toPastelBackground(edgeColor, 0.10, 1), edgeColor)
    const bgBottom = isDarkTheme
      ? this.toDarkBackground(mixedColor, 0.34, 0.72)
      : this.ensureColorfulEnough(this.toPastelBackground(mixedColor, 0.20, 0.92), seedColor)
    const isLightBackground: boolean = this.getLuminance(bgMiddle) > 150
    const glowSeed = this.toGlowColor(seedColor, isLightBackground)
    const glowAccent = this.toGlowColor(edgeColor, isLightBackground)

    const theme: CoverPageTheme = {
      baseColor: isLightBackground ? '#F8FAFB' : '#080A0F',
      topColor: this.toRgba(bgTop, 1),
      middleColor: this.toRgba(bgMiddle, 1),
      bottomColor: this.toRgba(bgBottom, 1),
      veilColor: isLightBackground ? 'rgba(255, 255, 255, 0.02)' : 'rgba(0, 0, 0, 0.06)',
      glowColor: this.toRgba(glowSeed, 1),
      glowAccentColor: this.toRgba(glowAccent, 1),
      primaryColor: isLightBackground ? '#202020' : '#FFFFFF',
      secondaryColor: isLightBackground ? 'rgba(32, 32, 32, 0.68)' : 'rgba(255, 255, 255, 0.74)',
      tertiaryColor: isLightBackground ? 'rgba(32, 32, 32, 0.46)' : 'rgba(255, 255, 255, 0.52)',
      progressTrackColor: isLightBackground ? 'rgba(32, 32, 32, 0.18)' : 'rgba(255, 255, 255, 0.24)',
      shadowColor: isLightBackground ? this.toRgba(seedColor, 0.20) : 'rgba(0, 0, 0, 0.34)'
    }

    console.info('ThemeColor',
      `seed=${this.colorToText(seedColor)} top=${theme.topColor} middle=${theme.middleColor} bottom=${theme.bottomColor}`)

    return theme
  }

  private selectSafeSeedColor(
    mainColor: CoverThemeRgb,
    averageColor: CoverThemeRgb,
    edgeColor: CoverThemeRgb,
    saturationColor: CoverThemeRgb
  ): CoverThemeRgb {
    const candidates: CoverThemeRgb[] = [
      edgeColor,
      mainColor,
      averageColor,
      this.mixColor(mainColor, edgeColor, 0.35),
      this.mixColor(averageColor, edgeColor, 0.45)
    ]

    if (this.isUsableAccentColor(saturationColor)) {
      candidates.push(saturationColor)
      candidates.push(this.mixColor(saturationColor, edgeColor, 0.35))
    }

    let bestColor: CoverThemeRgb = candidates[0]
    let bestScore: number = -999999

    for (let i = 0; i < candidates.length; i += 1) {
      const item = candidates[i]
      const score = this.scoreColorForUi(item, edgeColor)
      if (score > bestScore) {
        bestColor = item
        bestScore = score
      }
    }

    return bestColor
  }

  private isUsableAccentColor(color: CoverThemeRgb): boolean {
    const luminance: number = this.getLuminance(color)
    const colorfulness: number = this.getColorfulness(color)

    if (luminance < 70 || luminance > 235) {
      return false
    }

    if (colorfulness < 18 || colorfulness > 170) {
      return false
    }

    const isDirtyOlive: boolean = color.red < 130 && color.green < 155 && color.blue < 90 &&
      color.green >= color.blue && color.red >= color.blue
    return !isDirtyOlive
  }

  private scoreColorForUi(color: CoverThemeRgb, edgeColor: CoverThemeRgb): number {
    const luminance: number = this.getLuminance(color)
    const colorfulness: number = this.getColorfulness(color)
    const edgeDistance: number = this.colorDistance(color, edgeColor)
    let score: number = 100

    if (luminance < 45) {
      score -= 40
    }
    if (luminance > 238) {
      score -= 30
    }
    if (colorfulness < 10) {
      score -= 25
    }
    if (colorfulness > 150) {
      score -= 35
    }
    if (this.isSkinLikeColor(color) && edgeDistance > 35) {
      score -= 45
    }

    score += Math.max(0, 40 - edgeDistance * 0.4)
    return score
  }

  private normalizeSeedColor(seedColor: CoverThemeRgb, edgeColor: CoverThemeRgb): CoverThemeRgb {
    let color = seedColor
    color = this.fixSkinToneCast(color, edgeColor)
    color = this.fixOverSaturatedColor(color)
    color = this.fixTooDarkColor(color)
    color = this.fixTooLightNeutralColor(color, edgeColor)
    return color
  }

  private fixSkinToneCast(color: CoverThemeRgb, edgeColor: CoverThemeRgb): CoverThemeRgb {
    if (!this.isSkinLikeColor(color)) {
      return color
    }

    const edgeLooksPinkOrCool: boolean = edgeColor.red >= edgeColor.green && edgeColor.blue >= edgeColor.green - 12
    if (!edgeLooksPinkOrCool) {
      return this.toSoftWarmColor(color)
    }

    return {
      red: this.clampColor(color.red - 8),
      green: this.clampColor(color.green + 12),
      blue: this.clampColor(color.blue + 38)
    }
  }

  private toSoftWarmColor(color: CoverThemeRgb): CoverThemeRgb {
    return {
      red: this.clampColor(color.red),
      green: this.clampColor(color.green + 8),
      blue: this.clampColor(color.blue + 18)
    }
  }

  private fixOverSaturatedColor(color: CoverThemeRgb): CoverThemeRgb {
    const saturationLike: number = this.getColorfulness(color)
    if (saturationLike < 90) {
      return color
    }

    const gray: number = this.getLuminance(color)
    return {
      red: this.clampColor(gray + (color.red - gray) * 0.55),
      green: this.clampColor(gray + (color.green - gray) * 0.55),
      blue: this.clampColor(gray + (color.blue - gray) * 0.55)
    }
  }

  private fixTooDarkColor(color: CoverThemeRgb): CoverThemeRgb {
    if (this.getLuminance(color) >= 80) {
      return color
    }

    return {
      red: this.clampColor(color.red + 55),
      green: this.clampColor(color.green + 55),
      blue: this.clampColor(color.blue + 55)
    }
  }

  private fixTooLightNeutralColor(color: CoverThemeRgb, edgeColor: CoverThemeRgb): CoverThemeRgb {
    const isNeutral: boolean = this.getColorfulness(color) < 16
    if (!isNeutral) {
      return color
    }

    if (this.getColorfulness(edgeColor) > 20) {
      return this.mixColor(color, edgeColor, 0.45)
    }

    if (this.getLuminance(color) > 180) {
      return { red: 226, green: 236, blue: 240 }
    }

    return { red: 72, green: 84, blue: 92 }
  }

  private toPastelBackground(
    color: CoverThemeRgb,
    whiteRatio: number,
    saturationRatio: number
  ): CoverThemeRgb {
    const gray: number = this.getLuminance(color)
    const preserved: CoverThemeRgb = {
      red: this.clampColor(gray + (color.red - gray) * saturationRatio),
      green: this.clampColor(gray + (color.green - gray) * saturationRatio),
      blue: this.clampColor(gray + (color.blue - gray) * saturationRatio)
    }

    return this.mixColor(preserved, { red: 255, green: 255, blue: 255 }, whiteRatio)
  }

  private toGlowColor(color: CoverThemeRgb, isLightBackground: boolean): CoverThemeRgb {
    const gray: number = this.getLuminance(color)
    const saturationRatio: number = isLightBackground ? 0.88 : 0.72
    const preserved: CoverThemeRgb = {
      red: this.clampColor(gray + (color.red - gray) * saturationRatio),
      green: this.clampColor(gray + (color.green - gray) * saturationRatio),
      blue: this.clampColor(gray + (color.blue - gray) * saturationRatio)
    }

    if (isLightBackground) {
      return this.mixColor(preserved, { red: 255, green: 255, blue: 255 }, 0.08)
    }

    return this.mixColor(preserved, { red: 32, green: 36, blue: 44 }, 0.18)
  }

  private toDarkBackground(
    color: CoverThemeRgb,
    darkRatio: number,
    saturationRatio: number
  ): CoverThemeRgb {
    const gray: number = this.getLuminance(color)
    const preserved: CoverThemeRgb = {
      red: this.clampColor(gray + (color.red - gray) * saturationRatio),
      green: this.clampColor(gray + (color.green - gray) * saturationRatio),
      blue: this.clampColor(gray + (color.blue - gray) * saturationRatio)
    }

    return this.mixColor(preserved, { red: 24, green: 28, blue: 34 }, darkRatio)
  }

  private ensureColorfulEnough(color: CoverThemeRgb, seedColor: CoverThemeRgb): CoverThemeRgb {
    const minColorfulness: number = 24

    if (this.getColorfulness(color) >= minColorfulness) {
      return color
    }

    const boostedColor = this.mixColor(color, seedColor, 0.46)
    if (this.getColorfulness(boostedColor) >= minColorfulness) {
      return boostedColor
    }

    return this.mixColor(color, seedColor, 0.68)
  }

  private mixColor(a: CoverThemeRgb, b: CoverThemeRgb, ratio: number): CoverThemeRgb {
    const safeRatio: number = Math.max(0, Math.min(1, ratio))
    return {
      red: this.clampColor(a.red * (1 - safeRatio) + b.red * safeRatio),
      green: this.clampColor(a.green * (1 - safeRatio) + b.green * safeRatio),
      blue: this.clampColor(a.blue * (1 - safeRatio) + b.blue * safeRatio)
    }
  }

  private getColorfulness(color: CoverThemeRgb): number {
    return Math.max(color.red, color.green, color.blue) - Math.min(color.red, color.green, color.blue)
  }

  private isSkinLikeColor(color: CoverThemeRgb): boolean {
    const red: number = color.red
    const green: number = color.green
    const blue: number = color.blue
    return red > 190 && green > 115 && blue > 75 && red > green && green > blue && red - blue > 45 &&
      green - blue > 18
  }

  private colorDistance(a: CoverThemeRgb, b: CoverThemeRgb): number {
    const redDiff: number = a.red - b.red
    const greenDiff: number = a.green - b.green
    const blueDiff: number = a.blue - b.blue
    return Math.sqrt(redDiff * redDiff + greenDiff * greenDiff + blueDiff * blueDiff)
  }

  private isUsableThemeColor(color: CoverThemeRgb | null | undefined): boolean {
    return !!color &&
      Number.isFinite(color.red) &&
      Number.isFinite(color.green) &&
      Number.isFinite(color.blue)
  }

  private getLuminance(color: CoverThemeRgb): number {
    return 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
  }

  private toRgba(color: CoverThemeRgb, alpha: number): string {
    const normalizedAlpha: number = Math.max(0, Math.min(1, alpha))
    return `rgba(${this.clampColor(color.red)}, ${this.clampColor(color.green)}, ${this.clampColor(color.blue)}, ${normalizedAlpha})`
  }

  private colorToText(color: CoverThemeRgb): string {
    return `rgb(${this.clampColor(color.red)}, ${this.clampColor(color.green)}, ${this.clampColor(color.blue)})`
  }

  private hexToRgb(color: string): CoverThemeRgb {
    let hex: string = color.replace('#', '').trim()
    if (hex.length === 3) {
      hex = hex.split('').map((item: string) => `${item}${item}`).join('')
    }
    if (hex.length !== 6) {
      return { red: 123, green: 127, blue: 255 }
    }

    return {
      red: Number.parseInt(hex.substring(0, 2), 16),
      green: Number.parseInt(hex.substring(2, 4), 16),
      blue: Number.parseInt(hex.substring(4, 6), 16)
    }
  }

  private clampColor(value: number): number {
    return Math.max(0, Math.min(255, Math.round(value)))
  }

  private onPositionChange(): void {
    this.updateProgressPercent()
  }

  private onDurationChange(): void {
    this.updateProgressPercent()
  }

  private updateProgressPercent(): void {
    if (this.isSeeking) {
      return
    }
    this.progressPercent = this.totalDuration <= 0 ? 0 : (this.currentPosition / this.totalDuration) * 100
  }

  private closePage(): void {
    this.setImmersiveModeState(false, 0)
    this.closeMoreSheet()
    if (this.onClose) {
      this.onClose()
    }
  }

  private toggleMoreSheet(): void {
    if (this.isMoreSheetVisible) {
      this.closeMoreSheet()
      return
    }

    this.openMoreSheet()
  }

  private clearMoreSheetHideTask(): void {
    if (this.moreSheetHideTask >= 0) {
      clearTimeout(this.moreSheetHideTask)
      this.moreSheetHideTask = -1
    }
  }

  private clearOnlineSearchPopupHideTask(): void {
    if (this.onlineSearchPopupHideTask >= 0) {
      clearTimeout(this.onlineSearchPopupHideTask)
      this.onlineSearchPopupHideTask = -1
    }
  }

  private clearDetailDialogHideTask(): void {
    if (this.detailDialogHideTask >= 0) {
      clearTimeout(this.detailDialogHideTask)
      this.detailDialogHideTask = -1
    }
  }

  private clearApiSettingsDialogHideTask(): void {
    if (this.apiSettingsDialogHideTask >= 0) {
      clearTimeout(this.apiSettingsDialogHideTask)
      this.apiSettingsDialogHideTask = -1
    }
  }

  private clearDeleteDialogHideTask(): void {
    if (this.deleteDialogHideTask >= 0) {
      clearTimeout(this.deleteDialogHideTask)
      this.deleteDialogHideTask = -1
    }
  }

  private clearImmersiveModeHideTask(): void {
    if (this.immersiveModeHideTask >= 0) {
      clearTimeout(this.immersiveModeHideTask)
      this.immersiveModeHideTask = -1
    }
  }

  private openMoreSheet(): void {
    this.clearMoreSheetHideTask()
    this.clearOnlineSearchPopupHideTask()
    this.clearDetailDialogHideTask()
    this.clearApiSettingsDialogHideTask()
    this.clearDeleteDialogHideTask()
    this.setModalOverlayActive(true)
    this.isMoreSheetVisible = true
    this.moreSheetProgress = 0
    this.sheetDragOffsetY = 0
    animateTo({
      duration: this.moreSheetAnimationDuration,
      curve: Curve.EaseOut
    }, () => {
      this.moreSheetProgress = 1
    })
  }

  private closeMoreSheet(): void {
    if (!this.isMoreSheetVisible) {
      return
    }

    this.clearMoreSheetHideTask()
    this.clearOnlineSearchPopupHideTask()
    this.clearDetailDialogHideTask()
    this.clearApiSettingsDialogHideTask()
    this.clearDeleteDialogHideTask()
    animateTo({
      duration: this.moreSheetAnimationDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.moreSheetProgress = 0
      this.onlineSearchPopupProgress = 0
      this.detailDialogProgress = 0
      this.apiSettingsDialogProgress = 0
      this.deleteDialogProgress = 0
    })
    this.moreSheetHideTask = setTimeout(() => {
      this.isMoreSheetVisible = false
      this.isOnlineSearchPopupVisible = false
      this.isDetailDialogVisible = false
      this.setSharedMorphHidden(false)
      this.setModalOverlayActive(false)
      this.isApiSettingsDialogVisible = false
      this.isDeleteDialogVisible = false
      this.isDeletingSong = false
      this.activeOnlineSearchItem = ''
      this.moreSheetHideTask = -1
    }, this.moreSheetAnimationDuration) as number
  }

  private getImmersiveProgress(): number {
    return Math.max(0, Math.min(1, this.immersiveModeProgress))
  }

  private getImmersiveHiddenOpacity(): number {
    return 1 - this.getImmersiveProgress()
  }

  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t
  }

  private getImmersiveControlsTranslateY(): number {
    const progress = this.getImmersiveProgress()
    if (progress <= 0) {
      return 0
    }

    const coverBottom = this.getOverlayCoverTargetTop() + this.getOverlayCoverTargetSize()
    const bottomLimit = this.getOverlayScreenHeight() - this.bottomSafeHeight
    if (bottomLimit <= coverBottom) {
      return 0
    }

    const desiredCenterY = coverBottom + (bottomLimit - coverBottom) * 0.62
    const currentControlOffset = this.lerp(52, 45, progress)
    const currentCenterY = this.getOverlayScreenHeight() - this.bottomSafeHeight -
      this.controlsFloatingOffset - currentControlOffset
    return (desiredCenterY - currentCenterY) * progress
  }

  private isImmersiveModeShowing(): boolean {
    return this.immersiveModeActive || this.getImmersiveProgress() > 0.01
  }

  private enterImmersiveMode(): void {
    if (this.isImmersiveModeShowing()) {
      this.closeMoreSheet()
      return
    }

    this.clearImmersiveModeHideTask()
    this.coverLyricPageIndex = this.coverPageIndex
    this.emitLyricsProgress(0)
    this.closeMoreSheet()
    this.setImmersiveModeState(true, 0)
    try {
      promptAction.showToast({
        message: '点按歌曲封面即可退出沉浸模式',
        duration: 2200
      })
    } catch (_) {
    }
    animateTo({
      duration: this.immersiveModeAnimationDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.immersiveModeProgress = 1
    })
  }

  private exitImmersiveMode(): void {
    if (!this.isImmersiveModeShowing()) {
      return
    }

    this.clearImmersiveModeHideTask()
    animateTo({
      duration: this.immersiveModeAnimationDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.immersiveModeProgress = 0
    })
    this.immersiveModeHideTask = setTimeout(() => {
      this.setImmersiveModeState(false, 0)
      this.immersiveModeHideTask = -1
    }, this.immersiveModeAnimationDuration) as number
  }

  private toggleOnlineSearchPopup(): void {
    if (this.isOnlineSearchPopupVisible) {
      this.closeOnlineSearchPopup()
      return
    }

    this.openOnlineSearchPopup()
  }

  private openOnlineSearchPopup(): void {
    this.clearOnlineSearchPopupHideTask()
    this.setModalOverlayActive(true)
    this.isOnlineSearchPopupVisible = true
    this.onlineSearchPopupProgress = 0
    animateTo({
      duration: this.onlineSearchAnimationDuration,
      curve: Curve.EaseOut
    }, () => {
      this.onlineSearchPopupProgress = 1
    })
  }

  private closeOnlineSearchPopup(): void {
    if (!this.isOnlineSearchPopupVisible) {
      return
    }

    this.clearOnlineSearchPopupHideTask()
    animateTo({
      duration: this.onlineSearchAnimationDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.onlineSearchPopupProgress = 0
    })
    this.onlineSearchPopupHideTask = setTimeout(() => {
      this.isOnlineSearchPopupVisible = false
      this.restoreModalOverlayWhenIdle()
      this.activeOnlineSearchItem = ''
      this.onlineSearchPopupHideTask = -1
    }, this.onlineSearchAnimationDuration) as number
  }

  private openDetailDialog(): void {
    this.hideOnlineSearchPopupImmediately()
    this.clearDetailDialogHideTask()
    this.setModalOverlayActive(true)
    this.isDetailDialogVisible = true
    this.detailDialogProgress = 0
    animateTo({
      duration: this.detailDialogAnimationDuration,
      curve: Curve.EaseOut
    }, () => {
      this.detailDialogProgress = 1
    })
  }

  private closeDetailDialog(): void {
    if (!this.isDetailDialogVisible) {
      return
    }

    this.clearDetailDialogHideTask()
    animateTo({
      duration: this.detailDialogAnimationDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.detailDialogProgress = 0
    })
    this.detailDialogHideTask = setTimeout(() => {
      this.isDetailDialogVisible = false
      this.restoreModalOverlayWhenIdle()
      this.detailDialogHideTask = -1
    }, this.detailDialogAnimationDuration) as number
  }

  private openDeleteDialog(): void {
    this.hideOnlineSearchPopupImmediately()
    this.clearDeleteDialogHideTask()
    this.setModalOverlayActive(true)
    this.isDeleteDialogVisible = true
    this.deleteDialogProgress = 0
    animateTo({
      duration: this.deleteDialogAnimationDuration,
      curve: Curve.EaseOut
    }, () => {
      this.deleteDialogProgress = 1
    })
  }

  private closeDeleteDialog(): void {
    if (!this.isDeleteDialogVisible) {
      return
    }

    this.clearDeleteDialogHideTask()
    animateTo({
      duration: this.deleteDialogAnimationDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.deleteDialogProgress = 0
    })
    this.deleteDialogHideTask = setTimeout(() => {
      this.isDeleteDialogVisible = false
      this.restoreModalOverlayWhenIdle()
      this.isDeletingSong = false
      this.deleteDialogHideTask = -1
    }, this.deleteDialogAnimationDuration) as number
  }

  private hideOnlineSearchPopupImmediately(): void {
    this.clearOnlineSearchPopupHideTask()
    this.isOnlineSearchPopupVisible = false
    this.onlineSearchPopupProgress = 0
    this.activeOnlineSearchItem = ''
  }

  private async loadApiSettings(): Promise<void> {
    const settings = await this.lrcApiConfigService.loadSettings()
    this.applyApiSettings(settings)
  }

  private applyApiSettings(settings: LrcApiSettings): void {
    this.lyricApiUrl = settings.lyricsApiUrl
    this.lyricApiKey = settings.lyricsApiKey
    this.coverApiUrl = settings.coverApiUrl
    this.coverApiKey = settings.coverApiKey
  }

  private openApiSettingsDialog(): void {
    this.hideOnlineSearchPopupImmediately()
    this.clearApiSettingsDialogHideTask()
    this.setModalOverlayActive(true)
    const currentSettings = new LrcApiSettings(
      this.lyricApiUrl.length > 0 ? this.lyricApiUrl : this.lrcApiConfigService.getDefaultSettings().lyricsApiUrl,
      this.lyricApiKey,
      this.coverApiUrl.length > 0 ? this.coverApiUrl : this.lrcApiConfigService.getDefaultSettings().coverApiUrl,
      this.coverApiKey
    )
    this.draftLyricApiUrl = currentSettings.lyricsApiUrl
    this.draftLyricApiKey = currentSettings.lyricsApiKey
    this.draftCoverApiUrl = currentSettings.coverApiUrl
    this.draftCoverApiKey = currentSettings.coverApiKey
    this.isApiSettingsDialogVisible = true
    this.apiSettingsDialogProgress = 0
    animateTo({
      duration: this.apiSettingsDialogAnimationDuration,
      curve: Curve.EaseOut
    }, () => {
      this.apiSettingsDialogProgress = 1
    })
  }

  private closeApiSettingsDialog(commit: boolean): void {
    if (!this.isApiSettingsDialogVisible) {
      return
    }

    if (commit) {
      this.lyricApiUrl = this.draftLyricApiUrl
      this.lyricApiKey = this.draftLyricApiKey
      this.coverApiUrl = this.draftCoverApiUrl
      this.coverApiKey = this.draftCoverApiKey
      void this.persistApiSettings()
    }

    this.clearApiSettingsDialogHideTask()
    animateTo({
      duration: this.apiSettingsDialogAnimationDuration,
      curve: Curve.EaseInOut
    }, () => {
      this.apiSettingsDialogProgress = 0
    })
    this.apiSettingsDialogHideTask = setTimeout(() => {
      this.isApiSettingsDialogVisible = false
      this.restoreModalOverlayWhenIdle()
      if (commit) {
        this.retryPendingOnlineSearch()
      } else {
        this.pendingOnlineSearchItem = ''
      }
      this.apiSettingsDialogHideTask = -1
    }, this.apiSettingsDialogAnimationDuration) as number
  }

  private async persistApiSettings(): Promise<void> {
    await this.lrcApiConfigService.saveSettings(new LrcApiSettings(
      this.lyricApiUrl,
      this.lyricApiKey,
      this.coverApiUrl,
      this.coverApiKey
    ))
  }

  private retryPendingOnlineSearch(): void {
    if (this.pendingOnlineSearchItem.length === 0) {
      return
    }

    const itemId = this.pendingOnlineSearchItem
    this.pendingOnlineSearchItem = ''
    this.handleSubMenuAction(itemId)
  }

  private getApiSettingsDialogScale(): number {
    return 0.92 + this.apiSettingsDialogProgress * 0.08
  }

  private getApiSettingsDialogTranslateY(): number {
    return (1 - this.apiSettingsDialogProgress) * 18
  }

  private updateApiDraftField(fieldId: string, value: string): void {
    if (fieldId === 'lyrics_api') {
      this.draftLyricApiUrl = value
      return
    }
    if (fieldId === 'lyrics_key') {
      this.draftLyricApiKey = value
      return
    }
    if (fieldId === 'cover_api') {
      this.draftCoverApiUrl = value
      return
    }
    this.draftCoverApiKey = value
  }

  private withAlpha(color: string, alpha: number): string {
    const normalizedAlpha: number = Math.max(0, Math.min(1, alpha))
    const rgbaMatch: RegExpMatchArray | null = color.match(/rgba?\(([^)]+)\)/)
    if (rgbaMatch && rgbaMatch[1]) {
      const channels: string[] = rgbaMatch[1].split(',').map((item: string) => item.trim())
      if (channels.length >= 3) {
        return `rgba(${channels[0]}, ${channels[1]}, ${channels[2]}, ${normalizedAlpha})`
      }
    }

    let hex: string = color.replace('#', '').trim()
    if (hex.length === 3) {
      hex = hex.split('').map((item: string) => `${item}${item}`).join('')
    } else if (hex.length === 8) {
      hex = hex.substring(2)
    }

    if (hex.length === 6) {
      const red: number = Number.parseInt(hex.substring(0, 2), 16)
      const green: number = Number.parseInt(hex.substring(2, 4), 16)
      const blue: number = Number.parseInt(hex.substring(4, 6), 16)
      return `rgba(${red}, ${green}, ${blue}, ${normalizedAlpha})`
    }

    return `rgba(123, 127, 255, ${normalizedAlpha})`
  }

  private getCurrentSong() {
    return PlayerService.getInstance().getCurrentSong()
  }

  private getAudioFormatLabel(): string {
    const song = this.getCurrentSong()
    if (!song) {
      return 'AUDIO'
    }

    const codecMimeType = song.codecMimeType.toLowerCase()
    if (codecMimeType.startsWith('audio/')) {
      return codecMimeType.substring('audio/'.length).toUpperCase()
    }

    const mimeType = song.mimeType.toLowerCase()
    if (mimeType.startsWith('audio/')) {
      const formatLabel = mimeType.substring('audio/'.length)
      if (formatLabel === 'mpeg') {
        return 'MPEG'
      }
      return formatLabel.toUpperCase()
    }

    const fileName: string = song.uri.split('?')[0]
    const extension: string = fileName.includes('.')
      ? (fileName.split('.').pop() ?? '')
      : ''

    switch (extension.toLowerCase()) {
      case 'mp3':
        return 'MPEG'
      case 'm4a':
        return 'M4A'
      case 'flac':
        return 'FLAC'
      case 'wav':
        return 'WAV'
      case 'aac':
        return 'AAC'
      case 'ogg':
        return 'OGG'
      default:
        return extension.length > 0 ? extension.toUpperCase() : 'AUDIO'
    }
  }

  private getSampleRateLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.sampleRate <= 0) {
      return ''
    }

    const kiloHertz = song.sampleRate / 1000
    const hasFraction = song.sampleRate % 1000 !== 0
    return `${hasFraction ? kiloHertz.toFixed(1) : kiloHertz.toFixed(0)} kHz`
  }

  private getBitrateLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.bitrate <= 0) {
      return ''
    }

    const kiloBits = song.bitrate / 1000
    return `${kiloBits.toFixed(0)} kbps`
  }

  private getAudioTags(): string[] {
    const tags: string[] = [this.getAudioFormatLabel()]
    const sampleRateLabel = this.getSampleRateLabel()
    const bitrateLabel = this.getBitrateLabel()

    if (sampleRateLabel.length > 0) {
      tags.push(sampleRateLabel)
    }
    if (bitrateLabel.length > 0) {
      tags.push(bitrateLabel)
    }

    return tags
  }

  private getSongFileName(): string {
    const song = this.getCurrentSong()
    if (!song) {
      return 'Unknown'
    }

    const pathWithoutQuery = song.uri.split('?')[0]
    let fileName = pathWithoutQuery.split('/').pop() || pathWithoutQuery.split('\\').pop() || 'Unknown'
    try {
      fileName = decodeURIComponent(fileName)
    } catch (_) {
    }

    const managedNameMatch = fileName.match(/^[0-9a-f]{6,8}_+(.+)$/i)
    if (managedNameMatch && managedNameMatch[1]) {
      return managedNameMatch[1]
    }
    return fileName
  }

  private getSongFileSizeLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.uri.length === 0) {
      return 'Unknown'
    }

    try {
      const stat = fileIo.statSync(song.uri)
      return `${(stat.size / 1024 / 1024).toFixed(2)} MB`
    } catch (_) {
      return 'Unknown'
    }
  }

  private getSongAddedDateLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.uri.length === 0) {
      return 'Unknown'
    }

    try {
      const stat = fileIo.statSync(song.uri)
      const timestamp = stat.ctime > 0 ? stat.ctime : stat.mtime
      return this.formatDate(timestamp)
    } catch (_) {
      return 'Unknown'
    }
  }

  private formatDate(timestamp: number): string {
    if (timestamp <= 0) {
      return 'Unknown'
    }

    const normalizedTimestamp = timestamp < 1000000000000 ? timestamp * 1000 : timestamp
    const date = new Date(normalizedTimestamp)
    const month = date.getMonth() + 1
    const day = date.getDate()
    const monthText = month < 10 ? `0${month}` : `${month}`
    const dayText = day < 10 ? `0${day}` : `${day}`
    return `${date.getFullYear()}.${monthText}.${dayText}`
  }

  private getDetailDialogMaxHeight(): number {
    let screenHeight: number = 800
    if (this.screenHeightVp > 0) {
      screenHeight = this.screenHeightVp
    }
    return Math.max(520, screenHeight - this.topSafeHeight - this.bottomSafeHeight - 88)
  }

  private getDetailAlbumLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.album.length === 0) {
      return 'Unknown'
    }
    return song.album
  }

  private getDetailSampleRateLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.sampleRate <= 0) {
      return 'Unknown'
    }
    return `${song.sampleRate}Hz`
  }

  private getDetailBitrateLabel(): string {
    const song = this.getCurrentSong()
    if (!song || song.bitrate <= 0) {
      return 'Unknown'
    }
    return `${Math.round(song.bitrate / 1000)}kbps`
  }

  private getCoverShadowColor(): string {
    return this.coverPageShadowColor
  }

  private getMenuScrimColor(): string {
    return this.isDarkMode ? this.withAlpha('#000000', 0.30) : this.withAlpha('#0D1220', 0.14)
  }

  private getMenuShadowColor(): string {
    return this.isDarkMode ? this.withAlpha('#000000', 0.28) : this.withAlpha('#6C7899', 0.18)
  }

  private getBackdropBaseColor(): string {
    return this.coverBackdropBaseColor
  }

  private getSheetTranslateY(): number {
    const slideOffset: number = (1 - this.moreSheetProgress) * 400
    return slideOffset + this.sheetDragOffsetY
  }

  private getOverlayScreenWidth(): number {
    return this.screenWidthVp > 0 ? this.screenWidthVp : 360
  }

  private getOverlayScreenHeight(): number {
    return this.screenHeightVp > 0 ? this.screenHeightVp : 800
  }

  private getOverlayControlsReserveHeight(): number {
    return this.overlayControlsBaseHeight + this.bottomSafeHeight + this.controlsFloatingOffset
  }

  private getOverlayProgressReserveHeight(): number {
    return this.overlayControlsBaseHeight + this.bottomSafeHeight + this.overlayProgressControlsGap
  }

  private getOverlayCoverTopLimit(): number {
    return this.topSafeHeight + this.overlayCoverPageTopOffset
  }

  private getOverlayCoverSlotBottom(): number {
    return this.getProgressSectionTop() - this.overlayAudioHeight
  }

  private getOverlayCoverSize(): number {
    const screenW = this.getOverlayScreenWidth()
    const widthLimit = Math.min(
      screenW - this.overlayCoverPageHorizontalPadding,
      screenW * this.overlayCoverPageWidthRatio
    )
    const heightLimit = this.getOverlayCoverSlotBottom() - this.getOverlayCoverTopLimit()
    const targetSize = Math.min(this.overlayCoverPageMaxSize, widthLimit, heightLimit)
    const adaptiveMinSize = Math.min(this.overlayCoverPageMinSize, Math.max(120, heightLimit))
    return Math.max(adaptiveMinSize, targetSize)
  }

  private getOverlayCoverTop(): number {
    const topLimit = this.getOverlayCoverTopLimit()
    const coverSize = this.getOverlayCoverSize()
    const availableHeight = this.getOverlayCoverSlotBottom() - topLimit
    if (availableHeight <= coverSize) {
      return topLimit
    }
    return topLimit + (availableHeight - coverSize) / 2
  }

  private getOverlayImmersiveCoverSize(): number {
    const screenW = this.getOverlayScreenWidth()
    return Math.min(
      screenW - this.overlayCoverPageHorizontalPadding,
      screenW * this.overlayImmersiveCoverPageWidthRatio
    )
  }

  private getOverlayCoverTargetSize(): number {
    return this.lerp(this.getOverlayCoverSize(), this.getOverlayImmersiveCoverSize(), this.getImmersiveProgress())
  }

  private getOverlayCoverTargetTop(): number {
    const normalSize = this.getOverlayCoverSize()
    const targetSize = this.getOverlayCoverTargetSize()
    return this.getOverlayCoverTop() - (targetSize - normalSize) * this.overlayImmersiveCoverTopShiftRatio
  }

  private getOverlayCoverTargetLeft(): number {
    return (this.getOverlayScreenWidth() - this.getOverlayCoverTargetSize()) / 2
  }

  private getOverlayTitleTop(): number {
    const topLimit = this.topSafeHeight + this.overlayHeaderTopOffset
    const coverTop = this.getOverlayCoverTop()
    return this.topSafeHeight + ((coverTop - topLimit) - 68) / 2
  }

  private getOverlayArtistTop(): number {
    return this.getOverlayTitleTop() + this.getOverlayArtistOffset()
  }

  private getOverlayArtistOffset(): number {
    return this.overlayTitleLineHeight + this.overlayTextGap
  }

  private getOverlayCoverLeft(): number {
    return (this.getOverlayScreenWidth() - this.getOverlayCoverSize()) / 2
  }

  private getOverlayTitleWidth(): number {
    return Math.min(this.getOverlayScreenWidth() - 48, this.getOverlayCoverSize() + 28)
  }

  private getOverlayTitleLeft(): number {
    return (this.getOverlayScreenWidth() - this.getOverlayTitleWidth()) / 2
  }

  private getProgressTouchWidth(): number {
    const rowWidth = Math.max(1, this.getOverlayScreenWidth() - 48)
    return Math.max(1, rowWidth - this.progressTimeLabelWidth * 2 - this.progressInlineGap * 2)
  }

  private getProgressTouchLeft(): number {
    return 24 + this.progressTimeLabelWidth + this.progressInlineGap
  }

  private getProgressTouchTop(): number {
    return this.getProgressSectionTop()
  }

  private getProgressSectionTop(): number {
    return this.getOverlayScreenHeight() - this.getProgressBottomSpacerHeight() - this.overlayProgressHeight
  }

  private getProgressBottomSpacerHeight(): number {
    return this.getOverlayProgressReserveHeight()
  }

  private getCoverPageTopSpacerHeight(): number {
    return Math.max(0, this.getOverlayCoverTop() - (this.topSafeHeight + 2 + 48))
  }

  private shouldShowProgressHitLayer(): boolean {
    return this.expandProgress >= 0.96 && !this.isImmersiveModeShowing() && !this.isLyricsPageVisible() && !this.isMoreSheetVisible &&
      !this.isOnlineSearchPopupVisible && !this.isDetailDialogVisible && !this.isApiSettingsDialogVisible &&
      !this.isDeleteDialogVisible && this.currentIndex >= 0 && this.currentTitle.length > 0
  }

  private getPrimaryTouch(event: TouchEvent): TouchObject | null {
    if (event.touches.length > 0) {
      return event.touches[0]
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0]
    }
    return null
  }

  private getProgressPercentFromTouch(touch: TouchObject): number {
    const width: number = this.getProgressTouchWidth()
    return Math.max(0, Math.min(100, (touch.x / width) * 100))
  }

  private previewProgressSeek(percent: number): void {
    this.isSeeking = true
    this.seekValue = percent
    this.progressPercent = percent
  }

  private commitProgressSeek(percent: number): void {
    const targetPercent: number = Math.max(0, Math.min(100, percent))
    this.seekValue = targetPercent
    this.progressPercent = targetPercent
    if (this.totalDuration > 0) {
      const targetMs: number = (targetPercent / 100) * this.totalDuration
      void PlayerService.getInstance().seekTo(targetMs)
    }
    this.isSeeking = false
  }

  private handleProgressTouch(event: TouchEvent): void {
    event.stopPropagation()
    if (this.totalDuration <= 0) {
      return
    }

    const touch: TouchObject | null = this.getPrimaryTouch(event)
    if (!touch) {
      return
    }

    const percent: number = this.getProgressPercentFromTouch(touch)
    if (event.type === TouchType.Up) {
      this.commitProgressSeek(percent)
    } else if (event.type === TouchType.Cancel) {
      this.isSeeking = false
    } else {
      this.previewProgressSeek(percent)
    }
  }

  private getDialogScale(): number {
    return 0.88 + this.onlineSearchPopupProgress * 0.12
  }

  private getDetailDialogScale(): number {
    return 0.92 + this.detailDialogProgress * 0.08
  }

  private getDetailDialogTranslateY(): number {
    return (1 - this.detailDialogProgress) * 16
  }

  private getDeleteDialogScale(): number {
    return 0.92 + this.deleteDialogProgress * 0.08
  }

  private getDeleteDialogTranslateY(): number {
    return (1 - this.deleteDialogProgress) * 16
  }

  private getApiSettingsDialogInset(): number {
    return Math.max(this.topSafeHeight, this.bottomSafeHeight) + 16
  }

  private isLyricsPageVisible(): boolean {
    return this.coverLyricPageIndex === this.lyricsPageIndex
  }

  private canHandlePageSwipe(): boolean {
    return !this.isImmersiveModeShowing() && !this.isMoreSheetVisible && !this.isOnlineSearchPopupVisible &&
      !this.isDetailDialogVisible && !this.isApiSettingsDialogVisible && !this.isDeleteDialogVisible
  }

  private handlePageSwipeUpdate(offsetY: number): void {
    if (!this.canHandlePageSwipe() || offsetY <= 0 || !this.onSwipeUpdate) {
      return
    }
    this.onSwipeUpdate(offsetY)
  }

  private handlePageSwipeEnd(velocityY: number): void {
    if (!this.canHandlePageSwipe() || !this.onSwipeEnd) {
      return
    }
    this.onSwipeEnd(velocityY)
  }

  @Builder
  private ApiTextField(label: string, placeholder: string, value: string, fieldId: string) {
    Column({ space: label.length > 0 ? 10 : 0 }) {
      if (label.length > 0) {
        Text(label)
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.now_playing_primary_icon'))
      }

      TextInput({ text: value, placeholder })
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .fontSize(15)
        .fontColor($r('app.color.now_playing_primary_icon'))
        .placeholderColor($r('app.color.now_playing_secondary_icon'))
        .backgroundColor($r('app.color.online_search_api_input_bg'))
        .borderRadius(16)
        .onChange((inputValue: string) => {
          this.updateApiDraftField(fieldId, inputValue)
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ApiFieldSection(title: string, apiValue: string, apiFieldId: string, keyValue: string, keyFieldId: string) {
    Column({ space: 12 }) {
      this.ApiTextField(title, title, apiValue, apiFieldId)
      this.ApiTextField('', '密钥（可为空）', keyValue, keyFieldId)
    }
    .width('100%')
  }

  @Builder
  private ImmersiveModeIcon() {
    Stack() {
      Column()
        .width(12)
        .height(12)
        .border({ width: 1.5, color: $r('app.color.now_playing_primary_icon') })
        .borderRadius(4)

      Column()
        .width(5)
        .height(1.5)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 0, y: 4 })
      Column()
        .width(1.5)
        .height(5)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 4, y: 0 })

      Column()
        .width(5)
        .height(1.5)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 19, y: 4 })
      Column()
        .width(1.5)
        .height(5)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 18.5, y: 0 })

      Column()
        .width(5)
        .height(1.5)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 0, y: 19 })
      Column()
        .width(1.5)
        .height(5)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 4, y: 18.5 })

      Column()
        .width(5)
        .height(1.5)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 19, y: 19 })
      Column()
        .width(1.5)
        .height(5)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 18.5, y: 18.5 })
    }
    .width(24)
    .height(24)
  }

  @Builder
  private DetailIcon() {
    Stack() {
      Column()
        .width(24)
        .height(24)
        .border({ width: 1.5, color: $r('app.color.now_playing_primary_icon') })
        .borderRadius(12)

      Text('i')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.now_playing_primary_icon'))
    }
    .width(24)
    .height(24)
  }

  @Builder
  private SearchIcon() {
    Stack() {
      Column()
        .width(14)
        .height(14)
        .border({ width: 1.5, color: $r('app.color.now_playing_primary_icon') })
        .borderRadius(7)
        .position({ x: 1, y: 1 })

      Column()
        .width(8)
        .height(1.5)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .rotate({ angle: 45 })
        .position({ x: 13, y: 18 })
    }
    .width(24)
    .height(24)
  }

  @Builder
  private DeleteIcon() {
    Stack() {
      Column()
        .width(8)
        .height(2)
        .borderRadius(1)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 8, y: 1 })

      Column()
        .width(18)
        .height(2)
        .borderRadius(1)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 3, y: 4 })

      Column()
        .width(16)
        .height(17)
        .border({ width: 1.7, color: $r('app.color.now_playing_primary_icon') })
        .borderRadius(4)
        .position({ x: 4, y: 6 })

      Column()
        .width(1.5)
        .height(10)
        .borderRadius(1)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 9, y: 10 })

      Column()
        .width(1.5)
        .height(10)
        .borderRadius(1)
        .backgroundColor($r('app.color.now_playing_primary_icon'))
        .position({ x: 14, y: 10 })
    }
    .width(24)
    .height(24)
  }

  @Builder
  private MoreMenuItem(title: string, iconType: string, trailingArrow: boolean = false, onTap?: () => void) {
    Row() {
      if (iconType === 'immersive') {
        this.ImmersiveModeIcon()
      } else if (iconType === 'detail') {
        this.DetailIcon()
      } else if (iconType === 'delete') {
        this.DeleteIcon()
      } else {
        this.SearchIcon()
      }

      Text(title)
        .layoutWeight(1)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.now_playing_primary_icon'))
        .margin({ left: 14 })

      if (trailingArrow) {
        SymbolGlyph(iconType === 'search' && this.isOnlineSearchPopupVisible
          ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.now_playing_secondary_icon')])
      }
    }
    .width('100%')
    .height(60)
    .padding({ left: 20, right: 20 })
    .backgroundColor($r('app.color.now_playing_menu_item'))
    .borderRadius(18)
    .onClick(() => {
      if (onTap) {
        onTap()
      }
    })
  }

  @Builder
  private SubMenuItem(itemId: string, title: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.now_playing_primary_icon'))
        .layoutWeight(1)

      if (this.fetchStatus === 'loading' && this.activeOnlineSearchItem === itemId) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color($r('app.color.now_playing_secondary_icon'))
      }
    }
    .width('100%')
    .height(46)
    .padding({ left: 18, right: 18 })
    .backgroundColor(this.activeOnlineSearchItem === itemId
      ? this.withAlpha(this.isDarkMode ? '#FFFFFF' : '#182431', this.isDarkMode ? 0.14 : 0.08)
      : this.withAlpha(this.isDarkMode ? '#FFFFFF' : '#182431', this.isDarkMode ? 0.05 : 0.035))
    .borderRadius(14)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.activeOnlineSearchItem = itemId
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.fetchStatus !== 'loading') {
          this.activeOnlineSearchItem = ''
        }
      }
    })
    .onClick(() => {
      this.handleSubMenuAction(itemId)
    })
  }

  private handleSubMenuAction(itemId: string): void {
    // 设置按钮：始终打开 API 设置弹窗
    if (itemId === 'settings') {
      this.pendingOnlineSearchItem = ''
      this.activeOnlineSearchItem = ''
      this.openApiSettingsDialog()
      return
    }

    // 无 API 配置时：任意选项弹出 API 设置弹窗
    if (itemId === 'lyrics' && this.lyricApiUrl.length === 0) {
      this.pendingOnlineSearchItem = itemId
      this.activeOnlineSearchItem = ''
      this.openApiSettingsDialog()
      return
    }
    if (itemId === 'cover' && this.coverApiUrl.length === 0) {
      this.pendingOnlineSearchItem = itemId
      this.activeOnlineSearchItem = ''
      this.openApiSettingsDialog()
      return
    }

    // 有 API 配置时：执行在线查找
    if (itemId === 'lyrics') {
      this.executeFetchLyrics()
    } else if (itemId === 'cover') {
      this.executeFetchCover()
    }
  }

  private executeFetchLyrics(): void {
    const song = this.getCurrentSong()
    if (!song) {
      return
    }

    // 缓存检查：歌词已获取过则跳过网络请求
    if (song.lyrics.length > 0) {
      this.fetchStatus = 'success'
      this.fetchMessage = '歌词已缓存'
      this.scheduleFetchReset()
      return
    }

    this.fetchStatus = 'loading'
    this.activeOnlineSearchItem = 'lyrics'
    this.fetchMessage = ''

    const service = LrcApiService.getInstance()
    service.fetchLyrics(
      this.lyricApiUrl, song.title, song.artist, song.album, this.lyricApiKey
    ).then((lrc: string) => {
      if (lrc.length > 0) {
        song.lyrics = lrc
        this.playlistManager.persistPlaylist()
        this.fetchStatus = 'success'
        this.fetchMessage = '歌词获取成功'
      } else if (service.isLastRequestTimedOut()) {
        this.fetchStatus = 'error'
        this.fetchMessage = '歌词接口超时，请稍后重试'
      } else if (service.isLastRequestTransportError()) {
        this.fetchStatus = 'error'
        this.fetchMessage = '歌词接口响应异常'
      } else {
        this.fetchStatus = 'error'
        this.fetchMessage = '未找到歌词'
      }
      this.activeOnlineSearchItem = ''
      this.scheduleFetchReset()
    })
  }

  private executeFetchCover(): void {
    const song = this.getCurrentSong()
    if (!song) {
      return
    }

    // 缓存检查：已有在线封面 URL 则跳过网络请求
    if (song.coverUri.length > 0 && /^https?:\/\//i.test(song.coverUri)) {
      this.fetchStatus = 'success'
      this.fetchMessage = '封面已缓存'
      this.scheduleFetchReset()
      return
    }

    this.fetchStatus = 'loading'
    this.activeOnlineSearchItem = 'cover'
    this.fetchMessage = ''

    const service = LrcApiService.getInstance()
    service.fetchCover(
      this.coverApiUrl, song.title, song.artist, song.album, this.coverApiKey
    ).then((coverResult: LrcApiCoverResult) => {
      if (coverResult.pixelMap) {
        if (coverResult.coverUrl.length > 0) {
          song.coverUri = coverResult.coverUrl
          this.playlistManager.persistPlaylist()
        }
        this.coverPixelMap = coverResult.pixelMap
        void AudioScanner.updateCurrentCoverFromPixelMap(coverResult.pixelMap)
        this.fetchStatus = 'success'
        this.fetchMessage = '封面获取成功'
      } else if (service.isLastRequestTimedOut()) {
        this.fetchStatus = 'error'
        this.fetchMessage = '封面接口超时，请稍后重试'
      } else if (service.isLastRequestTransportError()) {
        this.fetchStatus = 'error'
        this.fetchMessage = '封面接口响应异常'
      } else {
        this.fetchStatus = 'error'
        this.fetchMessage = '未找到封面'
      }
      this.activeOnlineSearchItem = ''
      this.scheduleFetchReset()
    })
  }

  private scheduleFetchReset(): void {
    setTimeout(() => {
      this.fetchStatus = 'idle'
      this.fetchMessage = ''
    }, 2000)
  }

  private getDeleteConfirmMessage(): string {
    const title = this.currentTitle.length > 0 ? this.currentTitle : '当前歌曲'
    return `确定要删除${title}吗`
  }

  private async confirmDeleteCurrentSong(deleteFile: boolean): Promise<void> {
    if (this.isDeletingSong) {
      return
    }

    this.isDeletingSong = true
    const deleted: boolean = await PlayerService.getInstance().deleteCurrentSong(deleteFile)
    this.isDeletingSong = false

    if (!deleted) {
      this.closeDeleteDialog()
      return
    }

    const hasCurrentSong: boolean = PlayerService.getInstance().getCurrentSong() !== null
    this.closeMoreSheet()
    if (!hasCurrentSong && this.onClose) {
      setTimeout(() => {
        if (this.onClose) {
          this.onClose()
        }
      }, this.moreSheetAnimationDuration) as number
    }
  }

  @Builder
  private MoreActionSheet() {
    Column() {
      // 拖拽手柄
      Row() {
        Column()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.isDarkMode
            ? this.withAlpha('#FFFFFF', 0.2)
            : this.withAlpha('#182431', 0.16))
      }
      .width('100%')
      .height(20)
      .justifyContent(FlexAlign.Center)

      // 菜单项
      Column({ space: 10 }) {
        this.MoreMenuItem('沉浸模式', 'immersive', false, () => {
          this.enterImmersiveMode()
        })
        this.MoreMenuItem('详情', 'detail', false, () => {
          this.openDetailDialog()
        })
        this.MoreMenuItem('在线查找', 'search', true, () => {
          this.toggleOnlineSearchPopup()
        })
        this.MoreMenuItem('删除', 'delete', true, () => {
          this.openDeleteDialog()
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
  }

  @Builder
  private DetailRow(label: string, value: string) {
    Row() {
      Text(`${label}：`)
        .width(86)
        .fontSize(14)
        .lineHeight(21)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .flexShrink(0)

      Text(value)
        .layoutWeight(1)
        .fontSize(14)
        .lineHeight(21)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width('100%')
      .alignItems(VerticalAlign.Top)
  }

  @Builder
  private DetailDialog() {
    Column({ space: 14 }) {
      Text(this.currentTitle.length > 0 ? this.currentTitle : 'Unknown')
        .width('100%')
        .fontSize(22)
        .lineHeight(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Scroll() {
        Column({ space: 8 }) {
          this.DetailRow('艺术家', this.currentArtist.length > 0 ? this.currentArtist : 'Unknown')
          this.DetailRow('专辑', this.getDetailAlbumLabel())
          this.DetailRow('专辑艺术家', 'Unknown')
          this.DetailRow('作曲家', 'Unknown')
          this.DetailRow('音轨号', '000')
          this.DetailRow('碟号', 'Unknown')
          this.DetailRow('流派', 'Unknown')
          this.DetailRow('格式', this.getAudioFormatLabel())
          this.DetailRow('采样率', this.getDetailSampleRateLabel())
          this.DetailRow('比特率', this.getDetailBitrateLabel())
          this.DetailRow('时长', formatMs(this.totalDuration))
          this.DetailRow('大小', this.getSongFileSizeLabel())
          this.DetailRow('添加时间', this.getSongAddedDateLabel())
          this.DetailRow('文件名', this.getSongFileName())
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text('确定')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_emphasize'))
      }
      .width('100%')
      .height(42)
      .backgroundColor(Color.Transparent)
      .borderRadius(18)
      .onClick(() => {
        this.closeDetailDialog()
      })
    }
    .width('100%')
    .height(this.getDetailDialogMaxHeight())
    .constraintSize({ maxWidth: 430 })
    .padding({ left: 22, right: 22, top: 24, bottom: 16 })
    .backgroundColor(this.isDarkMode ? 'rgba(32, 34, 40, 1.0)' : 'rgba(255, 255, 255, 1.0)')
    .backgroundBlurStyle(BlurStyle.Thick, { colorMode: ThemeColorMode.SYSTEM })
    .borderRadius(34)
    .shadow({
      radius: 40,
      color: this.getMenuShadowColor(),
      offsetX: 0,
      offsetY: 16
    })
    .opacity(this.detailDialogProgress)
    .scale({
      x: this.getDetailDialogScale(),
      y: this.getDetailDialogScale(),
      centerX: '50%',
      centerY: '50%'
    })
    .translate({ x: 0, y: this.getDetailDialogTranslateY() })
  }

  @Builder
  private DeleteDialog() {
    Column() {
      Text('删除歌曲')
        .width('100%')
        .fontSize(22)
        .lineHeight(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))

      Text(this.getDeleteConfirmMessage())
        .width('100%')
        .fontSize(15)
        .lineHeight(22)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 18, bottom: 20 })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text('取消')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_emphasize'))
      }
      .width('100%')
      .height(42)
      .backgroundColor(Color.Transparent)
      .borderRadius(18)
      .enabled(!this.isDeletingSong)
      .onClick(() => {
        this.closeDeleteDialog()
      })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text('删除')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF3B30')
      }
      .width('100%')
      .height(42)
      .backgroundColor(Color.Transparent)
      .borderRadius(18)
      .enabled(!this.isDeletingSong)
      .onClick(() => {
        void this.confirmDeleteCurrentSong(false)
      })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        if (this.isDeletingSong) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color('#FF3B30')
        } else {
          Text('同时删除文件')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF3B30')
        }
      }
      .width('100%')
      .height(42)
      .backgroundColor(Color.Transparent)
      .borderRadius(18)
      .enabled(!this.isDeletingSong)
      .onClick(() => {
        void this.confirmDeleteCurrentSong(true)
      })
    }
    .width('100%')
    .constraintSize({ maxWidth: 360 })
    .padding({ left: 24, right: 24, top: 24, bottom: 22 })
    .backgroundColor(this.isDarkMode ? 'rgba(32, 34, 40, 1.0)' : 'rgba(255, 255, 255, 1.0)')
    .borderRadius(28)
    .shadow({
      radius: 40,
      color: this.getMenuShadowColor(),
      offsetX: 0,
      offsetY: 16
    })
    .opacity(this.deleteDialogProgress)
    .scale({
      x: this.getDeleteDialogScale(),
      y: this.getDeleteDialogScale(),
      centerX: '50%',
      centerY: '50%'
    })
    .translate({ x: 0, y: this.getDeleteDialogTranslateY() })
  }

  @Builder
  private OnlineSearchDialog() {
    Column() {
      // 标题
      Row() {
        Text('在线查找')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.now_playing_primary_icon'))
      }
      .width('100%')
      .height(46)
      .justifyContent(FlexAlign.Center)

      // 子菜单项
      this.SubMenuItem('lyrics', '歌词')
      this.SubMenuItem('cover', '封面')
      this.SubMenuItem('settings', '设置')

      // 状态提示
      if (this.fetchMessage.length > 0) {
        Row() {
          Text(this.fetchMessage)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.fetchStatus === 'success'
              ? '#34C759' : (this.fetchStatus === 'error' ? '#FF6B6B' : $r('app.color.now_playing_secondary_icon')))
        }
        .width('100%')
        .height(36)
        .justifyContent(FlexAlign.Center)
        .transition(TransitionEffect.opacity(0))
      }

      // 取消按钮
      Row() {
        Text('取消')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.now_playing_secondary_icon'))
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.Center)
      .borderRadius(14)
      .margin({ top: this.fetchMessage.length > 0 ? 0 : 4 })
      .onClick(() => {
        this.closeOnlineSearchPopup()
      })
    }
    .width(300)
    .padding({ left: 16, right: 16, top: 10, bottom: 14 })
    .backgroundColor(this.isDarkMode ? 'rgba(32, 34, 40, 1.0)' : 'rgba(255, 255, 255, 1.0)')
    .borderRadius(26)
    .shadow({
      radius: 32,
      color: this.getMenuShadowColor(),
      offsetX: 0,
      offsetY: 12
    })
    .opacity(this.onlineSearchPopupProgress)
    .scale({
      x: this.getDialogScale(),
      y: this.getDialogScale(),
      centerX: '50%',
      centerY: '50%'
    })
  }

  @Builder
  private ApiSettingsDialog() {
    Column({ space: 20 }) {
      Text('API设置')
        .width('100%')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.now_playing_primary_icon'))

      Column({ space: 6 }) {
        Text('设置 API 后可以使用在线查找功能')
          .width('100%')
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.now_playing_primary_icon'))

        Text('注意，此功能需要连接网络，且使用前您需要保证您拥有相关著作人的授权，否则可能导致法律纠纷，本软件对此不负任何责任。')
          .width('100%')
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.online_search_api_warning'))

        Text('目前支持的协议（点击跳转）：')
          .width('100%')
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.now_playing_primary_icon'))

        Text('https://github.com/hisatri/LrcAPI')
          .width('100%')
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.online_search_api_link'))
      }
      .width('100%')

      Column({ space: 22 }) {
        this.ApiFieldSection('歌词', this.draftLyricApiUrl, 'lyrics_api', this.draftLyricApiKey, 'lyrics_key')
        this.ApiFieldSection('封面', this.draftCoverApiUrl, 'cover_api', this.draftCoverApiKey, 'cover_key')
      }
      .width('100%')

      Row({ space: 16 }) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text('取消')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.now_playing_primary_icon'))
        }
        .layoutWeight(1)
        .height(52)
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .onClick(() => {
          this.closeApiSettingsDialog(false)
        })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text('确定')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.now_playing_primary_icon'))
        }
        .layoutWeight(1)
        .height(52)
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .onClick(() => {
          this.closeApiSettingsDialog(true)
        })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 26, bottom: 20 })
    .backgroundColor($r('app.color.online_search_api_dialog_surface'))
    .backgroundBlurStyle(BlurStyle.Thick, { colorMode: ThemeColorMode.SYSTEM })
    .borderRadius(30)
    .shadow({
      radius: 36,
      color: this.getMenuShadowColor(),
      offsetX: 0,
      offsetY: 16
    })
    .opacity(this.apiSettingsDialogProgress)
    .scale({
      x: this.getApiSettingsDialogScale(),
      y: this.getApiSettingsDialogScale(),
      centerX: '50%',
      centerY: '50%'
    })
    .translate({ x: 0, y: this.getApiSettingsDialogTranslateY() })
  }

  @Builder
  private AudioTagRow() {
    Row({ space: 18 }) {
      ForEach(this.getAudioTags(), (item: string) => {
        Text(item)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.coverPageTertiaryColor)
      }, (item: string) => item)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private CoverCard() {
    Stack() {
      if (this.coverPixelMap) {
        Image(this.coverPixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(120)
            .fontColor([this.coverPageSecondaryColor])
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.mini_player_placeholder'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
      .width(this.getOverlayCoverSize())
      .height(this.getOverlayCoverSize())
      .borderRadius(18)
      .clip(true)
      .shadow({
        radius: 24,
        color: this.getCoverShadowColor(),
        offsetX: 0,
        offsetY: 12
      })
  }

  @Builder
  private OverlayMorphLayer() {
    Stack() {
      Stack() {
        if (this.coverPixelMap) {
          Image(this.coverPixelMap)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(120)
              .fontColor([$r('sys.color.ohos_id_color_text_primary')])
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.mini_player_placeholder'))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width(this.getOverlayCoverSize())
      .height(this.getOverlayCoverSize())
      .borderRadius(18)
      .clip(true)
      .position({ x: this.getOverlayCoverLeft(), y: this.getOverlayCoverTop() })
      .shadow({
        radius: 24,
        color: this.getCoverShadowColor(),
        offsetX: 0,
        offsetY: 12
      })

      Text(this.currentTitle.length > 0 ? this.currentTitle : 'No song playing')
        .width(this.getOverlayTitleWidth())
        .height(this.overlayTitleLineHeight)
        .fontSize(this.overlayTitleFont)
        .lineHeight(this.overlayTitleLineHeight)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.coverPagePrimaryColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .position({ x: this.getOverlayTitleLeft(), y: this.getOverlayTitleTop() })
        .opacity(this.getImmersiveHiddenOpacity())

      Text(this.currentArtist)
        .width(this.getOverlayTitleWidth())
        .height(this.overlayArtistLineHeight)
        .fontSize(this.overlayArtistFont)
        .lineHeight(this.overlayArtistLineHeight)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.coverPageSecondaryColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .position({ x: this.getOverlayTitleLeft(), y: this.getOverlayArtistTop() })
        .opacity(this.getImmersiveHiddenOpacity())
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .zIndex(20)
  }

  @Builder
  private ProgressSection() {
    Row({ space: this.progressInlineGap }) {
      Text(formatMs(this.isSeeking ? (this.seekValue / 100) * this.totalDuration : this.currentPosition))
        .width(this.progressTimeLabelWidth)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.coverPageSecondaryColor)
        .textAlign(TextAlign.Start)

      Stack({ alignContent: Alignment.Center }) {
        Slider({
          value: this.isSeeking ? this.seekValue : this.progressPercent,
          min: 0,
          max: 100,
          step: 0.1,
          style: SliderStyle.OutSet
        })
          .width('100%')
          .trackColor(this.coverPageProgressTrackColor)
          .selectedColor(this.dominantColor)
          .blockColor(this.coverPagePrimaryColor)
          .blockSize({ width: 12, height: 12 })
          .trackThickness(6)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (!this.isComponentReady) {
              return
            }
            if (mode === SliderChangeMode.Begin) {
              this.previewProgressSeek(value)
            } else if (mode === SliderChangeMode.Moving) {
              this.previewProgressSeek(value)
            } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.commitProgressSeek(value)
            }
          })

        Row()
          .width('100%')
          .height(44)
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Default)
          .onTouch((event: TouchEvent) => {
            this.handleProgressTouch(event)
          })
          .zIndex(1)
      }
      .width(this.getProgressTouchWidth())
      .height(44)
      .hitTestBehavior(HitTestMode.Default)

      Text(formatMs(this.totalDuration))
        .width(this.progressTimeLabelWidth)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.coverPageSecondaryColor)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ProgressHitLayer() {
    Row()
      .width(this.getProgressTouchWidth())
      .height(56)
      .position({ x: this.getProgressTouchLeft(), y: this.getProgressTouchTop() - 6 })
      .backgroundColor(this.withAlpha('#000000', 0.001))
      .hitTestBehavior(HitTestMode.Default)
      .onTouch((event: TouchEvent) => {
        this.handleProgressTouch(event)
      })
      .zIndex(45)
  }

  @Builder
  private ImmersiveCoverExitLayer() {
    Row()
      .width(this.getOverlayCoverTargetSize())
      .height(this.getOverlayCoverTargetSize())
      .position({ x: this.getOverlayCoverTargetLeft(), y: this.getOverlayCoverTargetTop() })
      .backgroundColor(this.withAlpha('#000000', 0.001))
      .hitTestBehavior(HitTestMode.Default)
      .onClick(() => {
        this.exitImmersiveMode()
      })
      .zIndex(60)
  }

  @Builder
  private SongInfoSection() {
    Column({ space: 4 }) {
      Row() {
        Text(this.currentTitle)
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.coverPagePrimaryColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        SymbolGlyph(this.isCurrentSongFavorite() ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(22)
          .fontColor([this.isCurrentSongFavorite() ? '#FF3B30' :
            this.coverPageSecondaryColor])
          .margin({ left: 12 })
          .onClick(() => {
            const song = this.getCurrentSong()
            if (song) {
              void FavoriteManager.getInstance().toggleFavorite(song)
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.currentArtist)
        .fontSize(18)
        .fontWeight(FontWeight.Regular)
        .fontColor(this.coverPageSecondaryColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 8, bottom: 4 })
  }

  private isCurrentSongFavorite(): boolean {
    const song = this.getCurrentSong()
    if (!song) {
      return false
    }
    try {
      const arr = JSON.parse(this.favoriteIdsStr) as string[]
      return new Set(arr).has(song.id)
    } catch (_) {
      return false
    }
  }

  @Builder
  private CoverPageTopBar() {
    Row()
      .width('100%')
      .height(48)
  }

  @Builder
  private CoverPageContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 0 }) {
        Column()
          .height(this.topSafeHeight + 2)

        Column() {
          this.CoverPageTopBar()
        }
        .opacity(this.getContentOpacity(0.60))
        .translate({ x: 0, y: this.getContentTranslateY(0.60, 18) })

        Column()
          .width('100%')
          .height(this.getCoverPageTopSpacerHeight())

        Row() {
          this.CoverCard()
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .opacity(this.getContentOpacity(0.58))
        .scale({
          x: 0.82 + 0.18 * this.getContentOpacity(0.58),
          y: 0.82 + 0.18 * this.getContentOpacity(0.58),
          centerX: '50%',
          centerY: '50%'
        })

        Column() {
          this.AudioTagRow()
        }
        .width('100%')
        .height(this.overlayAudioHeight)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12 })
        .opacity(this.getContentOpacity(0.70) * this.getImmersiveHiddenOpacity())
        .translate({ x: 0, y: this.getContentTranslateY(0.70, 40) - 18 * this.getImmersiveProgress() })
        .hitTestBehavior(this.isImmersiveModeShowing() ? HitTestMode.None : HitTestMode.Default)

        Blank()
          .layoutWeight(1)

        Column() {
          this.ProgressSection()
        }
        .height(this.overlayProgressHeight)
        .opacity(this.getContentOpacity(0.78) * this.getImmersiveHiddenOpacity())
        .translate({ x: 0, y: this.getContentTranslateY(0.78, 60) + 18 * this.getImmersiveProgress() })
        .hitTestBehavior(this.isImmersiveModeShowing() ? HitTestMode.None : HitTestMode.Default)

        Column()
          .height(this.getProgressBottomSpacerHeight())
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24 })

      if (this.expandProgress > 0.85) {
        Column() {
          PlayControls({
            bottomSafe: this.bottomSafeHeight + this.controlsFloatingOffset,
            immersiveProgress: this.getImmersiveProgress(),
            primaryColor: this.coverPagePrimaryColor,
            secondaryColor: this.coverPageSecondaryColor,
            accentColor: this.dominantColor,
            onMoreClick: () => {
              this.toggleMoreSheet()
            }
          })
        }
        .width('100%')
        .opacity(this.getContentOpacity(0.88))
        .translate({ x: 0, y: this.getContentTranslateY(0.88, 260) + this.getImmersiveControlsTranslateY() })
        .hitTestBehavior(this.expandProgress < 0.96 ? HitTestMode.None : HitTestMode.Default)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private LyricsPageContent() {
    Column() {
      Column()
        .height(this.topSafeHeight + 4)

      LyricView({
        lyricLines: this.lyricLines,
        currentIndex: this.lyricIndex,
        dominantColor: this.dominantColor,
        isDarkMode: this.isDarkMode
      })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.getBackdropBaseColor())
          .opacity(this.getBgOpacity())

        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 160,
            colors: [
              [this.coverBackdropTopColor, 0.0],
              [this.coverBackdropMiddleColor, 0.46],
              [this.coverBackdropBottomColor, 1.0]
            ]
          })
          .opacity(this.getBgOpacity())
          .animation({ duration: 800, curve: Curve.EaseInOut })

        Ellipse()
          .width(this.getOverlayScreenWidth() * 1.18)
          .height(this.getOverlayScreenWidth() * 0.78)
          .fill(this.coverBackdropGlowColor)
          .opacity(this.getBgOpacity() * 0.22)
          .blur(72)
          .offset({
            x: -this.getOverlayScreenWidth() * 0.22,
            y: -this.getOverlayScreenHeight() * 0.25
          })

        Ellipse()
          .width(this.getOverlayScreenWidth() * 0.96)
          .height(this.getOverlayScreenWidth() * 0.70)
          .fill(this.coverBackdropAccentGlowColor)
          .opacity(this.getBgOpacity() * 0.16)
          .blur(78)
          .offset({
            x: this.getOverlayScreenWidth() * 0.24,
            y: this.getOverlayScreenHeight() * 0.16
          })

        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.coverBackdropVeilColor)
          .opacity(this.getBgOpacity())
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.currentIndex < 0 || this.currentTitle.length === 0) {
        Column({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(72)
            .fontColor([this.coverPageSecondaryColor])

          Text('Select a song to start playback')
            .fontSize(16)
            .fontColor(this.coverPageSecondaryColor)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Swiper(this.coverLyricSwiperController) {
          this.CoverPageContent()
          this.LyricsPageContent()
        }
        .index(this.coverLyricPageIndex)
        .indicator(false)
        .loop(false)
        .disableSwipe(this.isImmersiveModeShowing())
        .duration(240)
        .curve(Curve.EaseInOut)
        .width('100%')
        .height('100%')
        .gesture(
          PanGesture({ direction: PanDirection.Vertical, distance: 6 })
            .onActionUpdate((event: GestureEvent) => {
              this.handlePageSwipeUpdate(event.offsetY)
            })
            .onActionEnd((event: GestureEvent) => {
              this.handlePageSwipeEnd(event.velocityY)
            })
        )
        .onContentDidScroll((_selectedIndex: number, index: number, position: number, _mainAxisLength: number) => {
          if (index === this.coverPageIndex) {
            this.emitLyricsProgress(-position)
          }
        })
        .onChange((index: number) => {
          this.coverLyricPageIndex = index
          this.emitLyricsProgress(index === this.lyricsPageIndex ? 1 : 0)
        })
      }

      if (this.modalOverlayActive && !this.isLyricsPageVisible()) {
        this.OverlayMorphLayer()
      }

      if (this.shouldShowProgressHitLayer()) {
        this.ProgressHitLayer()
      }

      if (this.isImmersiveModeShowing() && !this.isLyricsPageVisible()) {
        this.ImmersiveCoverExitLayer()
      }

      if (this.isMoreSheetVisible) {
        Stack({ alignContent: Alignment.Bottom }) {
          // 半透明遮罩层
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.getMenuScrimColor())
            .opacity(this.moreSheetProgress)
            .onClick(() => {
              this.closeMoreSheet()
            })
            .zIndex(0)

          // 底部半模态面板
          Column() {
            this.MoreActionSheet()
          }
          .width('100%')
          .constraintSize({ maxWidth: 520 })
          .backgroundColor($r('app.color.now_playing_menu_panel'))
          .borderRadius({ topLeft: 28, topRight: 28, bottomLeft: 0, bottomRight: 0 })
          .clip(true)
          .shadow({
            radius: 28,
            color: this.getMenuShadowColor(),
            offsetX: 0,
            offsetY: -8
          })
          .padding({ bottom: Math.max(this.bottomSafeHeight, 32) })
          .translate({ x: 0, y: this.getSheetTranslateY() })
          .zIndex(1)
          .gesture(
            PanGesture({ direction: PanDirection.Vertical })
              .onActionStart(() => {
                this.sheetStartY = 0
              })
              .onActionUpdate((event: GestureEvent) => {
                const offsetY: number = event.offsetY
                if (offsetY > 0) {
                  this.sheetDragOffsetY = offsetY
                } else {
                  this.sheetDragOffsetY = offsetY * 0.15
                }
              })
              .onActionEnd((event: GestureEvent) => {
                if (this.sheetDragOffsetY > 80 || (event.velocityY > 500)) {
                  this.closeMoreSheet()
                } else {
                  animateTo({
                    duration: 200,
                    curve: Curve.EaseOut
                  }, () => {
                    this.sheetDragOffsetY = 0
                  })
                }
              })
          )

          // 二级菜单居中弹窗
          if (this.isOnlineSearchPopupVisible) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.withAlpha('#0D1220', this.isDarkMode ? 0.42 : 0.32))
              .opacity(this.onlineSearchPopupProgress)
              .onClick(() => {
                this.closeOnlineSearchPopup()
              })
              .zIndex(2)

            Column() {
              this.OnlineSearchDialog()
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .hitTestBehavior(HitTestMode.Transparent)
            .zIndex(3)
          }

          if (this.isDetailDialogVisible) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.withAlpha('#0D1220', this.isDarkMode ? 0.18 : 0.10))
              .onClick(() => {
                this.closeDetailDialog()
              })
              .zIndex(2)

            Column() {
              this.DetailDialog()
            }
            .width('100%')
            .height('100%')
            .padding({
              left: 20,
              right: 20,
              top: this.topSafeHeight + 24,
              bottom: this.bottomSafeHeight + 24
            })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .hitTestBehavior(HitTestMode.Transparent)
            .zIndex(3)
          }

          if (this.isDeleteDialogVisible) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.withAlpha('#0D1220', this.isDarkMode ? 0.44 : 0.34))
              .opacity(this.deleteDialogProgress)
              .onClick(() => {
                this.closeDeleteDialog()
              })
              .zIndex(2)

            Column() {
              this.DeleteDialog()
            }
            .width('100%')
            .height('100%')
            .padding({
              left: 20,
              right: 20,
              top: this.topSafeHeight + 24,
              bottom: this.bottomSafeHeight + 24
            })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .hitTestBehavior(HitTestMode.Transparent)
            .zIndex(3)
          }

          if (this.isApiSettingsDialogVisible) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.withAlpha('#0D1220', this.isDarkMode ? 0.28 : 0.18))
              .opacity(this.apiSettingsDialogProgress)
              .onClick(() => {
                this.closeApiSettingsDialog(false)
              })
              .zIndex(2)

            Column() {
              this.ApiSettingsDialog()
            }
            .width('100%')
            .height('100%')
            .padding({
              left: 20,
              right: 20,
              top: this.getApiSettingsDialogInset(),
              bottom: this.getApiSettingsDialogInset()
            })
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .hitTestBehavior(HitTestMode.Transparent)
            .zIndex(3)
          }
        }
        .width('100%')
        .height('100%')
        .zIndex(50)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
