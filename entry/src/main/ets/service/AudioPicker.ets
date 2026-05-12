import { picker } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { SongInfo } from '../model/SongInfo'
import { PermissionManager } from './PermissionManager'
import { MetadataParser } from './MetadataParser'
import { PlaylistManager } from './PlaylistManager'

export class AudioPicker {
  private static instance: AudioPicker | null = null
  private permissionManager: PermissionManager = PermissionManager.getInstance()
  private metadataParser: MetadataParser = MetadataParser.getInstance()
  private playlistManager: PlaylistManager = PlaylistManager.getInstance()

  private constructor() {}

  static getInstance(): AudioPicker {
    if (!AudioPicker.instance) {
      AudioPicker.instance = new AudioPicker()
    }
    return AudioPicker.instance
  }

  async pickAudioFiles(
    context: common.UIAbilityContext,
    onProgress?: (status: string, current: number, total: number) => void
  ): Promise<SongInfo[]> {
    try {
      if (onProgress) {
        onProgress('正在打开文件选择器...', 0, 0)
      }

      const documentPicker = new picker.DocumentViewPicker(context)
      const selectResult = await documentPicker.select({
        fileSuffixFilters: ['.mp3', '.flac', '.ogg', '.wav'],
        maxSelectNumber: 500
      })

      if (!selectResult || selectResult.length === 0) {
        console.info('AudioPicker', 'User canceled audio selection')
        return []
      }

      console.info('AudioPicker', `Selected ${selectResult.length} audio files`)

      if (onProgress) {
        onProgress('正在申请文件访问权限...', 0, selectResult.length)
      }

      const permissionSuccess = await this.permissionManager.persistPermissions(selectResult)
      if (!permissionSuccess) {
        console.warn('AudioPicker', 'Persisting picker permissions failed, continuing with current session access')
      }

      if (onProgress) {
        onProgress('正在激活文件访问权限...', 0, selectResult.length)
      }

      await this.permissionManager.activatePermissions(selectResult)

      const referencedUris = selectResult.filter((uri: string) => uri.length > 0)
      if (referencedUris.length === 0) {
        console.warn('AudioPicker', 'No selectable audio file URIs were returned')
        return []
      }

      if (onProgress) {
        onProgress('正在解析音频文件...', 0, referencedUris.length)
      }

      const songList = await this.metadataParser.parseMetadataBatch(
        referencedUris,
        (current: number, total: number) => {
          if (onProgress) {
            onProgress('正在解析音频文件...', current, total)
          }
        }
      )

      if (songList.length > 0) {
        this.playlistManager.addSongs(songList)
        console.info('AudioPicker', `Added ${songList.length} songs to playlist`)
      }

      return songList
    } catch (error) {
      console.error('AudioPicker', `Pick audio files failed: ${JSON.stringify(error)}`)
      return []
    }
  }

  async pickSingleAudioFile(context: common.UIAbilityContext): Promise<SongInfo | null> {
    const songList = await this.pickAudioFiles(context)
    return songList.length > 0 ? songList[0] : null
  }
}
