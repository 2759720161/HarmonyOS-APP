import { media } from '@kit.MediaKit'
import { avSession as AVSession } from '@kit.AVSessionKit'
import { fileIo } from '@kit.CoreFileKit'
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { SongInfo } from '../model/SongInfo'
import { PlayMode, StorageKeys } from '../common/Constants'
import { AudioScanner } from './AudioScanner'
import { AVSessionManager } from './AVSessionManager'
import { FavoriteManager } from './FavoriteManager'
import { LocalMusicLibrary } from './LocalMusicLibrary'
import { LrcApiService } from './LrcApiService'
import { PlaylistManager } from './PlaylistManager'
import { LyricService } from './LyricService'

interface PlaybackPersistedState {
  songId: string
  position: number
  playMode: number
}

export class PlayerService {
  private static instance: PlayerService | null = null
  private avPlayer: media.AVPlayer | null = null
  private songList: SongInfo[] = []
  private currentIndex: number = -1
  private playMode: PlayMode = PlayMode.SEQUENCE
  private playerState: string = 'idle'
  private avSessionMgr: AVSessionManager = new AVSessionManager()
  private playlistManager: PlaylistManager = PlaylistManager.getInstance()
  private favoriteManager: FavoriteManager = FavoriteManager.getInstance()
  private localMusicLibrary: LocalMusicLibrary = LocalMusicLibrary.getInstance()
  private currentFile: fileIo.File | null = null
  private lrcApiService: LrcApiService = LrcApiService.getInstance()
  private lyricService: LyricService = LyricService.getInstance()
  private preferences: preferences.Preferences | null = null
  private readonly stateKey: string = 'playback_state'
  private readonly saveThrottleMs: number = 3000
  private lastSaveTimestamp: number = 0
  private pendingSeekMs: number = 0

  private constructor() {}

  static getInstance(): PlayerService {
    if (!PlayerService.instance) {
      PlayerService.instance = new PlayerService()
    }
    return PlayerService.instance
  }

  async init(context: object): Promise<void> {
    if (this.avPlayer) {
      return
    }

    this.avPlayer = await media.createAVPlayer()
    this.bindPlayerEvents()
    await this.avSessionMgr.init(context, this)

    try {
      this.preferences = await preferences.getPreferences(context as common.UIAbilityContext, 'playback_state_store')
    } catch (error) {
      console.error('PlayerService', `Init preferences failed: ${JSON.stringify(error)}`)
    }

    AppStorage.setOrCreate(StorageKeys.IS_PLAYING, false)
    AppStorage.setOrCreate(StorageKeys.CURRENT_INDEX, -1)
    AppStorage.setOrCreate(StorageKeys.CURRENT_POSITION, 0)
    AppStorage.setOrCreate(StorageKeys.TOTAL_DURATION, 0)
    AppStorage.setOrCreate(StorageKeys.PLAY_MODE, PlayMode.SEQUENCE)
    AppStorage.setOrCreate(StorageKeys.COVER_VERSION, 0)
    AppStorage.setOrCreate(StorageKeys.CURRENT_TITLE, '')
    AppStorage.setOrCreate(StorageKeys.CURRENT_ARTIST, '')
    AppStorage.setOrCreate(StorageKeys.CURRENT_ALBUM, '')

    const savedState = await this.loadPersistedState()
    if (savedState) {
      this.playMode = savedState.playMode
      AppStorage.setOrCreate(StorageKeys.PLAY_MODE, savedState.playMode)
      this.avSessionMgr.updateLoopMode(savedState.playMode)
    }
  }

  private bindPlayerEvents(): void {
    if (!this.avPlayer) {
      return
    }

    this.avPlayer.on('stateChange', (state: string) => {
      this.playerState = state
      switch (state) {
        case 'initialized':
          this.avPlayer!.prepare()
          break
        case 'prepared':
          AppStorage.setOrCreate(StorageKeys.TOTAL_DURATION, this.avPlayer!.duration)
          if (this.pendingSeekMs > 0) {
            const seekTarget: number = this.pendingSeekMs
            this.pendingSeekMs = 0
            this.avPlayer!.seek(seekTarget, media.SeekMode.SEEK_PREV_SYNC)
            AppStorage.setOrCreate(StorageKeys.CURRENT_POSITION, seekTarget)
          }
          this.avPlayer!.play()
          break
        case 'playing':
          AppStorage.setOrCreate(StorageKeys.IS_PLAYING, true)
          this.avSessionMgr.updatePlaybackState(
            AVSession.PlaybackState.PLAYBACK_STATE_PLAY,
            AppStorage.get<number>(StorageKeys.CURRENT_POSITION) ?? 0
          )
          break
        case 'paused':
          AppStorage.setOrCreate(StorageKeys.IS_PLAYING, false)
          this.avSessionMgr.updatePlaybackState(
            AVSession.PlaybackState.PLAYBACK_STATE_PAUSE,
            AppStorage.get<number>(StorageKeys.CURRENT_POSITION) ?? 0
          )
          void this.savePersistedState()
          break
        case 'completed':
          void this.handleCompleted()
          break
        case 'error':
          AppStorage.setOrCreate(StorageKeys.IS_PLAYING, false)
          console.error('PlayerService', 'Playback state error, resetting player')
          void this.avPlayer?.reset()
          break
        default:
          break
      }
    })

    this.avPlayer.on('timeUpdate', (time: number) => {
      AppStorage.setOrCreate(StorageKeys.CURRENT_POSITION, time)
      this.avSessionMgr.updatePosition(time)
      this.lyricService.updatePosition(time)
      const now: number = Date.now()
      if (now - this.lastSaveTimestamp >= this.saveThrottleMs) {
        this.lastSaveTimestamp = now
        void this.savePersistedState()
      }
    })

    this.avPlayer.on('error', (err) => {
      console.error('PlayerService', `AVPlayer error: ${JSON.stringify(err)}`)
    })
  }

  setSongList(songs: SongInfo[]): void {
    this.songList = songs
    AppStorage.setOrCreate(StorageKeys.SONG_COUNT, songs.length)
  }

  getSongList(): SongInfo[] {
    const playlist = this.playlistManager.getPlaylist()
    if (playlist.length > 0) {
      this.songList = playlist
      AppStorage.setOrCreate(StorageKeys.SONG_COUNT, playlist.length)
    }
    return this.songList
  }

  getCurrentSong(): SongInfo | null {
    if (this.currentIndex >= 0 && this.currentIndex < this.songList.length) {
      return this.songList[this.currentIndex]
    }
    return null
  }

  getCurrentIndex(): number {
    return this.currentIndex
  }

  async playAt(index: number, startPositionMs: number = 0): Promise<void> {
    if (index < 0 || index >= this.songList.length || !this.avPlayer) {
      return
    }

    const song = this.songList[index]
    let nextFile: fileIo.File | null = null

    try {
      nextFile = fileIo.openSync(song.uri, fileIo.OpenMode.READ_ONLY)
    } catch (error) {
      console.error('PlayerService', `Open song failed for ${song.uri}: ${JSON.stringify(error)}`)
      return
    }

    try {
      if (this.currentFile) {
        fileIo.closeSync(this.currentFile)
        this.currentFile = null
      }

      if (this.playerState !== 'idle' && this.playerState !== 'released') {
        await this.avPlayer.reset()
      }

      this.currentFile = nextFile
      this.pendingSeekMs = startPositionMs > 0 ? startPositionMs : 0
      this.avPlayer.fdSrc = { fd: nextFile.fd, offset: 0, length: -1 }
    } catch (error) {
      if (nextFile) {
        fileIo.closeSync(nextFile)
      }
      this.currentFile = null
      this.pendingSeekMs = 0
      console.error('PlayerService', `Prepare song failed for ${song.uri}: ${JSON.stringify(error)}`)
      return
    }

    this.currentIndex = index
    AppStorage.setOrCreate(StorageKeys.CURRENT_INDEX, index)
    AppStorage.setOrCreate(StorageKeys.CURRENT_POSITION, startPositionMs > 0 ? startPositionMs : 0)
    AppStorage.setOrCreate(StorageKeys.CURRENT_TITLE, song.title)
    AppStorage.setOrCreate(StorageKeys.CURRENT_ARTIST, song.artist)
    AppStorage.setOrCreate(StorageKeys.CURRENT_ALBUM, song.album)

    void this.refreshCurrentCover(song)
    void this.lyricService.loadLyricForSong(song)
    this.avSessionMgr.updateMetadata(song)
    void this.savePersistedState()
  }

  private async refreshCurrentCover(song: SongInfo): Promise<void> {
    if (song.coverUri.length > 0) {
      const onlineCover = await this.lrcApiService.loadCoverFromUrl(song.coverUri)
      if (onlineCover) {
        await AudioScanner.updateCurrentCoverFromPixelMap(onlineCover)
        return
      }
    }

    await AudioScanner.updateCurrentCover(song.uri)
  }

  async pause(): Promise<void> {
    if (this.avPlayer && this.playerState === 'playing') {
      await this.avPlayer.pause()
    }
  }

  async resume(): Promise<void> {
    if (this.avPlayer && this.playerState === 'paused') {
      await this.avPlayer.play()
    }
  }

  async togglePlayPause(): Promise<void> {
    if (this.playerState === 'playing') {
      await this.pause()
    } else if (this.playerState === 'paused' || this.playerState === 'prepared') {
      await this.resume()
    } else if (this.currentIndex >= 0) {
      const startPos: number = this.pendingSeekMs > 0
        ? this.pendingSeekMs
        : (AppStorage.get<number>(StorageKeys.CURRENT_POSITION) ?? 0)
      await this.playAt(this.currentIndex, startPos)
    }
  }

  async next(): Promise<void> {
    await this.playAt(this.getNextIndex())
  }

  async prev(): Promise<void> {
    await this.playAt(this.getPrevIndex())
  }

  async seekTo(ms: number): Promise<void> {
    if (this.currentIndex < 0) {
      return
    }

    const duration: number = AppStorage.get<number>(StorageKeys.TOTAL_DURATION) ?? 0
    let nextPosition: number = Math.max(0, ms)
    if (duration > 0 && nextPosition > duration) {
      nextPosition = duration
    }

    this.pendingSeekMs = nextPosition
    AppStorage.setOrCreate(StorageKeys.CURRENT_POSITION, nextPosition)
    this.lyricService.updatePosition(nextPosition)
    this.avSessionMgr.updatePosition(nextPosition)
    void this.savePersistedState()

    if (!this.avPlayer) {
      return
    }

    if (this.playerState === 'playing' ||
      this.playerState === 'paused' ||
      this.playerState === 'prepared') {
      await this.avPlayer.seek(nextPosition, media.SeekMode.SEEK_PREV_SYNC)
      this.pendingSeekMs = 0
    }
  }

  async deleteCurrentSong(deleteFile: boolean = false): Promise<boolean> {
    const song: SongInfo | null = this.getCurrentSong()
    if (!song) {
      return false
    }

    const removedIndex: number = this.currentIndex
    const shouldContinuePlaying: boolean = this.playerState === 'playing'
    await this.resetPlaybackForRemoval()

    this.playlistManager.removeSong(song.id)
    void this.favoriteManager.removeFromFavorites(song.id)

    if (deleteFile) {
      this.localMusicLibrary.deleteImportedFile(song.uri)
    }

    this.songList = this.playlistManager.getPlaylist()
    AppStorage.setOrCreate(StorageKeys.SONG_COUNT, this.songList.length)

    if (this.songList.length === 0) {
      await this.clearCurrentPlaybackState()
      await this.clearPersistedState()
      return true
    }

    const nextIndex: number = Math.min(removedIndex, this.songList.length - 1)
    if (shouldContinuePlaying) {
      await this.playAt(nextIndex)
    } else {
      this.selectSongWithoutPlayback(nextIndex)
    }
    return true
  }

  private async resetPlaybackForRemoval(): Promise<void> {
    this.pendingSeekMs = 0
    AppStorage.setOrCreate(StorageKeys.IS_PLAYING, false)

    if (this.avPlayer && this.playerState !== 'idle' && this.playerState !== 'released') {
      try {
        await this.avPlayer.reset()
      } catch (error) {
        console.error('PlayerService', `Reset player before delete failed: ${JSON.stringify(error)}`)
      }
    }

    if (this.currentFile) {
      try {
        fileIo.closeSync(this.currentFile)
      } catch (_) {
      }
      this.currentFile = null
    }
  }

  private selectSongWithoutPlayback(index: number): void {
    if (index < 0 || index >= this.songList.length) {
      return
    }

    const song: SongInfo = this.songList[index]
    this.currentIndex = index
    this.pendingSeekMs = 0

    AppStorage.setOrCreate(StorageKeys.CURRENT_INDEX, index)
    AppStorage.setOrCreate(StorageKeys.CURRENT_POSITION, 0)
    AppStorage.setOrCreate(StorageKeys.TOTAL_DURATION, song.duration)
    AppStorage.setOrCreate(StorageKeys.CURRENT_TITLE, song.title)
    AppStorage.setOrCreate(StorageKeys.CURRENT_ARTIST, song.artist)
    AppStorage.setOrCreate(StorageKeys.CURRENT_ALBUM, song.album)
    AppStorage.setOrCreate(StorageKeys.IS_PLAYING, false)

    void this.refreshCurrentCover(song)
    void this.lyricService.loadLyricForSong(song)
    this.avSessionMgr.updateMetadata(song)
    this.avSessionMgr.updatePlaybackState(AVSession.PlaybackState.PLAYBACK_STATE_PAUSE, 0)
    void this.savePersistedState()
  }

  private async clearCurrentPlaybackState(): Promise<void> {
    this.currentIndex = -1
    this.pendingSeekMs = 0

    AppStorage.setOrCreate(StorageKeys.CURRENT_INDEX, -1)
    AppStorage.setOrCreate(StorageKeys.CURRENT_POSITION, 0)
    AppStorage.setOrCreate(StorageKeys.TOTAL_DURATION, 0)
    AppStorage.setOrCreate(StorageKeys.CURRENT_TITLE, '')
    AppStorage.setOrCreate(StorageKeys.CURRENT_ARTIST, '')
    AppStorage.setOrCreate(StorageKeys.CURRENT_ALBUM, '')
    AppStorage.setOrCreate(StorageKeys.IS_PLAYING, false)

    this.lyricService.clearLyric()
    await AudioScanner.updateCurrentCoverFromPixelMap(null)
    await this.avSessionMgr.updatePlaybackState(AVSession.PlaybackState.PLAYBACK_STATE_PAUSE, 0)
  }

  setPlayMode(mode: PlayMode): void {
    this.playMode = mode
    AppStorage.setOrCreate(StorageKeys.PLAY_MODE, mode)
    this.avSessionMgr.updateLoopMode(mode)
    void this.savePersistedState()
  }

  private getNextIndex(): number {
    if (this.songList.length === 0) {
      return 0
    }
    if (this.playMode === PlayMode.SHUFFLE) {
      return Math.floor(Math.random() * this.songList.length)
    }
    return (this.currentIndex + 1) % this.songList.length
  }

  private getPrevIndex(): number {
    if (this.songList.length === 0) {
      return 0
    }
    if (this.playMode === PlayMode.SHUFFLE) {
      return Math.floor(Math.random() * this.songList.length)
    }
    return (this.currentIndex - 1 + this.songList.length) % this.songList.length
  }

  private async handleCompleted(): Promise<void> {
    AppStorage.setOrCreate(StorageKeys.IS_PLAYING, false)
    if (this.playMode === PlayMode.SINGLE) {
      await this.playAt(this.currentIndex)
    } else {
      await this.next()
    }
  }

  async release(): Promise<void> {
    await this.savePersistedState()
    this.avSessionMgr.release()
    if (this.currentFile) {
      fileIo.closeSync(this.currentFile)
      this.currentFile = null
    }
    if (this.avPlayer) {
      await this.avPlayer.release()
      this.avPlayer = null
    }
  }

  restoreFromPersistence(savedState: PlaybackPersistedState): void {
    if (!savedState || savedState.songId.length === 0 || this.songList.length === 0) {
      return
    }

    const index: number = this.songList.findIndex((song: SongInfo) => song.id === savedState.songId)
    if (index < 0) {
      console.info('PlayerService', `Saved song id not found in playlist: ${savedState.songId}`)
      return
    }

    const song: SongInfo = this.songList[index]
    this.currentIndex = index
    this.pendingSeekMs = savedState.position > 0 ? savedState.position : 0

    AppStorage.setOrCreate(StorageKeys.CURRENT_INDEX, index)
    AppStorage.setOrCreate(StorageKeys.CURRENT_POSITION, this.pendingSeekMs)
    AppStorage.setOrCreate(StorageKeys.TOTAL_DURATION, song.duration)
    AppStorage.setOrCreate(StorageKeys.CURRENT_TITLE, song.title)
    AppStorage.setOrCreate(StorageKeys.CURRENT_ARTIST, song.artist)
    AppStorage.setOrCreate(StorageKeys.CURRENT_ALBUM, song.album)

    void this.refreshCurrentCover(song)
    void this.lyricService.loadLyricForSong(song)
    this.avSessionMgr.updateMetadata(song)
    console.info('PlayerService', `Restored song "${song.title}" at ${this.pendingSeekMs}ms`)
  }

  async loadPersistedState(): Promise<PlaybackPersistedState | null> {
    if (!this.preferences) {
      return null
    }

    try {
      const raw = await this.preferences.get(this.stateKey, '') as string
      if (!raw || raw.length === 0) {
        return null
      }
      const parsed = JSON.parse(raw) as PlaybackPersistedState
      if (!parsed || typeof parsed.songId !== 'string') {
        return null
      }
      return {
        songId: parsed.songId,
        position: typeof parsed.position === 'number' ? parsed.position : 0,
        playMode: typeof parsed.playMode === 'number' ? parsed.playMode : PlayMode.SEQUENCE
      }
    } catch (error) {
      console.error('PlayerService', `Load persisted state failed: ${JSON.stringify(error)}`)
      return null
    }
  }

  private async savePersistedState(): Promise<void> {
    if (!this.preferences) {
      return
    }

    const song: SongInfo | null = this.getCurrentSong()
    if (!song) {
      return
    }

    const state: PlaybackPersistedState = {
      songId: song.id,
      position: AppStorage.get<number>(StorageKeys.CURRENT_POSITION) ?? 0,
      playMode: this.playMode
    }

    try {
      await this.preferences.put(this.stateKey, JSON.stringify(state))
      await this.preferences.flush()
    } catch (error) {
      console.error('PlayerService', `Save persisted state failed: ${JSON.stringify(error)}`)
    }
  }

  private async clearPersistedState(): Promise<void> {
    if (!this.preferences) {
      return
    }

    try {
      await this.preferences.put(this.stateKey, '')
      await this.preferences.flush()
    } catch (error) {
      console.error('PlayerService', `Clear persisted state failed: ${JSON.stringify(error)}`)
    }
  }
}
