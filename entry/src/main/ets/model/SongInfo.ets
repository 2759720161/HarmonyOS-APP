export class SongInfo {
  id: string = ''
  title: string = ''
  artist: string = ''
  album: string = ''
  duration: number = 0
  uri: string = ''
  coverUri: string = ''
  sampleRate: number = 0
  bitrate: number = 0
  mimeType: string = ''
  codecMimeType: string = ''
  lyrics: string = ''

  constructor(
    id: string,
    title: string,
    artist: string,
    album: string,
    duration: number,
    uri: string,
    coverUri: string = '',
    sampleRate: number = 0,
    bitrate: number = 0,
    mimeType: string = '',
    codecMimeType: string = '',
    lyrics: string = ''
  ) {
    this.id = id
    this.title = title
    this.artist = artist
    this.album = album
    this.duration = duration
    this.uri = uri
    this.coverUri = coverUri
    this.sampleRate = sampleRate
    this.bitrate = bitrate
    this.mimeType = mimeType
    this.codecMimeType = codecMimeType
    this.lyrics = lyrics
  }
}
