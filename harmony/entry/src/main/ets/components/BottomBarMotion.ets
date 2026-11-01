import { deviceInfo } from '@kit.BasicServicesKit';
import { curves } from '@kit.ArkUI';
export function bottomBarMotionAvailable(): boolean {
  try { return deviceInfo.sdkApiVersion >= 13; } catch (_) { return false; }
}
// One animator per Tabs owner. Native springs inherit velocity when the gesture reverses.
export class BottomBarMotion {
  private target: boolean | undefined = undefined;
  private showCurve: curves.ICurve | undefined = undefined;
  private hideCurve: curves.ICurve | undefined = undefined;
  reset(): void { this.target = undefined; }
  move(controller: TabsController, context: UIContext, visible: boolean, animated: boolean): boolean {
    if (!bottomBarMotionAvailable()) return false;
    // Repeated renders/page resets must not restart an in-flight animation to the same destination.
    if (animated && this.target === visible) return true;
    const paint = (): void => {
      controller.setTabBarTranslate({ y: visible ? 0 : 112 });
      controller.setTabBarOpacity(visible ? 1 : 0);
    };
    try {
      if (animated) {
        if (this.showCurve === undefined) this.showCurve = curves.springMotion(0.34, 1, 0.10);
        if (this.hideCurve === undefined) this.hideCurve = curves.springMotion(0.26, 1, 0.10);
        context.animateTo({ curve: visible ? this.showCurve : this.hideCurve }, paint);
      } else paint();
      this.target = visible;
      return true;
    } catch (_) { this.target = undefined; return false; }
  }
}
