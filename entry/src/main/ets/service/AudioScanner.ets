import { media } from '@kit.MediaKit'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { effectKit } from '@kit.ArkGraphics2D'
import { Colors, StorageKeys } from '../common/Constants'
import { GlobalContext, GCKeys } from '../common/GlobalContext'

/**
 * 音频文件工具类
 * 
 * 提供专辑封面提取和主色调提取功能
 * 注意：文件扫描功能已迁移到AudioPicker服务
 */
export class AudioScanner {
  static async updateCurrentCoverFromPixelMap(pixelMap: image.PixelMap | null): Promise<void> {
    await AudioScanner.applyCurrentCover(pixelMap)
  }

  /**
   * 从文件提取专辑封面 PixelMap（AVMetadataExtractor）
   */
  static async extractAlbumCover(uri: string): Promise<image.PixelMap | null> {
    let extractor: media.AVMetadataExtractor | null = null
    let fileHandle: fileIo.File | null = null
    try {
      extractor = await media.createAVMetadataExtractor()
      // Picker返回的URI需要直接传入（含file://前缀），系统自动映射
      fileHandle = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      extractor.fdSrc = { fd: fileHandle.fd, offset: 0, length: -1 }
      const pixelMap = await extractor.fetchAlbumCover()
      return pixelMap
    } catch (_) {
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

  /**
   * 更新当前播放歌曲封面到 GlobalContext，触发 UI 刷新
   */
  static async updateCurrentCover(uri: string): Promise<void> {
    const pixelMap = await AudioScanner.extractAlbumCover(uri)
    await AudioScanner.applyCurrentCover(pixelMap)
  }

  private static async applyCurrentCover(pixelMap: image.PixelMap | null): Promise<void> {
    if (pixelMap) {
      let coverPixelMap: image.PixelMap = pixelMap
      try {
        coverPixelMap = await AudioScanner.createDisplayPixelMap(pixelMap)
      } catch (err) {
        console.error('AudioScanner', `封面缩放失败: ${JSON.stringify(err)}`)
      }

      GlobalContext.getInstance().set(GCKeys.CURRENT_COVER, coverPixelMap)
      let samplePixelMap: image.PixelMap | null = null
      let shouldReleaseSample: boolean = false
      try {
        // 使用 effectKit 提取主色调
        const sampledPixelMap = await AudioScanner.createThemePixelMap(coverPixelMap)
        samplePixelMap = sampledPixelMap
        shouldReleaseSample = sampledPixelMap !== coverPixelMap
        const colorPicker = await effectKit.createColorPicker(sampledPixelMap)
        const mainColor = colorPicker.getMainColorSync()
        if (mainColor) {
          const r = mainColor.red.toString(16).padStart(2, '0')
          const g = mainColor.green.toString(16).padStart(2, '0')
          const b = mainColor.blue.toString(16).padStart(2, '0')
          AppStorage.setOrCreate(StorageKeys.DOMINANT_COLOR, `#${r}${g}${b}`)
        } else {
          AppStorage.setOrCreate(StorageKeys.DOMINANT_COLOR, Colors.DEFAULT_DOMINANT_COLOR)
        }
      } catch (err) {
        console.error('AudioScanner', `取色失败: ${JSON.stringify(err)}`)
        AppStorage.setOrCreate(StorageKeys.DOMINANT_COLOR, Colors.DEFAULT_DOMINANT_COLOR)
      } finally {
        if (shouldReleaseSample && samplePixelMap) {
          samplePixelMap.release()
        }
      }
    } else {
      GlobalContext.getInstance().delete(GCKeys.CURRENT_COVER)
      AppStorage.setOrCreate(StorageKeys.DOMINANT_COLOR, Colors.DEFAULT_DOMINANT_COLOR)
    }
    const version: number = AppStorage.get<number>(StorageKeys.COVER_VERSION) ?? 0
    AppStorage.setOrCreate(StorageKeys.COVER_VERSION, version + 1)
  }

  private static async createThemePixelMap(pixelMap: image.PixelMap): Promise<image.PixelMap> {
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

  private static async createDisplayPixelMap(pixelMap: image.PixelMap): Promise<image.PixelMap> {
    const imageInfo = await pixelMap.getImageInfo()
    const width: number = Math.max(1, imageInfo.size.width)
    const height: number = Math.max(1, imageInfo.size.height)
    const maxSide: number = Math.max(width, height)
    const displaySize: number = 720

    if (maxSide <= displaySize) {
      return pixelMap
    }

    const scale: number = displaySize / maxSide
    return await pixelMap.createScaledPixelMap(scale, scale)
  }
}
