import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { SongInfo } from '../model/SongInfo'
import { StorageKeys } from '../common/Constants'

class FavoriteRecord {
  song_id: string = ''
  title: string = ''
  artist: string = ''
  album: string = ''
  duration: number = 0
  uri: string = ''
  cover_uri: string = ''
  created_at: number = 0

  static fromSongInfo(song: SongInfo): FavoriteRecord {
    const record = new FavoriteRecord()
    record.song_id = song.id
    record.title = song.title
    record.artist = song.artist
    record.album = song.album
    record.duration = song.duration
    record.uri = song.uri
    record.cover_uri = song.coverUri
    record.created_at = Date.now()
    return record
  }

  static toSongInfo(record: FavoriteRecord): SongInfo {
    return new SongInfo(
      record.song_id,
      record.title,
      record.artist,
      record.album,
      record.duration,
      record.uri,
      record.cover_uri
    )
  }
}

export class FavoriteManager {
  private static instance: FavoriteManager | null = null
  private store: relationalStore.RdbStore | null = null
  private favoriteIds: Set<string> = new Set()
  private context: common.UIAbilityContext | null = null

  private readonly dbName: string = 'favorite_store.db'
  private readonly tableName: string = 'favorites'
  private readonly dbConfig: relationalStore.StoreConfig = {
    name: 'favorite_store.db',
    securityLevel: relationalStore.SecurityLevel.S1
  }

  private constructor() {}

  static getInstance(): FavoriteManager {
    if (!FavoriteManager.instance) {
      FavoriteManager.instance = new FavoriteManager()
    }
    return FavoriteManager.instance
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    try {
      this.context = context
      this.store = await relationalStore.getRdbStore(context, this.dbConfig)

      const createTableSql = `CREATE TABLE IF NOT EXISTS ${this.tableName} (` +
        `song_id TEXT PRIMARY KEY, ` +
        `title TEXT NOT NULL, ` +
        `artist TEXT NOT NULL, ` +
        `album TEXT, ` +
        `duration INTEGER, ` +
        `uri TEXT NOT NULL, ` +
        `cover_uri TEXT, ` +
        `created_at INTEGER NOT NULL)`

      await this.store.executeSql(createTableSql)

      const createIndexSql = `CREATE INDEX IF NOT EXISTS idx_favorite_created_at ` +
        `ON ${this.tableName} (created_at DESC)`

      await this.store.executeSql(createIndexSql)

      await this.loadAllFavoriteIds()
      this.syncToAppStorage()

      console.info('FavoriteManager', 'Init success')
    } catch (error) {
      console.error('FavoriteManager', `Init failed: ${JSON.stringify(error)}`)
    }
  }

  private async loadAllFavoriteIds(): Promise<void> {
    if (!this.store) {
      return
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.tableName)
      const resultSet = await this.store.query(predicates, ['song_id'])

      this.favoriteIds.clear()
      while (resultSet.goToNextRow()) {
        const songId = resultSet.getString(0)
        this.favoriteIds.add(songId)
      }
      resultSet.close()
    } catch (error) {
      console.error('FavoriteManager', `Load favorite ids failed: ${JSON.stringify(error)}`)
    }
  }

  private syncToAppStorage(): void {
    const idsArray: string[] = []
    this.favoriteIds.forEach((id: string) => {
      idsArray.push(id)
    })
    AppStorage.setOrCreate(StorageKeys.FAVORITE_IDS, JSON.stringify(idsArray))
    AppStorage.setOrCreate(StorageKeys.FAVORITE_COUNT, idsArray.length)
  }

  async toggleFavorite(song: SongInfo): Promise<boolean> {
    if (!this.store) {
      return false
    }

    try {
      if (this.favoriteIds.has(song.id)) {
        const predicates = new relationalStore.RdbPredicates(this.tableName)
        predicates.equalTo('song_id', song.id)
        const deletedRows = await this.store.delete(predicates)
        if (deletedRows > 0) {
          this.favoriteIds.delete(song.id)
        }
      } else {
        const record = FavoriteRecord.fromSongInfo(song)
        const valueBucket: relationalStore.ValuesBucket = {
          'song_id': record.song_id,
          'title': record.title,
          'artist': record.artist,
          'album': record.album,
          'duration': record.duration,
          'uri': record.uri,
          'cover_uri': record.cover_uri,
          'created_at': record.created_at
        }
        await this.store.insert(this.tableName, valueBucket)
        this.favoriteIds.add(song.id)
      }

      this.syncToAppStorage()
      return this.favoriteIds.has(song.id)
    } catch (error) {
      console.error('FavoriteManager', `Toggle favorite failed: ${JSON.stringify(error)}`)
      return this.favoriteIds.has(song.id)
    }
  }

  isFavorite(songId: string): boolean {
    return this.favoriteIds.has(songId)
  }

  async getFavoriteList(): Promise<SongInfo[]> {
    if (!this.store) {
      return []
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.tableName)
      predicates.orderByDesc('created_at')
      const resultSet = await this.store.query(predicates)

      const list: SongInfo[] = []
      while (resultSet.goToNextRow()) {
        const record = new FavoriteRecord()
        record.song_id = resultSet.getString(0)
        record.title = resultSet.getString(1)
        record.artist = resultSet.getString(2)
        record.album = resultSet.getString(3)
        record.duration = resultSet.getLong(4)
        record.uri = resultSet.getString(5)
        record.cover_uri = resultSet.getString(6)
        record.created_at = resultSet.getLong(7)
        list.push(FavoriteRecord.toSongInfo(record))
      }
      resultSet.close()
      return list
    } catch (error) {
      console.error('FavoriteManager', `Get favorite list failed: ${JSON.stringify(error)}`)
      return []
    }
  }

  async getFavoriteCount(): Promise<number> {
    return this.favoriteIds.size
  }

  async removeFromFavorites(songId: string): Promise<void> {
    if (!this.store) {
      return
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.tableName)
      predicates.equalTo('song_id', songId)
      await this.store.delete(predicates)
      this.favoriteIds.delete(songId)
      this.syncToAppStorage()
    } catch (error) {
      console.error('FavoriteManager', `Remove from favorites failed: ${JSON.stringify(error)}`)
    }
  }

  async syncWithPlaylist(playlist: SongInfo[]): Promise<void> {
    if (!this.store || this.favoriteIds.size === 0) {
      return
    }

    const playlistIds = new Set(playlist.map((song: SongInfo) => song.id))
    const toRemove: string[] = []
    this.favoriteIds.forEach((id: string) => {
      if (!playlistIds.has(id)) {
        toRemove.push(id)
      }
    })

    if (toRemove.length === 0) {
      return
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.tableName)
      predicates.in('song_id', toRemove)
      await this.store.delete(predicates)

      for (const id of toRemove) {
        this.favoriteIds.delete(id)
      }
      this.syncToAppStorage()
      console.info('FavoriteManager', `Synced favorites, removed ${toRemove.length} orphaned items`)
    } catch (error) {
      console.error('FavoriteManager', `Sync with playlist failed: ${JSON.stringify(error)}`)
    }
  }

  getFavoriteIds(): Set<string> {
    return new Set(this.favoriteIds)
  }
}
