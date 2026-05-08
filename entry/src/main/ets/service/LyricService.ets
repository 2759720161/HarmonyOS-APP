import { LyricLine, LyricParser } from './LyricParser'
import { LrcApiService } from './LrcApiService'
import { LrcApiConfigService, LrcApiSettings } from './LrcApiConfigService'
import { StorageKeys } from '../common/Constants'
import { SongInfo } from '../model/SongInfo'

export class LyricService {
  private static instance: LyricService | null = null
  private lrcApiService: LrcApiService = LrcApiService.getInstance()
  private lrcApiConfigService: LrcApiConfigService = LrcApiConfigService.getInstance()
  private currentLyricLines: LyricLine[] = []
  private lastSong: SongInfo | null = null

  private constructor() {
    AppStorage.setOrCreate(StorageKeys.CURRENT_LYRIC, '')
    AppStorage.setOrCreate(StorageKeys.LYRIC_LINES, [])
    AppStorage.setOrCreate(StorageKeys.LYRIC_INDEX, -1)
  }

  static getInstance(): LyricService {
    if (!LyricService.instance) {
      LyricService.instance = new LyricService()
    }
    return LyricService.instance
  }

  async loadLyricForSong(song: SongInfo): Promise<void> {
    if (this.lastSong && this.lastSong.uri === song.uri) {
      return
    }

    this.lastSong = song
    this.currentLyricLines = []
    AppStorage.setOrCreate(StorageKeys.LYRIC_LINES, [])
    AppStorage.setOrCreate(StorageKeys.LYRIC_INDEX, -1)

    if (song.lyrics.length > 0) {
      this.setLyricContent(song.lyrics)
      return
    }

    const settings: LrcApiSettings = await this.lrcApiConfigService.loadSettings()
    if (settings.lyricsApiUrl.length === 0) {
      return
    }

    const fetchedLyric = await this.lrcApiService.fetchLyrics(
      settings.lyricsApiUrl,
      song.title,
      song.artist,
      song.album,
      settings.lyricsApiKey
    )

    if (fetchedLyric.length > 0) {
      this.setLyricContent(fetchedLyric)
    }
  }

  private setLyricContent(content: string): void {
    AppStorage.setOrCreate(StorageKeys.CURRENT_LYRIC, content)
    this.currentLyricLines = LyricParser.parse(content)
    AppStorage.setOrCreate(StorageKeys.LYRIC_LINES, this.currentLyricLines)
  }

  updatePosition(currentMs: number): void {
    if (this.currentLyricLines.length === 0) {
      return
    }

    const index = LyricParser.findCurrentIndex(this.currentLyricLines, currentMs)
    AppStorage.setOrCreate(StorageKeys.LYRIC_INDEX, index)
  }

  getLyricLines(): LyricLine[] {
    return this.currentLyricLines
  }

  clearLyric(): void {
    this.lastSong = null
    this.currentLyricLines = []
    AppStorage.setOrCreate(StorageKeys.CURRENT_LYRIC, '')
    AppStorage.setOrCreate(StorageKeys.LYRIC_LINES, [])
    AppStorage.setOrCreate(StorageKeys.LYRIC_INDEX, -1)
  }
}
