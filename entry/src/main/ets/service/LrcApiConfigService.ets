import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'

export class LrcApiSettings {
  lyricsApiUrl: string = 'https://api.lrc.cx/lyrics'
  lyricsApiKey: string = ''
  coverApiUrl: string = 'https://api.lrc.cx/cover'
  coverApiKey: string = ''

  constructor(
    lyricsApiUrl: string = 'https://api.lrc.cx/lyrics',
    lyricsApiKey: string = '',
    coverApiUrl: string = 'https://api.lrc.cx/cover',
    coverApiKey: string = ''
  ) {
    this.lyricsApiUrl = lyricsApiUrl
    this.lyricsApiKey = lyricsApiKey
    this.coverApiUrl = coverApiUrl
    this.coverApiKey = coverApiKey
  }
}

export class LrcApiConfigService {
  private static instance: LrcApiConfigService | null = null
  private preferences: preferences.Preferences | null = null
  private readonly storeName: string = 'lrc_api_store'
  private readonly lyricsApiUrlKey: string = 'lyrics_api_url'
  private readonly lyricsApiKeyKey: string = 'lyrics_api_key'
  private readonly coverApiUrlKey: string = 'cover_api_url'
  private readonly coverApiKeyKey: string = 'cover_api_key'

  private constructor() {}

  static getInstance(): LrcApiConfigService {
    if (!LrcApiConfigService.instance) {
      LrcApiConfigService.instance = new LrcApiConfigService()
    }
    return LrcApiConfigService.instance
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.preferences) {
      return
    }

    try {
      this.preferences = await preferences.getPreferences(context, this.storeName)
    } catch (error) {
      console.error('LrcApiConfigService', `Init failed: ${JSON.stringify(error)}`)
    }
  }

  getDefaultSettings(): LrcApiSettings {
    return new LrcApiSettings()
  }

  async loadSettings(): Promise<LrcApiSettings> {
    const defaults = this.getDefaultSettings()
    if (!this.preferences) {
      return defaults
    }

    try {
      return new LrcApiSettings(
        this.normalizeUrlInput(await this.preferences.get(this.lyricsApiUrlKey, defaults.lyricsApiUrl) as string),
        this.normalizeTokenInput(await this.preferences.get(this.lyricsApiKeyKey, defaults.lyricsApiKey) as string),
        this.normalizeUrlInput(await this.preferences.get(this.coverApiUrlKey, defaults.coverApiUrl) as string),
        this.normalizeTokenInput(await this.preferences.get(this.coverApiKeyKey, defaults.coverApiKey) as string)
      )
    } catch (error) {
      console.error('LrcApiConfigService', `Load settings failed: ${JSON.stringify(error)}`)
      return defaults
    }
  }

  async saveSettings(settings: LrcApiSettings): Promise<void> {
    if (!this.preferences) {
      return
    }

    try {
      await this.preferences.put(this.lyricsApiUrlKey, this.normalizeUrlInput(settings.lyricsApiUrl))
      await this.preferences.put(this.lyricsApiKeyKey, this.normalizeTokenInput(settings.lyricsApiKey))
      await this.preferences.put(this.coverApiUrlKey, this.normalizeUrlInput(settings.coverApiUrl))
      await this.preferences.put(this.coverApiKeyKey, this.normalizeTokenInput(settings.coverApiKey))
      await this.preferences.flush()
    } catch (error) {
      console.error('LrcApiConfigService', `Save settings failed: ${JSON.stringify(error)}`)
    }
  }

  private normalizeUrlInput(value: string): string {
    const normalized = typeof value === 'string' ? value.trim() : ''
    return normalized.length > 0 ? normalized : ''
  }

  private normalizeTokenInput(value: string): string {
    return typeof value === 'string' ? value.trim() : ''
  }
}
