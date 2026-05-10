import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { image } from '@kit.ImageKit'
import { effectKit } from '@kit.ArkGraphics2D'
import { Colors, StorageKeys } from '../common/Constants'

export interface CoverThemeRgb {
  red: number
  green: number
  blue: number
}

export interface CoverPageTheme {
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

export class CoverThemeService {
  private static instance: CoverThemeService | null = null
  private preferences: preferences.Preferences | null = null
  private readonly storeName: string = 'cover_theme_store'
  private readonly memoryCache: Map<string, CoverPageTheme> = new Map<string, CoverPageTheme>()

  private constructor() {}

  static getInstance(): CoverThemeService {
    if (!CoverThemeService.instance) {
      CoverThemeService.instance = new CoverThemeService()
    }
    return CoverThemeService.instance
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.preferences) {
      return
    }

    try {
      this.preferences = await preferences.getPreferences(context, this.storeName)
    } catch (error) {
      console.error('CoverThemeService', `Init failed: ${JSON.stringify(error)}`)
    }
  }

  isInitialized(): boolean {
    return this.preferences !== null
  }

  async loadCachedTheme(cacheKey: string): Promise<CoverPageTheme | null> {
    const memoryTheme = this.memoryCache.get(cacheKey)
    if (memoryTheme) {
      return memoryTheme
    }

    if (!this.preferences) {
      return null
    }

    try {
      const raw = await this.preferences.get(this.getPreferenceKey(cacheKey), '') as string
      if (raw.length === 0) {
        return null
      }
      const theme = this.parseCachedTheme(raw)
      if (theme) {
        this.memoryCache.set(cacheKey, theme)
      }
      return theme
    } catch (error) {
      console.error('CoverThemeService', `Load cached theme failed: ${JSON.stringify(error)}`)
      return null
    }
  }

  async computeAndCacheTheme(cacheKey: string, pixelMap: image.PixelMap, isDarkMode: boolean): Promise<CoverPageTheme> {
    let themePixelMap: image.PixelMap | null = null
    let shouldReleaseThemePixelMap: boolean = false

    try {
      const sampledPixelMap = await this.createThemePixelMap(pixelMap)
      themePixelMap = sampledPixelMap
      shouldReleaseThemePixelMap = sampledPixelMap !== pixelMap

      const colorPicker = await effectKit.createColorPicker(sampledPixelMap)
      const mainColor = colorPicker.getMainColorSync() as CoverThemeRgb
      const averageColor = colorPicker.getAverageColor() as CoverThemeRgb
      const saturationColor = colorPicker.getHighestSaturationColor() as CoverThemeRgb
      const edgeColor = await this.getEdgeAverageColor(sampledPixelMap)

      const fallbackColor: CoverThemeRgb = this.hexToRgb(Colors.DEFAULT_DOMINANT_COLOR)
      const safeMainColor: CoverThemeRgb = this.isUsableThemeColor(mainColor) ? mainColor : fallbackColor
      const safeAverageColor: CoverThemeRgb = this.isUsableThemeColor(averageColor) ? averageColor : safeMainColor
      const safeSaturationColor: CoverThemeRgb = this.isUsableThemeColor(saturationColor) ? saturationColor : safeMainColor
      const safeEdgeColor: CoverThemeRgb = this.isUsableThemeColor(edgeColor) ? edgeColor : safeAverageColor

      console.info('ThemeColor',
        `main=${this.colorToText(safeMainColor)} average=${this.colorToText(safeAverageColor)} ` +
          `edge=${this.colorToText(safeEdgeColor)} saturation=${this.colorToText(safeSaturationColor)}`)

      const theme = this.buildCoverPageTheme(safeMainColor, safeAverageColor, safeEdgeColor, safeSaturationColor, isDarkMode)
      this.memoryCache.set(cacheKey, theme)
      await this.persistTheme(cacheKey, theme)
      return theme
    } catch (error) {
      console.error('CoverThemeService', `Compute theme failed: ${JSON.stringify(error)}`)
      return this.getFallbackTheme(isDarkMode)
    } finally {
      if (shouldReleaseThemePixelMap && themePixelMap) {
        themePixelMap.release()
      }
    }
  }

  applyTheme(theme: CoverPageTheme): void {
    AppStorage.setOrCreate(StorageKeys.COVER_THEME_PRIMARY_COLOR, theme.primaryColor)
    AppStorage.setOrCreate(StorageKeys.COVER_THEME_SECONDARY_COLOR, theme.secondaryColor)
    AppStorage.setOrCreate('coverBackdropBaseColor', theme.baseColor)
    AppStorage.setOrCreate('coverBackdropTopColor', theme.topColor)
    AppStorage.setOrCreate('coverBackdropMiddleColor', theme.middleColor)
    AppStorage.setOrCreate('coverBackdropBottomColor', theme.bottomColor)
    AppStorage.setOrCreate('coverBackdropVeilColor', theme.veilColor)
    AppStorage.setOrCreate('coverBackdropGlowColor', theme.glowColor)
    AppStorage.setOrCreate('coverBackdropAccentGlowColor', theme.glowAccentColor)
    AppStorage.setOrCreate('coverThemeShadowColor', theme.shadowColor)
    AppStorage.setOrCreate('coverThemeAccentColor', theme.glowAccentColor)
  }

  getFallbackTheme(isDarkMode: boolean): CoverPageTheme {
    if (isDarkMode) {
      const darkTheme: CoverPageTheme = {
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
      return darkTheme
    }

    const lightTheme: CoverPageTheme = {
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
    return lightTheme
  }

  private getPreferenceKey(cacheKey: string): string {
    return `theme_${this.hashString(cacheKey)}`
  }

  private hashString(value: string): string {
    let hash: number = 0
    for (let i = 0; i < value.length; i += 1) {
      hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0
    }
    return Math.abs(hash).toString()
  }

  private async persistTheme(cacheKey: string, theme: CoverPageTheme): Promise<void> {
    if (!this.preferences) {
      return
    }

    try {
      await this.preferences.put(this.getPreferenceKey(cacheKey), JSON.stringify(theme))
      await this.preferences.flush()
    } catch (error) {
      console.error('CoverThemeService', `Persist theme failed: ${JSON.stringify(error)}`)
    }
  }

  private parseCachedTheme(raw: string): CoverPageTheme | null {
    try {
      const theme = JSON.parse(raw) as CoverPageTheme
      if (typeof theme.baseColor !== 'string' || typeof theme.topColor !== 'string' ||
        typeof theme.middleColor !== 'string' || typeof theme.bottomColor !== 'string' ||
        typeof theme.glowColor !== 'string' || typeof theme.glowAccentColor !== 'string' ||
        typeof theme.primaryColor !== 'string' || typeof theme.secondaryColor !== 'string') {
        return null
      }
      return theme
    } catch (_) {
      return null
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
      const fallback: CoverThemeRgb = { red: 238, green: 238, blue: 238 }
      return fallback
    }

    const color: CoverThemeRgb = {
      red: Math.round(redTotal / count),
      green: Math.round(greenTotal / count),
      blue: Math.round(blueTotal / count)
    }
    return color
  }

  private buildCoverPageTheme(
    mainColor: CoverThemeRgb,
    averageColor: CoverThemeRgb,
    edgeColor: CoverThemeRgb,
    saturationColor: CoverThemeRgb,
    isDarkMode: boolean
  ): CoverPageTheme {
    const rawSeedColor = this.selectSafeSeedColor(mainColor, averageColor, edgeColor, saturationColor)
    const seedColor = this.normalizeSeedColor(rawSeedColor, edgeColor)
    const mixedColor = this.mixColor(seedColor, edgeColor, 0.42)
    const seedLuminance: number = this.getLuminance(seedColor)
    const isDarkTheme: boolean = isDarkMode || seedLuminance < 115

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

    const fixed: CoverThemeRgb = {
      red: this.clampColor(color.red - 8),
      green: this.clampColor(color.green + 12),
      blue: this.clampColor(color.blue + 38)
    }
    return fixed
  }

  private toSoftWarmColor(color: CoverThemeRgb): CoverThemeRgb {
    const fixed: CoverThemeRgb = {
      red: this.clampColor(color.red),
      green: this.clampColor(color.green + 8),
      blue: this.clampColor(color.blue + 18)
    }
    return fixed
  }

  private fixOverSaturatedColor(color: CoverThemeRgb): CoverThemeRgb {
    const saturationLike: number = this.getColorfulness(color)
    if (saturationLike < 90) {
      return color
    }

    const gray: number = this.getLuminance(color)
    const fixed: CoverThemeRgb = {
      red: this.clampColor(gray + (color.red - gray) * 0.55),
      green: this.clampColor(gray + (color.green - gray) * 0.55),
      blue: this.clampColor(gray + (color.blue - gray) * 0.55)
    }
    return fixed
  }

  private fixTooDarkColor(color: CoverThemeRgb): CoverThemeRgb {
    if (this.getLuminance(color) >= 80) {
      return color
    }

    const fixed: CoverThemeRgb = {
      red: this.clampColor(color.red + 55),
      green: this.clampColor(color.green + 55),
      blue: this.clampColor(color.blue + 55)
    }
    return fixed
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
      const light: CoverThemeRgb = { red: 226, green: 236, blue: 240 }
      return light
    }

    const dark: CoverThemeRgb = { red: 72, green: 84, blue: 92 }
    return dark
  }

  private toPastelBackground(color: CoverThemeRgb, whiteRatio: number, saturationRatio: number): CoverThemeRgb {
    const gray: number = this.getLuminance(color)
    const preserved: CoverThemeRgb = {
      red: this.clampColor(gray + (color.red - gray) * saturationRatio),
      green: this.clampColor(gray + (color.green - gray) * saturationRatio),
      blue: this.clampColor(gray + (color.blue - gray) * saturationRatio)
    }

    const white: CoverThemeRgb = { red: 255, green: 255, blue: 255 }
    return this.mixColor(preserved, white, whiteRatio)
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
      const white: CoverThemeRgb = { red: 255, green: 255, blue: 255 }
      return this.mixColor(preserved, white, 0.08)
    }

    const dark: CoverThemeRgb = { red: 32, green: 36, blue: 44 }
    return this.mixColor(preserved, dark, 0.18)
  }

  private toDarkBackground(color: CoverThemeRgb, darkRatio: number, saturationRatio: number): CoverThemeRgb {
    const gray: number = this.getLuminance(color)
    const preserved: CoverThemeRgb = {
      red: this.clampColor(gray + (color.red - gray) * saturationRatio),
      green: this.clampColor(gray + (color.green - gray) * saturationRatio),
      blue: this.clampColor(gray + (color.blue - gray) * saturationRatio)
    }

    const dark: CoverThemeRgb = { red: 24, green: 28, blue: 34 }
    return this.mixColor(preserved, dark, darkRatio)
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
    const color: CoverThemeRgb = {
      red: this.clampColor(a.red * (1 - safeRatio) + b.red * safeRatio),
      green: this.clampColor(a.green * (1 - safeRatio) + b.green * safeRatio),
      blue: this.clampColor(a.blue * (1 - safeRatio) + b.blue * safeRatio)
    }
    return color
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
    return !!color && Number.isFinite(color.red) && Number.isFinite(color.green) && Number.isFinite(color.blue)
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
      const fallback: CoverThemeRgb = { red: 123, green: 127, blue: 255 }
      return fallback
    }

    const rgb: CoverThemeRgb = {
      red: Number.parseInt(hex.substring(0, 2), 16),
      green: Number.parseInt(hex.substring(2, 4), 16),
      blue: Number.parseInt(hex.substring(4, 6), 16)
    }
    return rgb
  }

  private clampColor(value: number): number {
    return Math.max(0, Math.min(255, Math.round(value)))
  }
}
