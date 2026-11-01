import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { POLICY_REVISION, PrivacyStatus } from '../model/PrivacyPolicy';

export class PrivacyStore {
  private async store(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, { name: 'steam_hours_privacy_v1' });
  }
  async read(context: common.UIAbilityContext): Promise<PrivacyStatus> {
    try {
      const store: preferences.Preferences = await this.store(context);
      if (await store.get('cleanupPending', false) === true) return 'blocked';
      if (await store.get('revision', '') !== POLICY_REVISION) return 'pending';
      const allowed: preferences.ValueType = await store.get('allowed', false);
      return allowed === true ? 'granted' : 'declined';
    } catch (_) { return 'pending'; }
  }
  async choose(context: common.UIAbilityContext, allowed: boolean): Promise<void> {
    const store: preferences.Preferences = await this.store(context);
    const revision: preferences.ValueType = await store.get('revision', '');
    const previous: preferences.ValueType = await store.get('allowed', false);
    try {
      await store.put('revision', POLICY_REVISION); await store.put('allowed', allowed); await store.flush();
    } catch (_) {
      try { await store.put('revision', revision); await store.put('allowed', previous); } catch (_) {}
      throw new Error('隐私选择未能保存，请重试。');
    }
  }
  async markCleanup(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await this.store(context);
    try { await store.put('allowed', false); await store.put('cleanupPending', true); await store.flush(); }
    catch (_) { throw new Error('清理状态未能保存，本次联网已关闭。请重试，尚未开始删除数据。'); }
  }
  async finishCleanup(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await this.store(context);
    try { await store.clear(); await store.flush(); }
    catch (_) {
      try { await store.put('allowed', false); await store.put('cleanupPending', true); } catch (_) {}
      throw new Error('删除已执行，但完成状态未能保存。联网保持关闭，请重试。');
    }
  }
}
