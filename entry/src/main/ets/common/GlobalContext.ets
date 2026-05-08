/**
 * 全局上下文单例 —— 用于存储无法 JSON 序列化的对象（如 PixelMap）
 */
export class GlobalContext {
  private static instance: GlobalContext | null = null
  private objectMap: Map<string, Object> = new Map<string, Object>()

  private constructor() {}

  static getInstance(): GlobalContext {
    if (!GlobalContext.instance) {
      GlobalContext.instance = new GlobalContext()
    }
    return GlobalContext.instance
  }

  set(key: string, value: Object): void {
    this.objectMap.set(key, value)
  }

  get(key: string): Object | undefined {
    return this.objectMap.get(key)
  }

  has(key: string): boolean {
    return this.objectMap.has(key)
  }

  delete(key: string): void {
    this.objectMap.delete(key)
  }
}

/** GlobalContext 中存储的 Key */
export class GCKeys {
  static readonly ABILITY_CONTEXT: string = 'abilityContext'
  static readonly CURRENT_COVER: string = 'currentCoverPixelMap'
  static readonly WINDOW_CLASS: string = 'windowClass'
}
