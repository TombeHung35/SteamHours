import { http } from '@kit.NetworkKit';
import { privacyAccess } from '../model/PrivacyAccess';
import { ArtworkMap, SteamArtworkAssets, steamAssetUrls } from '../model/SteamImages';

interface StoreItem { appid: number; assets?: SteamArtworkAssets; }
interface StoreResponse { response?: StoreItems; }
interface StoreItems { store_items?: StoreItem[]; }
interface StoreId { appid: number; }
interface StoreContext { language: string; country_code: string; }
interface StoreDataRequest { include_assets: boolean; }
interface StoreInput { ids: StoreId[]; context: StoreContext; data_request: StoreDataRequest; }
interface CachedArtwork { urls: string[]; at: number; }

// Public game metadata only. Never send player identity, API keys or family tokens.
export class ArtworkApi {
  private cache: Map<number, CachedArtwork> = new Map();
  clearCache(): void { this.cache.clear(); }

  async load(appIds: number[]): Promise<ArtworkMap> {
    const generation: number = privacyAccess.begin();
    const ids: number[] = Array.from(new Set(appIds.filter((id: number) => Number.isInteger(id) && id > 0))).slice(0, 1200);
    const result: ArtworkMap = {};
    const missing: number[] = [];
    for (const id of ids) {
      const cached: CachedArtwork | undefined = this.cache.get(id);
      if (cached && Date.now() - cached.at < 86400000) result[id.toString()] = cached.urls.slice();
      else missing.push(id);
    }
    for (let offset: number = 0; offset < missing.length; offset += 50) {
      privacyAccess.check(generation);
      const batch: number[] = missing.slice(offset, offset + 50);
      try {
        let response: StoreResponse;
        try { response = await this.request(batch); }
        catch (_) { privacyAccess.check(generation); response = await this.request(batch); }
        privacyAccess.check(generation);
        const items: StoreItem[] | undefined = response.response?.store_items;
        if (!Array.isArray(items)) continue;
        for (const item of items) {
          if (!item || !batch.includes(item.appid)) continue;
          const urls: string[] = steamAssetUrls(item.appid, item.assets);
          if (!urls.length) continue;
          this.cache.set(item.appid, { urls: urls, at: Date.now() }); result[item.appid.toString()] = urls.slice();
        }
        while (this.cache.size > 5000) this.cache.delete(this.cache.keys().next().value);
      } catch (_) { privacyAccess.check(generation); }
    }
    return result;
  }

  private async request(ids: number[]): Promise<StoreResponse> {
    const generation: number = privacyAccess.begin();
    const input: StoreInput = { ids: ids.map((id: number): StoreId => ({ appid: id })), context: { language: 'schinese', country_code: 'CN' }, data_request: { include_assets: true } };
    const request: http.HttpRequest = http.createHttp();
    let destroyed: boolean = false;
    const close: () => void = (): void => { if (!destroyed) { destroyed = true; request.destroy(); } };
    const unregister: () => void = privacyAccess.register(close, generation);
    try {
      const response: http.HttpResponse = await request.request('https://api.steampowered.com/IStoreBrowseService/GetItems/v1/?input_json=' + encodeURIComponent(JSON.stringify(input)), {
        method: http.RequestMethod.GET, header: { 'Accept': 'application/json' }, expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000, readTimeout: 20000, usingCache: true
      });
      privacyAccess.check(generation);
      if (response.responseCode >= 400 && response.responseCode < 500) return {};
      if (response.responseCode !== 200 || typeof response.result !== 'string' || response.result.length > 8000000) throw new Error('封面素材暂不可用。');
      return JSON.parse(response.result) as StoreResponse;
    } finally { unregister(); close(); }
  }
}
