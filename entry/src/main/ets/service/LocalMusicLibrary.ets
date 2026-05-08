import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { SongInfo } from '../model/SongInfo'

export class LocalMusicLibrary {
  private static instance: LocalMusicLibrary | null = null
  private readonly libraryDirName: string = 'imported_audio'

  private constructor() {}

  static getInstance(): LocalMusicLibrary {
    if (!LocalMusicLibrary.instance) {
      LocalMusicLibrary.instance = new LocalMusicLibrary()
    }
    return LocalMusicLibrary.instance
  }

  async importUris(
    context: common.UIAbilityContext,
    sourceUris: string[],
    onProgress?: (current: number, total: number) => void
  ): Promise<string[]> {
    if (!sourceUris || sourceUris.length === 0) {
      return []
    }

    const importedUris: string[] = []
    const total: number = sourceUris.length
    for (let index = 0; index < sourceUris.length; index++) {
      const localUri = this.ensureLocalUriSync(context, sourceUris[index])
      if (localUri) {
        importedUris.push(localUri)
      }
      if (onProgress) {
        onProgress(index + 1, total)
      }
    }

    console.info('LocalMusicLibrary', `Imported ${importedUris.length}/${total} audio files`)
    return importedUris
  }

  async migrateSongs(
    context: common.UIAbilityContext,
    songs: SongInfo[]
  ): Promise<SongInfo[]> {
    if (!songs || songs.length === 0) {
      return []
    }

    const migratedSongs: SongInfo[] = []
    let migratedCount: number = 0

    for (const song of songs) {
      const localUri = this.ensureLocalUriSync(context, song.uri)
      if (localUri && localUri !== song.uri) {
        migratedSongs.push(new SongInfo(
          localUri,
          song.title,
          song.artist,
          song.album,
          song.duration,
          localUri,
          song.coverUri,
          song.sampleRate,
          song.bitrate,
          song.mimeType,
          song.codecMimeType,
          song.lyrics
        ))
        migratedCount++
      } else {
        migratedSongs.push(song)
      }
    }

    if (migratedCount > 0) {
      console.info('LocalMusicLibrary', `Migrated ${migratedCount} songs into sandbox storage`)
    }

    return migratedSongs
  }

  isLocalUri(uri: string): boolean {
    return !!uri && !uri.startsWith('file://')
  }

  deleteImportedFile(uri: string): boolean {
    if (!this.isImportedFile(uri)) {
      return false
    }

    try {
      if (!this.fileExists(uri)) {
        return false
      }
      fileIo.unlinkSync(uri)
      return true
    } catch (error) {
      console.error('LocalMusicLibrary', `Delete imported audio failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  private isImportedFile(uri: string): boolean {
    if (!uri || uri.length === 0) {
      return false
    }
    return uri.includes(`/${this.libraryDirName}/`) || uri.includes(`\\${this.libraryDirName}\\`)
  }

  private ensureLocalUriSync(context: common.UIAbilityContext, sourceUri: string): string | null {
    if (!sourceUri) {
      return null
    }

    if (this.isLocalUri(sourceUri)) {
      return sourceUri
    }

    const destinationPath = this.buildDestinationPath(context, sourceUri)
    if (this.fileExists(destinationPath)) {
      return destinationPath
    }

    let sourceFile: fileIo.File | null = null
    try {
      sourceFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY)
      fileIo.copyFileSync(sourceFile.fd, destinationPath)
      return this.fileExists(destinationPath) ? destinationPath : null
    } catch (error) {
      console.error('LocalMusicLibrary', `Copy audio failed: ${JSON.stringify(error)}`)
      this.deleteIfExists(destinationPath)
      return null
    } finally {
      if (sourceFile) {
        fileIo.closeSync(sourceFile)
      }
    }
  }

  private buildDestinationPath(context: common.UIAbilityContext, sourceUri: string): string {
    const libraryDir = this.ensureLibraryDir(context)
    const fileName = this.buildFileName(sourceUri)
    return `${libraryDir}/${fileName}`
  }

  private ensureLibraryDir(context: common.UIAbilityContext): string {
    const libraryDir = `${context.filesDir}/${this.libraryDirName}`
    if (!this.fileExists(libraryDir)) {
      fileIo.mkdirSync(libraryDir)
    }
    return libraryDir
  }

  private fileExists(path: string): boolean {
    try {
      fileIo.statSync(path)
      return true
    } catch (_) {
      return false
    }
  }

  private deleteIfExists(path: string): void {
    try {
      if (this.fileExists(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_) {
    }
  }

  private buildFileName(sourceUri: string): string {
    const decodedFileName = this.getDecodedFileName(sourceUri)
    const extension = this.getExtension(decodedFileName)
    const baseName = decodedFileName.substring(0, decodedFileName.length - extension.length)
    const safeBaseName = this.sanitizeFileName(baseName) || 'track'
    return `${this.hashString(sourceUri)}_${safeBaseName}${extension}`
  }

  private getDecodedFileName(sourceUri: string): string {
    const rawFileName = sourceUri.split('/').pop() || 'track.mp3'
    try {
      return decodeURIComponent(rawFileName)
    } catch (_) {
      return rawFileName
    }
  }

  private getExtension(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.')
    if (dotIndex === -1) {
      return ''
    }
    return fileName.substring(dotIndex)
  }

  private sanitizeFileName(fileName: string): string {
    return fileName
      .replace(/[<>:"/\\|?*\u0000-\u001F]/g, '_')
      .replace(/\s+/g, ' ')
      .trim()
  }

  private hashString(value: string): string {
    let hash = 2166136261
    for (let index = 0; index < value.length; index++) {
      hash ^= value.charCodeAt(index)
      hash +=
        (hash << 1) +
        (hash << 4) +
        (hash << 7) +
        (hash << 8) +
        (hash << 24)
    }
    return (hash >>> 0).toString(16)
  }
}
