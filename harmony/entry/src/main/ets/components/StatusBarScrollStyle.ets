import { deviceInfo } from '@kit.BasicServicesKit';

// Scroll.backToTop is available from API 15. Keep the minimum API 12 page safe.
export class StatusBarScrollStyle implements AttributeModifier<ScrollAttribute> {
  applyNormalAttribute(instance: ScrollAttribute): void {
    try {
      if (deviceInfo.sdkApiVersion >= 15) instance.backToTop(true);
    } catch (_) {
      // Unsupported system integration must not prevent the scrollable page from rendering.
    }
  }
}
