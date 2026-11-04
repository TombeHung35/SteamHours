import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial, ScrollEffectType as HdsScrollEffectType, TitleBarStyleOptions } from '@kit.UIDesignKit';

// HDS is optional: do not touch its material enums on the API 12 fallback.
export class OfficialTitleStyle {
  readonly supported: boolean;
  private cached: TitleBarStyleOptions | undefined = undefined;

  constructor() {
    let supported: boolean = false;
    try {
      supported = deviceInfo.sdkApiVersion >= 26 && deviceInfo.apiAvailable('26.0.0') &&
        canIUse('SystemCapability.UIDesign.HDSComponent.Core');
    } catch (_) {}
    this.supported = supported;
  }

  options(): TitleBarStyleOptions | undefined {
    if (!this.supported || !deviceInfo.apiAvailable('26.0.0')) return undefined;
    if (this.cached === undefined) {
      this.cached = {
        scrollEffectOpts: { enableScrollEffect: false, scrollEffectType: HdsScrollEffectType.IMMERSIVE_GRADIENT_BLUR },
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE }
      };
    }
    return this.cached;
  }
}
