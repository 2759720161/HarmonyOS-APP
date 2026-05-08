import { http } from '@kit.NetworkKit'
import { image } from '@kit.ImageKit'

const TEXT_REQUEST_TIMEOUT = 20000
const IMAGE_REQUEST_TIMEOUT = 30000
const TIMEOUT_ERROR_CODE = 2300028
const HTTP2_ERROR_CODE = 2300016

class LrcApiQuery {
  title: string = ''
  artist: string = ''
  album: string = ''

  constructor(title: string = '', artist: string = '', album: string = '') {
    this.title = title
    this.artist = artist
    this.album = album
  }
}

export class LrcApiCoverResult {
  pixelMap: image.PixelMap | null = null
  coverUrl: string = ''

  constructor(pixelMap: image.PixelMap | null = null, coverUrl: string = '') {
    this.pixelMap = pixelMap
    this.coverUrl = coverUrl
  }
}

export class LrcApiService {
  private static instance: LrcApiService | null = null
  private lastErrorCode: number = 0
  private lastErrorMessage: string = ''

  private constructor() {}

  static getInstance(): LrcApiService {
    if (!LrcApiService.instance) {
      LrcApiService.instance = new LrcApiService()
    }
    return LrcApiService.instance
  }

  getLastErrorMessage(): string {
    return this.lastErrorMessage
  }

  isLastRequestTimedOut(): boolean {
    return this.lastErrorCode === TIMEOUT_ERROR_CODE ||
      this.lastErrorMessage.toLowerCase().includes('timeout')
  }

  isLastRequestTransportError(): boolean {
    return this.lastErrorCode === HTTP2_ERROR_CODE ||
      this.lastErrorCode === TIMEOUT_ERROR_CODE
  }

  async fetchLyrics(
    lyricsApiUrl: string,
    title: string,
    artist: string,
    album: string,
    apiKey: string
  ): Promise<string> {
    this.clearLastError()

    const normalizedLyricsUrl = this.normalizeEndpointUrl(lyricsApiUrl, 'lyrics')
    const normalizedJsonUrl = this.normalizeEndpointUrl(lyricsApiUrl, 'jsonapi')
    const queryCandidates = this.buildQueryCandidates(title, artist, album)

    if (this.isJsonEndpoint(normalizedLyricsUrl)) {
      const lyricFromJson = await this.fetchLyricsFromJson(normalizedLyricsUrl, queryCandidates, apiKey)
      if (lyricFromJson.length > 0) {
        return lyricFromJson
      }
    } else {
      const directLyrics = await this.fetchLyricsText(normalizedLyricsUrl, queryCandidates, apiKey)
      if (directLyrics.length > 0) {
        return directLyrics
      }
    }

    if (normalizedJsonUrl.length > 0 && normalizedJsonUrl !== normalizedLyricsUrl) {
      return await this.fetchLyricsFromJson(normalizedJsonUrl, queryCandidates, apiKey)
    }

    return ''
  }

  async fetchCover(
    coverApiUrl: string,
    title: string,
    artist: string,
    album: string,
    apiKey: string
  ): Promise<LrcApiCoverResult> {
    this.clearLastError()

    const normalizedJsonUrl = this.normalizeEndpointUrl(coverApiUrl, 'jsonapi')
    const normalizedCoverUrl = this.normalizeEndpointUrl(coverApiUrl, 'cover')
    const queryCandidates = this.buildQueryCandidates(title, artist, album)

    if (normalizedJsonUrl.length > 0) {
      for (const query of queryCandidates) {
        const coverUrl = await this.fetchCoverUrlFromJson(normalizedJsonUrl, query, apiKey)
        if (coverUrl.length > 0) {
          const pixelMap = await this.loadCoverFromUrl(coverUrl)
          if (pixelMap) {
            return new LrcApiCoverResult(pixelMap, coverUrl)
          }
        }
      }
    }

    if (normalizedCoverUrl.length > 0) {
      for (const query of queryCandidates) {
        const fallbackPixelMap = await this.fetchCoverBinary(normalizedCoverUrl, query, apiKey)
        if (fallbackPixelMap) {
          return new LrcApiCoverResult(fallbackPixelMap, '')
        }
      }
    }

    return new LrcApiCoverResult(null, '')
  }

  /**
   * 并发竞速文本请求 — 同时发起所有 URL 变体，取最先成功的结果
   */
  private raceTextGet(urls: string[], timeout: number, headers: Record<string, string>): Promise<http.HttpResponse | null> {
    if (urls.length === 0) {
      return Promise.resolve(null)
    }
    if (urls.length === 1) {
      return this.singleGet(urls[0], timeout, headers, false)
    }
    return new Promise<http.HttpResponse | null>((resolve) => {
      let settled = false
      let doneCount = 0
      const total = urls.length
      for (const url of urls) {
        this.singleGet(url, timeout, headers, false).then((resp: http.HttpResponse | null) => {
          if (settled) {
            return
          }
          if (resp !== null) {
            settled = true
            resolve(resp)
          } else {
            doneCount++
            if (doneCount >= total) {
              settled = true
              resolve(null)
            }
          }
        })
      }
    })
  }

  /**
   * 并发竞速二进制请求
   */
  private raceBinaryGet(urls: string[], timeout: number, headers: Record<string, string>): Promise<http.HttpResponse | null> {
    if (urls.length === 0) {
      return Promise.resolve(null)
    }
    if (urls.length === 1) {
      return this.singleGet(urls[0], timeout, headers, true)
    }
    return new Promise<http.HttpResponse | null>((resolve) => {
      let settled = false
      let doneCount = 0
      const total = urls.length
      for (const url of urls) {
        this.singleGet(url, timeout, headers, true).then((resp: http.HttpResponse | null) => {
          if (settled) {
            return
          }
          if (resp !== null) {
            settled = true
            resolve(resp)
          } else {
            doneCount++
            if (doneCount >= total) {
              settled = true
              resolve(null)
            }
          }
        })
      }
    })
  }

  private async singleGet(
    url: string, timeout: number, headers: Record<string, string>, binary: boolean
  ): Promise<http.HttpResponse | null> {
    const httpRequest = http.createHttp()
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: timeout,
        readTimeout: timeout,
        header: headers
      }
      if (binary) {
        opts.expectDataType = http.HttpDataType.ARRAY_BUFFER
      }
      const response = await httpRequest.request(url, opts)
      if (response.responseCode === 200 && response.result) {
        return response
      }
      return null
    } catch (error) {
      this.captureError(error)
      return null
    } finally {
      httpRequest.destroy()
    }
  }

  async loadCoverFromUrl(coverUrl: string): Promise<image.PixelMap | null> {
    if (coverUrl.length === 0) {
      return null
    }

    const requestUrlVariants = this.buildRequestUrlVariants(coverUrl)
    const response = await this.raceBinaryGet(requestUrlVariants, IMAGE_REQUEST_TIMEOUT, this.createHeaders(''))
    if (response) {
      const pixelMap = await this.responseToPixelMap(response)
      if (pixelMap) {
        this.clearLastError()
        return pixelMap
      }
    }

    console.error('LrcApiService', `loadCoverFromUrl failed: ${this.lastErrorMessage}`)
    return null
  }

  private async fetchLyricsText(requestUrl: string, queries: LrcApiQuery[], apiKey: string): Promise<string> {
    const headers = this.createHeaders(apiKey, 'text/plain, application/json')
    for (const query of queries) {
      const urls = this.buildRequestUrlVariants(this.appendQuery(requestUrl, query))
      const response = await this.raceTextGet(urls, TEXT_REQUEST_TIMEOUT, headers)
      if (response && typeof response.result === 'string') {
        const lyrics = (response.result as string).trim()
        if (lyrics.length > 0) {
          this.clearLastError()
          return lyrics
        }
      }
    }
    return ''
  }

  private async fetchLyricsFromJson(requestUrl: string, queries: LrcApiQuery[], apiKey: string): Promise<string> {
    for (const query of queries) {
      const jsonData = await this.fetchJsonArray(requestUrl, query, apiKey)
      const lyrics = this.extractBestLyrics(jsonData)
      if (lyrics.length > 0) {
        return lyrics
      }
    }
    return ''
  }

  private async fetchCoverUrlFromJson(requestUrl: string, query: LrcApiQuery, apiKey: string): Promise<string> {
    const jsonData = await this.fetchJsonArray(requestUrl, query, apiKey)
    return this.extractBestCoverUrl(jsonData)
  }

  private async fetchJsonArray(requestUrl: string, query: LrcApiQuery, apiKey: string): Promise<Object[]> {
    if (requestUrl.length === 0) {
      return []
    }

    const urls = this.buildRequestUrlVariants(this.appendQuery(requestUrl, query))
    const headers = this.createHeaders(apiKey, 'application/json, text/plain')
    const response = await this.raceTextGet(urls, TEXT_REQUEST_TIMEOUT, headers)
    if (response) {
      try {
        if (typeof response.result === 'string') {
          const parsed = JSON.parse(response.result) as Object[] | Object
          this.clearLastError()
          return Array.isArray(parsed) ? parsed : [parsed]
        }
        if (Array.isArray(response.result)) {
          this.clearLastError()
          return response.result as Object[]
        }
        this.clearLastError()
        return [response.result as Object]
      } catch (error) {
        this.captureError(error)
      }
    }

    console.error('LrcApiService', `fetchJsonArray failed: ${this.lastErrorMessage}`)
    return []
  }

  private async fetchCoverBinary(requestUrl: string, query: LrcApiQuery, apiKey: string): Promise<image.PixelMap | null> {
    if (requestUrl.length === 0) {
      return null
    }

    const urls = this.buildRequestUrlVariants(this.appendQuery(requestUrl, query))
    const headers = this.createHeaders(apiKey)
    const response = await this.raceBinaryGet(urls, IMAGE_REQUEST_TIMEOUT, headers)
    if (response) {
      const pixelMap = await this.responseToPixelMap(response)
      if (pixelMap) {
        this.clearLastError()
        return pixelMap
      }
    }

    console.error('LrcApiService', `fetchCoverBinary failed: ${this.lastErrorMessage}`)
    return null
  }

  private async responseToPixelMap(response: http.HttpResponse): Promise<image.PixelMap | null> {
    if (response.responseCode === 200 && response.result) {
      const buffer = response.result as ArrayBuffer
      if (buffer.byteLength > 0) {
        const imageSource = image.createImageSource(buffer)
        const pixelMap = await imageSource.createPixelMap()
        imageSource.release()
        return pixelMap
      }
    }

    const location = this.getHeaderValue(response.header, 'Location')
    if (location.length > 0) {
      return await this.loadCoverFromUrl(location)
    }

    return null
  }

  private buildQueryCandidates(title: string, artist: string, album: string): LrcApiQuery[] {
    const normalizedTitle = this.normalizeMetadataValue(title, 'title')
    const normalizedArtist = this.normalizeMetadataValue(artist, 'artist')
    const normalizedAlbum = this.normalizeMetadataValue(album, 'album')
    const candidates: LrcApiQuery[] = []

    const splitCandidate = this.trySplitTitleArtist(normalizedTitle, normalizedArtist, normalizedAlbum)
    if (splitCandidate) {
      candidates.push(splitCandidate)
    }

    if (normalizedTitle.length > 0 || normalizedArtist.length > 0 || normalizedAlbum.length > 0) {
      candidates.push(new LrcApiQuery(normalizedTitle, normalizedArtist, normalizedAlbum))
    }

    if (splitCandidate && splitCandidate.title.length > 0) {
      candidates.push(new LrcApiQuery(splitCandidate.title, splitCandidate.artist, ''))
      candidates.push(new LrcApiQuery(splitCandidate.title, '', ''))
    }

    if (normalizedTitle.length > 0) {
      candidates.push(new LrcApiQuery(normalizedTitle, normalizedArtist, ''))
      candidates.push(new LrcApiQuery(normalizedTitle, '', ''))
    }

    return this.uniqueQueries(candidates)
  }

  private uniqueQueries(candidates: LrcApiQuery[]): LrcApiQuery[] {
    const uniqueMap = new Map<string, LrcApiQuery>()
    for (const query of candidates) {
      if (query.title.length === 0 && query.artist.length === 0) {
        continue
      }
      const key = `${query.title}|${query.artist}|${query.album}`
      if (!uniqueMap.has(key)) {
        uniqueMap.set(key, query)
      }
    }
    return Array.from(uniqueMap.values())
  }

  private trySplitTitleArtist(title: string, artist: string, album: string): LrcApiQuery | null {
    if (artist.length > 0 || title.length === 0) {
      return null
    }

    const match = title.match(/^(.+?)\s*-\s*(.+)$/)
    if (!match || !match[1] || !match[2]) {
      return null
    }

    return new LrcApiQuery(match[2].trim(), match[1].trim(), album)
  }

  private normalizeMetadataValue(value: string, field: string): string {
    if (typeof value !== 'string') {
      return ''
    }

    const normalized = value.trim()
    if (normalized.length === 0) {
      return ''
    }

    const lowerCased = normalized.toLowerCase()
    if (field === 'artist' && lowerCased === 'unknown artist') {
      return ''
    }
    if (field === 'album' && lowerCased === 'unknown album') {
      return ''
    }
    if (field === 'title' && (lowerCased === 'unknown title' || lowerCased === 'unknown track')) {
      return ''
    }

    return normalized
  }

  private buildRequestUrlVariants(url: string): string[] {
    const variants: string[] = []
    if (this.isPublicApiLrcEndpoint(url)) {
      variants.push(this.replaceScheme(url, 'http'))
      variants.push(this.replaceScheme(url, 'https'))
      return this.uniqueStringArray(variants)
    }
    return [url]
  }

  private uniqueStringArray(values: string[]): string[] {
    const result: string[] = []
    for (const item of values) {
      if (!result.includes(item)) {
        result.push(item)
      }
    }
    return result
  }

  private isPublicApiLrcEndpoint(url: string): boolean {
    return /^https?:\/\/api\.lrc\.cx(\/|$)/i.test(url)
  }

  private replaceScheme(url: string, scheme: 'http' | 'https'): string {
    return url.replace(/^https?:\/\//i, `${scheme}://`)
  }

  private normalizeEndpointUrl(rawUrl: string, endpoint: string): string {
    const fallbackUrl = this.getDefaultEndpointUrl(endpoint)
    let url = typeof rawUrl === 'string' ? rawUrl.trim() : ''
    if (url.length === 0) {
      return fallbackUrl
    }

    if (!/^https?:\/\//i.test(url)) {
      url = `https://${url.replace(/^\/+/, '')}`
    }

    const hashIndex = url.indexOf('#')
    if (hashIndex >= 0) {
      url = url.substring(0, hashIndex)
    }

    const queryIndex = url.indexOf('?')
    const query = queryIndex >= 0 ? url.substring(queryIndex) : ''
    let baseUrl = queryIndex >= 0 ? url.substring(0, queryIndex) : url
    baseUrl = baseUrl.replace(/\/+$/, '')

    if (endpoint === 'lyrics') {
      if (baseUrl.endsWith('/jsonapi')) {
        return `${baseUrl.substring(0, baseUrl.length - '/jsonapi'.length)}/lyrics${query}`
      }
      if (baseUrl.endsWith('/api/v1/lyrics/advance')) {
        return `${baseUrl.substring(0, baseUrl.length - '/advance'.length)}/single${query}`
      }
      if (baseUrl.endsWith('/lyrics') || baseUrl.endsWith('/api/v1/lyrics/single')) {
        return `${baseUrl}${query}`
      }
      if (baseUrl.endsWith('/cover')) {
        return `${baseUrl.substring(0, baseUrl.length - '/cover'.length)}/lyrics${query}`
      }
      return `${baseUrl}/lyrics${query}`
    }

    if (endpoint === 'cover') {
      if (baseUrl.endsWith('/jsonapi')) {
        return `${baseUrl.substring(0, baseUrl.length - '/jsonapi'.length)}/cover${query}`
      }
      if (baseUrl.endsWith('/lyrics')) {
        return `${baseUrl.substring(0, baseUrl.length - '/lyrics'.length)}/cover${query}`
      }
      if (baseUrl.endsWith('/cover')) {
        return `${baseUrl}${query}`
      }
      return `${baseUrl}/cover${query}`
    }

    if (baseUrl.endsWith('/jsonapi') || baseUrl.endsWith('/api/v1/lyrics/advance')) {
      return `${baseUrl}${query}`
    }
    if (baseUrl.endsWith('/lyrics')) {
      return `${baseUrl.substring(0, baseUrl.length - '/lyrics'.length)}/jsonapi${query}`
    }
    if (baseUrl.endsWith('/cover')) {
      return `${baseUrl.substring(0, baseUrl.length - '/cover'.length)}/jsonapi${query}`
    }
    if (baseUrl.endsWith('/api/v1/lyrics/single')) {
      return `${baseUrl.substring(0, baseUrl.length - '/single'.length)}/advance${query}`
    }
    return `${baseUrl}/jsonapi${query}`
  }

  private getDefaultEndpointUrl(endpoint: string): string {
    if (endpoint === 'jsonapi') {
      return 'https://api.lrc.cx/jsonapi'
    }
    if (endpoint === 'cover') {
      return 'https://api.lrc.cx/cover'
    }
    return 'https://api.lrc.cx/lyrics'
  }

  private isJsonEndpoint(url: string): boolean {
    return url.endsWith('/jsonapi') || url.endsWith('/api/v1/lyrics/advance')
  }

  private appendQuery(url: string, query: LrcApiQuery): string {
    const params: string[] = []
    if (query.title.length > 0) {
      params.push(`title=${encodeURIComponent(query.title)}`)
    }
    if (query.artist.length > 0) {
      params.push(`artist=${encodeURIComponent(query.artist)}`)
    }
    if (query.album.length > 0) {
      params.push(`album=${encodeURIComponent(query.album)}`)
    }

    if (params.length === 0) {
      return url
    }

    const separator = url.includes('?') ? '&' : '?'
    return `${url}${separator}${params.join('&')}`
  }

  private extractBestLyrics(items: Object[]): string {
    for (const item of items) {
      const candidate = item as Record<string, Object>
      const lyrics = this.readString(candidate, 'lyrics')
      if (lyrics.length > 0) {
        return lyrics
      }

      const lrc = this.readString(candidate, 'lrc')
      if (lrc.length > 0) {
        return lrc
      }
    }
    return ''
  }

  private extractBestCoverUrl(items: Object[]): string {
    for (const item of items) {
      const candidate = item as Record<string, Object>
      const coverUrl = this.readString(candidate, 'cover')
      if (/^https?:\/\//i.test(coverUrl)) {
        return coverUrl
      }
    }
    return ''
  }

  private readString(source: Record<string, Object>, key: string): string {
    const value = source[key]
    return typeof value === 'string' ? value.trim() : ''
  }

  private createHeaders(apiKey: string, accept: string = '*/*'): Record<string, string> {
    const headers: Record<string, string> = { 'Accept': accept }
    if (apiKey.length > 0) {
      headers['Authorization'] = apiKey
      headers['Authentication'] = apiKey
    }
    return headers
  }

  private getHeaderValue(headers: Object | undefined, key: string): string {
    if (!headers) {
      return ''
    }

    const headerMap = headers as Record<string, Object>
    const directValue = headerMap[key]
    if (typeof directValue === 'string') {
      return directValue
    }

    const lowerCaseValue = headerMap[key.toLowerCase()]
    if (typeof lowerCaseValue === 'string') {
      return lowerCaseValue
    }

    return ''
  }

  private clearLastError(): void {
    this.lastErrorCode = 0
    this.lastErrorMessage = ''
  }

  private captureError(error: Object): void {
    const typedError = error as Record<string, Object>
    const code = typedError['code']
    const message = typedError['message']
    this.lastErrorCode = typeof code === 'number' ? code : 0
    this.lastErrorMessage = typeof message === 'string'
      ? message
      : JSON.stringify(error)
  }
}
