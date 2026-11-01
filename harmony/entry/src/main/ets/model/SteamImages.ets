import { Game } from './Library';

export interface SteamArtworkAssets {
  asset_url_format?: string;
  library_capsule_2x?: string;
  library_capsule?: string;
  header_2x?: string;
  header?: string;
}
export type ArtworkMap = Record<string, string[]>;

export function steamAssetUrls(appId: number, assets?: SteamArtworkAssets): string[] {
  if (!Number.isInteger(appId) || appId <= 0 || !assets || typeof assets.asset_url_format !== 'string') return [];
  const format: string = assets.asset_url_format;
  const expected: string = 'steam/apps/' + appId.toString() + '/';
  if (!format.startsWith(expected) || !/^steam\/apps\/\d+\/(?:[a-f0-9]{40}\/)?\$\{FILENAME\}(?:\?t=\d+)?$/.test(format)) return [];
  const urls: string[] = [];
  for (const file of [assets.library_capsule_2x, assets.library_capsule, assets.header_2x, assets.header]) {
    if (typeof file !== 'string' || file.length > 240 || !/^[A-Za-z0-9_/-]+\.(?:jpg|png|webp|avif)$/.test(file) || file.includes('..') || file.startsWith('/') || file.includes('//')) continue;
    for (const host of ['https://shared.fastly.steamstatic.com/store_item_assets/', 'https://shared.akamai.steamstatic.com/store_item_assets/']) {
      const url: string = host + format.replace('${FILENAME}', file);
      if (!urls.includes(url)) urls.push(url);
    }
  }
  return urls;
}

export function steamArtworkUrl(game: Game, attempt: number = 0, metadata: string[] = []): string {
  if (!Number.isInteger(game.appId) || game.appId <= 0 || !Number.isInteger(attempt) || attempt < 0) return '';
  const id: string = game.appId.toString();
  const candidates: string[] = metadata.slice();
  for (const base of ['https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/', 'https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/', 'https://cdn.akamai.steamstatic.com/steam/apps/']) {
    for (const file of ['library_600x900.jpg', 'header.jpg']) {
      const url: string = base + id + '/' + file;
      if (!candidates.includes(url)) candidates.push(url);
    }
  }
  if (/^https:\/\//.test(game.iconUrl) && !candidates.includes(game.iconUrl)) candidates.push(game.iconUrl);
  return candidates[attempt] || '';
}
