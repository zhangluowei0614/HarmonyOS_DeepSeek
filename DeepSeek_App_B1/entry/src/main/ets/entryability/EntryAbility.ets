import { UIAbility } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'DeepSeekHarmony';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      // Keep the status-bar area reserved at the top, while allowing the Web surface
      // to extend into the bottom navigation/gesture area.
      const avoidArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const statusBarHeightVp: number =
        density > 0 ? avoidArea.topRect.height / density : 0;
      AppStorage.setOrCreate<number>('statusBarHeightVp', statusBarHeightVp);

      mainWindow.setWindowLayoutFullScreen(true).catch((error: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'Failed to enable immersive layout: %{public}s', JSON.stringify(error));
      });

      // Let the app-painted status-bar strip be visible instead of being covered by
      // an opaque system status bar background.
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000'
      }).catch((error: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'Failed to set transparent status bar: %{public}s', JSON.stringify(error));
      });
    } catch (error) {
      const err = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'Failed to obtain the main window: %{public}d %{public}s', err.code, err.message);
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load Index page: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'Index page loaded.');
    });
  }
}
