import { fileIo, fileShare } from '@kit.CoreFileKit'

export class PermissionManager {
  private static instance: PermissionManager | null = null
  private readonly operationMode: number = 2

  private constructor() {}

  static getInstance(): PermissionManager {
    if (!PermissionManager.instance) {
      PermissionManager.instance = new PermissionManager()
    }
    return PermissionManager.instance
  }

  async persistPermissions(uris: string[]): Promise<boolean> {
    if (!uris || uris.length === 0) {
      console.warn('PermissionManager', 'URI list is empty')
      return false
    }

    try {
      await fileShare.persistPermission(this.buildPolicies(uris))
      console.info('PermissionManager', `Persisted permissions for ${uris.length} files`)
      return true
    } catch (error) {
      console.error('PermissionManager', `Persist permissions failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  async revokePermissions(uris: string[]): Promise<boolean> {
    if (!uris || uris.length === 0) {
      console.warn('PermissionManager', 'URI list is empty')
      return false
    }

    try {
      await fileShare.revokePermission(this.buildPolicies(uris))
      console.info('PermissionManager', `Revoked permissions for ${uris.length} files`)
      return true
    } catch (error) {
      console.error('PermissionManager', `Revoke permissions failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  async checkPermission(uri: string): Promise<boolean> {
    return this.ensureUriAccessible(uri)
  }

  async checkPermissions(uris: string[]): Promise<string[]> {
    return this.ensureUrisAccessible(uris)
  }

  async activatePermissions(uris: string[]): Promise<boolean> {
    if (!uris || uris.length === 0) {
      console.warn('PermissionManager', 'URI list is empty')
      return false
    }

    try {
      await fileShare.activatePermission(this.buildPolicies(uris))
      console.info('PermissionManager', `Activated permissions for ${uris.length} files`)
      return true
    } catch (error) {
      console.error('PermissionManager', `Activate permissions failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  async ensureUriAccessible(uri: string): Promise<boolean> {
    if (!uri) {
      return false
    }

    if (this.requiresPickerPermission(uri)) {
      try {
        await fileShare.activatePermission([this.buildPolicy(uri)])
      } catch (error) {
        console.warn('PermissionManager', `Activate permission failed for ${uri}: ${JSON.stringify(error)}`)
        return false
      }
    }

    let fileHandle: fileIo.File | null = null
    try {
      fileHandle = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      return true
    } catch (error) {
      console.warn('PermissionManager', `Open URI failed for ${uri}: ${JSON.stringify(error)}`)
      return false
    } finally {
      if (fileHandle) {
        fileIo.closeSync(fileHandle)
      }
    }
  }

  async ensureUrisAccessible(uris: string[]): Promise<string[]> {
    if (!uris || uris.length === 0) {
      return []
    }

    const validUris: string[] = []
    for (const uri of uris) {
      if (await this.ensureUriAccessible(uri)) {
        validUris.push(uri)
      }
    }
    return validUris
  }

  private buildPolicies(uris: string[]): fileShare.PolicyInfo[] {
    return uris.map((uri: string) => this.buildPolicy(uri))
  }

  private buildPolicy(uri: string): fileShare.PolicyInfo {
    return {
      uri: uri,
      operationMode: this.operationMode
    }
  }

  private requiresPickerPermission(uri: string): boolean {
    return uri.startsWith('file://')
  }
}
