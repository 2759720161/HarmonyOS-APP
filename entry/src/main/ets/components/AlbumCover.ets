import { image } from '@kit.ImageKit'
import { GlobalContext, GCKeys } from '../common/GlobalContext'

/**
 * 专辑封面组件（播放详情页使用）
 * 功能：黑胶唱片旋转动画 + HDS shadow 投影
 */
@Component
export struct AlbumCover {
  /** 是否正在播放（控制旋转） */
  @Prop isPlaying: boolean = false
  /** 封面版本号（变化时触发封面刷新） */
  @Prop coverVersion: number = 0
  /** 封面直径尺寸（vp），避免与系统 size 属性冲突 */
  @Prop coverSize: number = 260

  @State private coverPixelMap: image.PixelMap | null = null
  @State private rotateAngle: number = 0
  private rotateTimer: number = -1

  aboutToAppear(): void {
    this.loadCover()
    if (this.isPlaying) {
      this.startRotation()
    }
  }

  aboutToDisappear(): void {
    this.stopRotation()
  }

  private loadCover(): void {
    const pm = GlobalContext.getInstance().get(GCKeys.CURRENT_COVER)
    this.coverPixelMap = pm ? pm as image.PixelMap : null
  }

  private startRotation(): void {
    if (this.rotateTimer !== -1) {
      return
    }
    this.rotateTimer = setInterval(() => {
      this.rotateAngle = (this.rotateAngle + 0.08) % 360
    }, 16)
  }

  private stopRotation(): void {
    if (this.rotateTimer !== -1) {
      clearInterval(this.rotateTimer)
      this.rotateTimer = -1
    }
  }

  build() {
    Stack() {
      // 黑胶唱片底盘
      Circle()
        .width(this.coverSize)
        .height(this.coverSize)
        .fill($r('app.color.album_disc_fill'))
        .shadow({
          radius: 40,
          color: $r('app.color.album_disc_shadow'),
          offsetX: 0,
          offsetY: 20
        })

      // 叠加光泽 (SweepGradient) - 更真实的光盘折射反光模型
      Circle()
        .width(this.coverSize)
        .height(this.coverSize)
        .fill(Color.Transparent)
        .sweepGradient({
          center: ['50%', '50%'],
          start: 0,
          end: 360,
          colors: [
            ['rgba(255, 255, 255, 0.00)', 0.0],
            ['rgba(255, 255, 255, 0.03)', 0.1],
            ['rgba(255, 255, 255, 0.25)', 0.15], // 强反光带
            ['rgba(255, 255, 255, 0.03)', 0.2],
            ['rgba(255, 255, 255, 0.00)', 0.45],
            ['rgba(255, 255, 255, 0.03)', 0.6],
            ['rgba(255, 255, 255, 0.15)', 0.65], // 对称副反光带
            ['rgba(255, 255, 255, 0.03)', 0.7],
            ['rgba(255, 255, 255, 0.00)', 1.0]
          ]
        })
        .blendMode(BlendMode.OVERLAY)

      // 同心圆纹路
      ForEach([0.95, 0.85, 0.75, 0.65, 0.55] as number[], (ratio: number) => {
        Circle()
          .width(this.coverSize * ratio)
          .height(this.coverSize * ratio)
          .fill(Color.Transparent)
          .stroke($r('app.color.album_disc_ring'))
          .strokeWidth(1)
      }, (ratio: number) => ratio.toString())

      // 专辑封面图（或默认图标）
      if (this.coverPixelMap) {
        Image(this.coverPixelMap)
          .width(this.coverSize * 0.6)
          .height(this.coverSize * 0.6)
          .borderRadius(this.coverSize * 0.3 as number)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(this.coverSize * 0.22)
            .fontColor([$r('app.color.album_placeholder_icon')])
        }
        .width(this.coverSize * 0.6)
        .height(this.coverSize * 0.6)
        .borderRadius(this.coverSize * 0.3 as number)
        .backgroundColor($r('app.color.album_placeholder_bg'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // 中心小孔
      Circle()
        .width(18)
        .height(18)
        .fill($r('app.color.album_center_fill'))
        .stroke($r('app.color.album_center_stroke'))
        .strokeWidth(1.5)
    }
    .width(this.coverSize)
    .height(this.coverSize)
    .rotate({ angle: this.rotateAngle })
  }
}
