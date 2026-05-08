import { avSession as AVSession } from '@kit.AVSessionKit'
import { image } from '@kit.ImageKit'
import { SongInfo } from '../model/SongInfo'
import { PlayMode } from '../common/Constants'
import { GlobalContext, GCKeys } from '../common/GlobalContext'

/** 避免循环依赖，仅声明播放控制接口 */
interface IPlayerControl {
  resume(): Promise<void>;
  pause(): Promise<void>;
  next(): Promise<void>;
  prev(): Promise<void>;
  seekTo(ms: number): Promise<void>;
}

/**
 * AVSession 系统播控管理器
 * 负责与系统控制中心、锁屏播控卡片同步播放状态
 */
export class AVSessionManager {
  private session: AVSession.AVSession | null = null
  private playerRef: object | null = null   // 使用 object 避免循环依赖类型
  private lastPositionUpdateTime: number = 0
  private static readonly POSITION_UPDATE_INTERVAL: number = 1000

  async init(context: object, playerService: object): Promise<void> {
    this.playerRef = playerService
    try {
      this.session = await AVSession.createAVSession(
        context as Context,
        'LocalMusicPlayer',
        'audio'
      )
      await this.session.activate()
      this.registerCommands()
    } catch (err) {
      console.error('AVSessionManager', `创建Session失败: ${JSON.stringify(err)}`)
    }
  }

  private registerCommands(): void {
    if (!this.session) {
      return
    }

    const player = this.playerRef as IPlayerControl

    this.session.on('play', () => {
      player.resume()
    })

    this.session.on('pause', () => {
      player.pause()
    })

    this.session.on('playNext', () => {
      player.next()
    })

    this.session.on('playPrevious', () => {
      player.prev()
    })

    this.session.on('seek', (time: number) => {
      player.seekTo(time)
    })
  }

  /** 更新歌曲元数据（歌名、歌手、时长、封面） */
  async updateMetadata(song: SongInfo): Promise<void> {
    if (!this.session) {
      return
    }
    try {
      const metadata: AVSession.AVMetadata = {
        assetId: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
      }

      // 如果有封面，设置封面
      const cover = GlobalContext.getInstance().get(GCKeys.CURRENT_COVER)
      if (cover) {
        metadata.mediaImage = cover as image.PixelMap
      }

      await this.session.setAVMetadata(metadata)
    } catch (err) {
      console.error('AVSessionManager', `更新Metadata失败: ${JSON.stringify(err)}`)
    }
  }

  /** 更新播放状态 */
  async updatePlaybackState(state: AVSession.PlaybackState, position: number): Promise<void> {
    if (!this.session) {
      return
    }
    try {
      await this.session.setAVPlaybackState({
        state: state,
        position: {
          elapsedTime: position,
          updateTime: Date.now()
        }
      })
    } catch (err) {
      console.error('AVSessionManager', `更新PlaybackState失败: ${JSON.stringify(err)}`)
    }
  }

  /** 更新进度（轻量，仅更新position），节流1秒避免高频阻塞主线程 */
  async updatePosition(positionMs: number): Promise<void> {
    if (!this.session) {
      return
    }
    const now: number = Date.now()
    if (now - this.lastPositionUpdateTime < AVSessionManager.POSITION_UPDATE_INTERVAL) {
      return
    }
    this.lastPositionUpdateTime = now
    try {
      await this.session.setAVPlaybackState({
        position: {
          elapsedTime: positionMs,
          updateTime: now
        }
      })
    } catch (_) {
      // 静默忽略高频更新的错误
    }
  }

  /** 更新循环模式 */
  async updateLoopMode(mode: PlayMode): Promise<void> {
    if (!this.session) {
      return
    }
    let loopMode: AVSession.LoopMode = AVSession.LoopMode.LOOP_MODE_SEQUENCE
    if (mode === PlayMode.SINGLE) {
      loopMode = AVSession.LoopMode.LOOP_MODE_SINGLE
    } else if (mode === PlayMode.SHUFFLE) {
      loopMode = AVSession.LoopMode.LOOP_MODE_SHUFFLE
    }
    try {
      await this.session.setAVPlaybackState({ loopMode: loopMode })
    } catch (err) {
      console.error('AVSessionManager', `更新LoopMode失败: ${JSON.stringify(err)}`)
    }
  }

  release(): void {
    if (this.session) {
      this.session.deactivate()
      this.session.destroy()
      this.session = null
    }
  }
}
