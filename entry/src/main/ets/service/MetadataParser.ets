import { media } from '@kit.MediaKit'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { SongInfo } from '../model/SongInfo'
import { Colors } from '../common/Constants'
import { PermissionManager } from './PermissionManager'

export interface FilenameTitleArtist {
  title: string
  artist: string
}

export class MetadataParser {
  private static instance: MetadataParser | null = null
  private readonly trackBitrateKey: string = 'bitrate'
  private readonly trackSampleRateKey: string = 'sample_rate'
  private readonly trackMimeTypeKey: string = 'mime_type'
  private readonly trackCodecMimeKey: string = 'codec_mime'
  private permissionManager: PermissionManager = PermissionManager.getInstance()

  private constructor() {}

  static getInstance(): MetadataParser {
    if (!MetadataParser.instance) {
      MetadataParser.instance = new MetadataParser()
    }
    return MetadataParser.instance
  }

  async parseMetadata(uri: string): Promise<SongInfo | null> {
    let extractor: media.AVMetadataExtractor | null = null
    let fileHandle: fileIo.File | null = null

    try {
      extractor = await media.createAVMetadataExtractor()
      fileHandle = await this.permissionManager.openReadableFile(uri)
      if (!fileHandle) {
        return null
      }
      extractor.fdSrc = { fd: fileHandle.fd, offset: 0, length: -1 }

      const metadata = await extractor.fetchMetadata()
      const audioTrack = this.findAudioTrack(metadata)
      const filenameParsed = this.parseFilenameToTitleArtist(uri)

      let title: string
      let artist: string

      if (metadata.title && metadata.title.length > 0) {
        const normalizedMetadataTitle = this.normalizeTitle(metadata.title)
        const metadataArtist = metadata.artist || ''
        if (metadataArtist.length === 0 && filenameParsed.artist !== Colors.UNKNOWN_ARTIST) {
          title = filenameParsed.title
          artist = filenameParsed.artist
        } else {
          title = normalizedMetadataTitle
          artist = metadataArtist.length > 0 ? metadataArtist : filenameParsed.artist
        }
      } else {
        title = filenameParsed.title
        artist = filenameParsed.artist
      }

      return new SongInfo(
        uri,
        title,
        artist,
        metadata.album || '未知专辑',
        this.parseNumber(metadata.duration),
        uri,
        '',
        this.resolveSampleRate(metadata, audioTrack),
        this.resolveBitrate(audioTrack),
        metadata.mimeType || this.getTrackString(audioTrack, this.trackMimeTypeKey),
        this.getTrackString(audioTrack, this.trackCodecMimeKey)
      )
    } catch (error) {
      console.error('MetadataParser', `Parse metadata failed: ${JSON.stringify(error)}`)
      return null
    } finally {
      if (extractor) {
        extractor.release()
      }
      if (fileHandle) {
        fileIo.closeSync(fileHandle)
      }
    }
  }

  async parseMetadataBatch(
    uris: string[],
    onProgress?: (current: number, total: number) => void
  ): Promise<SongInfo[]> {
    if (!uris || uris.length === 0) {
      return []
    }

    const songList: SongInfo[] = []
    const total: number = uris.length
    const concurrency: number = 5

    for (let index = 0; index < uris.length; index += concurrency) {
      const batch = uris.slice(index, Math.min(index + concurrency, uris.length))
      const results = await Promise.all(batch.map((uri: string) => this.parseMetadata(uri)))

      for (const result of results) {
        if (result) {
          songList.push(result)
        }
      }

      if (onProgress) {
        onProgress(Math.min(index + concurrency, total), total)
      }
    }

    console.info('MetadataParser', `Parsed ${songList.length}/${total} audio files`)
    return songList
  }

  async extractCover(uri: string): Promise<image.PixelMap | null> {
    let extractor: media.AVMetadataExtractor | null = null
    let fileHandle: fileIo.File | null = null

    try {
      extractor = await media.createAVMetadataExtractor()
      fileHandle = await this.permissionManager.openReadableFile(uri)
      if (!fileHandle) {
        return null
      }
      extractor.fdSrc = { fd: fileHandle.fd, offset: 0, length: -1 }
      return await extractor.fetchAlbumCover()
    } catch (error) {
      console.error('MetadataParser', `Extract cover failed: ${JSON.stringify(error)}`)
      return null
    } finally {
      if (extractor) {
        extractor.release()
      }
      if (fileHandle) {
        fileIo.closeSync(fileHandle)
      }
    }
  }

  private parseFilenameToTitleArtist(uri: string): FilenameTitleArtist {
    const fileName = uri.split('/').pop() || Colors.UNKNOWN_TITLE
    let rawName = fileName.replace(/\.[^/.]+$/, '')
    try {
      rawName = decodeURIComponent(rawName)
    } catch (_) {
    }

    const separatorIndex = rawName.indexOf('-')
    if (separatorIndex >= 0) {
      const before = rawName.substring(0, separatorIndex).trim()
      const after = rawName.substring(separatorIndex + 1).trim()
      if (after.length > 0) {
        return { title: after, artist: before.length > 0 ? before : Colors.UNKNOWN_ARTIST }
      }
      return { title: before.length > 0 ? before : Colors.UNKNOWN_TITLE, artist: Colors.UNKNOWN_ARTIST }
    }

    const trimmed = rawName.trim()
    return { title: trimmed.length > 0 ? trimmed : Colors.UNKNOWN_TITLE, artist: Colors.UNKNOWN_ARTIST }
  }

  normalizeTitle(title: string): string {
    if (!title) {
      return Colors.UNKNOWN_TITLE
    }

    return title.trim()
  }

  resolveTitleArtistFromFilename(uri: string): FilenameTitleArtist {
    return this.parseFilenameToTitleArtist(uri)
  }

  private parseNumber(rawValue?: string): number {
    if (!rawValue) {
      return 0
    }

    const parsedValue = Number(rawValue)
    return Number.isFinite(parsedValue) ? parsedValue : 0
  }

  private findAudioTrack(metadata: media.AVMetadata): media.MediaDescription | null {
    if (!metadata.tracks || metadata.tracks.length === 0) {
      return null
    }

    for (const track of metadata.tracks) {
      const mimeType = this.getTrackString(track, this.trackMimeTypeKey)
      const codecMimeType = this.getTrackString(track, this.trackCodecMimeKey)
      if (mimeType.startsWith('audio/') || codecMimeType.startsWith('audio/')) {
        return track
      }
    }

    return metadata.tracks[0]
  }

  private getTrackString(track: media.MediaDescription | null, key: string): string {
    if (!track) {
      return ''
    }

    const rawValue = track[key]
    if (typeof rawValue === 'string') {
      return rawValue
    }
    if (typeof rawValue === 'number') {
      return `${rawValue}`
    }
    return ''
  }

  private getTrackNumber(track: media.MediaDescription | null, key: string): number {
    const rawValue = this.getTrackString(track, key)
    if (!rawValue) {
      return 0
    }

    const parsedValue = Number(rawValue)
    return Number.isFinite(parsedValue) ? parsedValue : 0
  }

  private resolveSampleRate(metadata: media.AVMetadata, audioTrack: media.MediaDescription | null): number {
    const sampleRateFromMetadata = this.parseNumber(metadata.sampleRate)
    if (sampleRateFromMetadata > 0) {
      return sampleRateFromMetadata
    }
    return this.getTrackNumber(audioTrack, this.trackSampleRateKey)
  }

  private resolveBitrate(audioTrack: media.MediaDescription | null): number {
    return this.getTrackNumber(audioTrack, this.trackBitrateKey)
  }

}
