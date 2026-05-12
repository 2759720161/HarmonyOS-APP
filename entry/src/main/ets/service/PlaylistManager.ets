import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { SongInfo } from '../model/SongInfo'
import { MetadataParser } from './MetadataParser'
import { Colors } from '../common/Constants'
import { PermissionManager } from './PermissionManager'

export class PlaylistManager {
  private static instance: PlaylistManager | null = null
  private playlist: SongInfo[] = []
  private preferences: preferences.Preferences | null = null
  private readonly playlistKey: string = 'playlist'
  private metadataParser: MetadataParser = MetadataParser.getInstance()
  private permissionManager: PermissionManager = PermissionManager.getInstance()

  private constructor() {}

  static getInstance(): PlaylistManager {
    if (!PlaylistManager.instance) {
      PlaylistManager.instance = new PlaylistManager()
    }
    return PlaylistManager.instance
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    try {
      this.preferences = await preferences.getPreferences(context, 'playlist_store')
      await this.loadPlaylist()
    } catch (error) {
      console.error('PlaylistManager', `Init failed: ${JSON.stringify(error)}`)
    }
  }

  addSongs(songs: SongInfo[]): void {
    if (!songs || songs.length === 0) {
      return
    }

    const existingIds = new Set(this.playlist.map((song: SongInfo) => song.id))
    const newSongs = songs.filter((song: SongInfo) => !existingIds.has(song.id))
    if (newSongs.length === 0) {
      return
    }

    this.playlist.push(...newSongs)
    console.info('PlaylistManager', `Added ${newSongs.length} songs, total ${this.playlist.length}`)
    void this.savePlaylist()
  }

  removeSong(songId: string): void {
    const index = this.playlist.findIndex((song: SongInfo) => song.id === songId)
    if (index === -1) {
      return
    }

    this.playlist.splice(index, 1)
    console.info('PlaylistManager', `Removed song, total ${this.playlist.length}`)
    void this.savePlaylist()
  }

  clearPlaylist(): void {
    this.playlist = []
    console.info('PlaylistManager', 'Cleared playlist')
    void this.savePlaylist()
  }

  getPlaylist(): SongInfo[] {
    return [...this.playlist]
  }

  getSize(): number {
    return this.playlist.length
  }

  getSongAt(index: number): SongInfo | null {
    if (index >= 0 && index < this.playlist.length) {
      return this.playlist[index]
    }
    return null
  }

  persistPlaylist(): void {
    void this.savePlaylist()
  }

  findIndex(songId: string): number {
    return this.playlist.findIndex((song: SongInfo) => song.id === songId)
  }

  searchSongs(keyword: string): SongInfo[] {
    if (!keyword || keyword.trim().length === 0) {
      return [...this.playlist]
    }
    const lowerKeyword = keyword.toLowerCase()
    return this.playlist.filter((song: SongInfo) => {
      return song.title.toLowerCase().includes(lowerKeyword) ||
        song.artist.toLowerCase().includes(lowerKeyword)
    })
  }

  private async savePlaylist(): Promise<void> {
    if (!this.preferences) {
      console.warn('PlaylistManager', 'Preferences not initialized')
      return
    }

    try {
      await this.preferences.put(this.playlistKey, JSON.stringify(this.playlist))
      await this.preferences.flush()
      console.info('PlaylistManager', 'Playlist saved')
    } catch (error) {
      console.error('PlaylistManager', `Save playlist failed: ${JSON.stringify(error)}`)
    }
  }

  private async loadPlaylist(): Promise<void> {
    if (!this.preferences) {
      console.warn('PlaylistManager', 'Preferences not initialized')
      return
    }

    try {
      const playlistJson = await this.preferences.get(this.playlistKey, '[]') as string
      const loadedPlaylist = JSON.parse(playlistJson) as SongInfo[]
      const normalizedPlaylist = this.normalizePlaylist(loadedPlaylist)

      if (normalizedPlaylist.length === 0) {
        this.playlist = []
        console.info('PlaylistManager', 'Playlist loaded: 0 songs')
        return
      }

      await this.activatePlaylistPermissions(normalizedPlaylist)

      const finalPlaylist = await this.hydrateMissingMetadata(normalizedPlaylist)
      this.playlist = finalPlaylist

      if (this.hasPlaylistChanged(normalizedPlaylist, finalPlaylist)) {
        await this.savePlaylist()
      }

      console.info('PlaylistManager', `Playlist loaded: ${this.playlist.length} songs`)
    } catch (error) {
      console.error('PlaylistManager', `Load playlist failed: ${JSON.stringify(error)}`)
      this.playlist = []
    }
  }

  private hasPlaylistChanged(previous: SongInfo[], next: SongInfo[]): boolean {
    return JSON.stringify(previous) !== JSON.stringify(next)
  }

  private async activatePlaylistPermissions(playlist: SongInfo[]): Promise<void> {
    const externalUris = playlist
      .map((song: SongInfo) => song.uri)
      .filter((uri: string) => uri.startsWith('file://'))

    if (externalUris.length === 0) {
      return
    }

    await this.permissionManager.activatePermissions(externalUris)
  }

  private shouldUseFilenameMetadata(title: string, artist: string, parsedArtist: string): boolean {
    return parsedArtist !== Colors.UNKNOWN_ARTIST &&
      (artist.length === 0 ||
        artist === Colors.UNKNOWN_ARTIST ||
        artist === 'Unknown Artist' ||
        title.includes('-'))
  }

  private normalizePlaylist(rawPlaylist: SongInfo[]): SongInfo[] {
    if (!Array.isArray(rawPlaylist)) {
      return []
    }

    return rawPlaylist
      .filter((song: SongInfo) => !!song && typeof song.uri === 'string' && song.uri.length > 0)
      .map((song: SongInfo) => new SongInfo(
        typeof song.id === 'string' && song.id.length > 0 ? song.id : song.uri,
        this.metadataParser.normalizeTitle(typeof song.title === 'string' ? song.title : Colors.UNKNOWN_TITLE),
        typeof song.artist === 'string' ? song.artist : Colors.UNKNOWN_ARTIST,
        typeof song.album === 'string' ? song.album : '未知专辑',
        typeof song.duration === 'number' ? song.duration : 0,
        song.uri,
        typeof song.coverUri === 'string' ? song.coverUri : '',
        typeof song.sampleRate === 'number' ? song.sampleRate : 0,
        typeof song.bitrate === 'number' ? song.bitrate : 0,
        typeof song.mimeType === 'string' ? song.mimeType : '',
        typeof song.codecMimeType === 'string' ? song.codecMimeType : '',
        typeof song.lyrics === 'string' ? song.lyrics : ''
      ))
  }

  private async hydrateMissingMetadata(playlist: SongInfo[]): Promise<SongInfo[]> {
    const hydratedPlaylist: SongInfo[] = []
    let hasUpdates: boolean = false

    for (const song of playlist) {
      if (!this.needsMetadataRefresh(song)) {
        hydratedPlaylist.push(song)
        continue
      }

      const parsedSong = await this.metadataParser.parseMetadata(song.uri)
      if (!parsedSong) {
        hydratedPlaylist.push(song)
        continue
      }

      hydratedPlaylist.push(new SongInfo(
        song.id,
        this.metadataParser.normalizeTitle(parsedSong.title || song.title),
        parsedSong.artist || song.artist,
        parsedSong.album || song.album,
        parsedSong.duration > 0 ? parsedSong.duration : song.duration,
        song.uri,
        song.coverUri,
        parsedSong.sampleRate,
        parsedSong.bitrate,
        parsedSong.mimeType,
        parsedSong.codecMimeType,
        song.lyrics
      ))
      hasUpdates = true
    }

    if (hasUpdates) {
      console.info('PlaylistManager', 'Backfilled missing audio metadata for playlist')
    }

    return hydratedPlaylist
  }

  private needsMetadataRefresh(song: SongInfo): boolean {
    const filenameParsed = this.metadataParser.resolveTitleArtistFromFilename(song.uri)
    const hasFilenameMetadata = filenameParsed.artist !== Colors.UNKNOWN_ARTIST
    const shouldUseFilename = this.shouldUseFilenameMetadata(song.title, song.artist, filenameParsed.artist)
    const looksReversed = hasFilenameMetadata &&
      song.title === filenameParsed.artist &&
      song.artist === filenameParsed.title

    return song.sampleRate <= 0 ||
      song.bitrate <= 0 ||
      song.mimeType.length === 0 ||
      song.codecMimeType.length === 0 ||
      song.artist.length === 0 ||
      song.artist === Colors.UNKNOWN_ARTIST ||
      song.artist === 'Unknown Artist' ||
      song.title.includes('-') ||
      shouldUseFilename ||
      looksReversed ||
      this.metadataParser.normalizeTitle(song.title) !== song.title
  }
}
