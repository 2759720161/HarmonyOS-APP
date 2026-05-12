import { fileIo, fileShare } from '@kit.CoreFileKit'

export class PermissionManager {
  private static instance: PermissionManager | null = null
  private readonly operationMode: number = 1
  private readonly legacyOperationMode: number = 2

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
    const fileHandle = await this.openReadableFile(uri)
    if (fileHandle) {
      fileIo.closeSync(fileHandle)
      return true
    }
    return false
  }

  async openReadableFile(uri: string): Promise<fileIo.File | null> {
    if (!uri) {
      return null
    }

    if (this.requiresPickerPermission(uri)) {
      await this.activateUriPermission(uri, this.operationMode)
    }

    try {
      return fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
    } catch (readError) {
      if (this.requiresPickerPermission(uri)) {
        await this.activateUriPermission(uri, this.legacyOperationMode)
      }

      try {
        return fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE)
      } catch (readWriteError) {
        console.warn('PermissionManager',
          `Open URI failed for ${uri}: read=${JSON.stringify(readError)}, readWrite=${JSON.stringify(readWriteError)}`)
        return null
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

  private async activateUriPermission(uri: string, operationMode: number): Promise<void> {
    try {
      await fileShare.activatePermission([this.buildPolicy(uri, operationMode)])
    } catch (error) {
      console.warn('PermissionManager', `Activate permission failed for ${uri}: ${JSON.stringify(error)}`)
    }
  }

  private buildPolicies(uris: string[], operationMode: number = this.operationMode): fileShare.PolicyInfo[] {
    return uris.map((uri: string) => this.buildPolicy(uri, operationMode))
  }

  private buildPolicy(uri: string, operationMode: number = this.operationMode): fileShare.PolicyInfo {
    return {
      uri: uri,
      operationMode: operationMode
    }
  }

  private requiresPickerPermission(uri: string): boolean {
    return uri.startsWith('file://')
  }
}
