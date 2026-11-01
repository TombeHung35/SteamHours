import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

export class KeyStore {
  private storeAlias: string;
  constructor(alias: string = 'steam_hours_personal_api_key_v1') {
    this.storeAlias = alias;
  }
  private alias(): Uint8Array {
    return new util.TextEncoder().encodeInto(this.storeAlias);
  }

  async read(): Promise<string> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias());
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: Array<asset.AssetMap> = await asset.query(query);
      if (results.length === 0) return '';
      const secret: Uint8Array = results[0].get(asset.Tag.SECRET) as Uint8Array;
      return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(secret, { stream: false });
    } catch (error) {
      if ((error as BusinessError).code === 24000002) return '';
      throw new Error('暂时无法读取安全存储，请重新输入密钥。');
    }
  }

  async save(key: string): Promise<void> {
    const attrs: asset.AssetMap = new Map();
    attrs.set(asset.Tag.ALIAS, this.alias());
    attrs.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(key));
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    attrs.set(asset.Tag.AUTH_TYPE, asset.AuthType.NONE);
    attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      await asset.add(attrs);
    } catch (_) {
      throw new Error('密钥未能写入安全存储，当前仅在本次打开应用期间使用。');
    }
  }

  async clear(): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias());
    try {
      await asset.remove(query);
    } catch (error) {
      if ((error as BusinessError).code === 24000002) return;
      throw new Error('暂时无法删除已保存的密钥，请稍后重试。');
    }
  }
}
