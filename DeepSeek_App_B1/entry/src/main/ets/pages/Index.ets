import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { inputMethod } from '@kit.IMEKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'DeepSeekHarmony';
const PAGE_URL: string = 'https://chat.deepseek.com';
// Desktop Chrome UA. Keep this constant as the single source of truth for every request,
// including server-side redirects and subresources.
const DESKTOP_USER_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

interface TopStripColorRun {
  color: string;
  weight: number;
  widthPercent: number;
}

class TopStripBridge {
  colorCallback: ((data: string) => void) | undefined = undefined;
  chatListCallback: ((visible: boolean) => void) | undefined = undefined;

  updateTopStripColors(data: string): void {
    if (this.colorCallback) {
      this.colorCallback(data);
    }
  }

  setChatListVisible(visible: boolean): void {
    if (this.chatListCallback) {
      this.chatListCallback(visible);
    }
  }
}

@Entry
@Component
struct Index {
  private readonly controller: webview.WebviewController = new webview.WebviewController();
  @StorageProp('statusBarHeightVp') statusBarHeightVp: number = 0;

  private autoImeGuardActive: boolean = false;
  private autoImeGuardStartedAt: number = 0;
  private topStripSampleTimer: number = -1;
  private topStripBridge: TopStripBridge = new TopStripBridge();
  @State topStripRuns: TopStripColorRun[] = [];
  @State isChatListOpen: boolean = false;
  @State chatListLeftPercent: number = 785 / (785 + 302) * 100;

  aboutToAppear(): void {
    this.topStripBridge.colorCallback = (data: string) => {
      this.applyTopStripColors(data);
    };
    this.topStripBridge.chatListCallback = (visible: boolean) => {
      this.isChatListOpen = visible;
    };
  }

  private applyDesktopUserAgent(): void {
    try {
      // onControllerAttached runs after the controller is bound to the Web component and
      // before the initial page navigation, so the first request already uses this UA.
      this.controller.setCustomUserAgent(DESKTOP_USER_AGENT);
      hilog.info(DOMAIN, TAG, '%{public}s', 'Desktop user agent applied before page load.');
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to set desktop user agent: %{public}d %{public}s', err.code, err.message);
    }
  }

  private dismissAutoKeyboard(): void {
    if (!this.autoImeGuardActive) {
      return;
    }

    try {
      // The Web component itself must release focus; otherwise the page may request IME again.
      this.getUIContext().getFocusController().clearFocus();
    } catch (error) {
      hilog.debug(DOMAIN, TAG, '%{public}s', 'Unable to clear component focus.');
    }

    try {
      // DeepSeek focuses its editor after opening a conversation from the sidebar.
      // Blur the focused web element so the keyboard is not requested again.
      this.controller.runJavaScript(
        `(function() {
          if (document.activeElement && document.activeElement.blur) {
            document.activeElement.blur();
          }
          var backdrop = document.querySelector('._4cbcd96');
          if (!backdrop) {
            var nodes = document.querySelectorAll('div');
            for (var i = 0; i < nodes.length; i++) {
              var style = window.getComputedStyle(nodes[i]);
              if (style.position === 'fixed' &&
                  style.zIndex === '1001' &&
                  style.backgroundColor.indexOf('rgba(0, 0, 0') === 0 &&
                  style.pointerEvents !== 'none' &&
                  style.opacity !== '0') {
                backdrop = nodes[i];
                break;
              }
            }
          }
          if (backdrop) {
            var backdropStyle = window.getComputedStyle(backdrop);
            if (backdropStyle.pointerEvents !== 'none' && backdropStyle.opacity !== '0') {
              backdrop.click();
            }
          }
        })();`
      ).catch(() => {
        // The document can be between navigations; there is nothing to close yet.
      });
    } catch (error) {
      hilog.debug(DOMAIN, TAG, '%{public}s', 'Unable to blur the active web element.');
    }

    try {
      inputMethod.getController().stopInputSession().catch(() => {
        // No active input session is expected when no editor has focus.
      });
    } catch (error) {
      hilog.debug(DOMAIN, TAG, '%{public}s', 'Input method controller is not available.');
    }
  }

  private handleMainFrameNavigation(): void {
    this.autoImeGuardActive = true;
    this.autoImeGuardStartedAt = Date.now();
    this.dismissAutoKeyboard();

    // DeepSeek may focus the editor after the route content has rendered.
    setTimeout(() => {
      this.dismissAutoKeyboard();
    }, 150);
    setTimeout(() => {
      this.dismissAutoKeyboard();
    }, 400);
    setTimeout(() => {
      this.dismissAutoKeyboard();
    }, 700);
  }

  private scheduleTopStripSample(): void {
    if (this.topStripSampleTimer !== -1) {
      clearTimeout(this.topStripSampleTimer);
    }
    this.topStripSampleTimer = setTimeout(() => {
      this.topStripSampleTimer = -1;
      this.captureTopStripColors();
    }, 100);
  }

  private captureTopStripColors(): void {
    const script: string = `
      (function() {
        function parseColor(value) {
          if (!value) {
            return null;
          }
          var text = value.trim();
          if (text.indexOf('rgb(') !== 0 && text.indexOf('rgba(') !== 0) {
            return null;
          }
          var open = text.indexOf('(');
          var close = text.lastIndexOf(')');
          if (open < 0 || close < 0) {
            return null;
          }
          var parts = text.substring(open + 1, close).split(',');
          if (parts.length < 3) {
            return null;
          }
          var r = parseFloat(parts[0]);
          var g = parseFloat(parts[1]);
          var b = parseFloat(parts[2]);
          var a = parts.length > 3 ? parseFloat(parts[3]) : 1;
          if (isNaN(r) || isNaN(g) || isNaN(b) || isNaN(a)) {
            return null;
          }
          return { r: r, g: g, b: b, a: Math.max(0, Math.min(1, a)) };
        }

        function hex(value) {
          var n = Math.max(0, Math.min(255, Math.round(value))).toString(16);
          return n.length === 1 ? '0' + n : n;
        }

        function backgroundColorAt(x) {
          var found = document.elementFromPoint(x + 0.5, 2);
          var layers = [];
          var node = found;
          while (node && node.nodeType === 1) {
            var style = window.getComputedStyle(node);
            var color = parseColor(style.backgroundColor);
            if (color && color.a > 0) {
              layers.push(color);
              if (color.a >= 0.999) {
                break;
              }
            }
            node = node.parentElement;
          }

          var r = 255;
          var g = 255;
          var b = 255;
          for (var i = layers.length - 1; i >= 0; i--) {
            var layer = layers[i];
            r = layer.r * layer.a + r * (1 - layer.a);
            g = layer.g * layer.a + g * (1 - layer.a);
            b = layer.b * layer.a + b * (1 - layer.a);
          }
          return '#' + hex(r) + hex(g) + hex(b);
        }

        var count = Math.ceil(window.innerWidth);
        var colors = [];
        for (var x = 0; x < count; x++) {
          colors.push(backgroundColorAt(x));
        }
        var payload = colors.join(',');
        if (window.deepSeekHarmonyTopStrip &&
            window.deepSeekHarmonyTopStrip.updateTopStripColors) {
          window.deepSeekHarmonyTopStrip.updateTopStripColors(payload);
        }
        return payload;
      })();
    `;

    try {
      this.controller.runJavaScript(script).then((result: string) => {
        hilog.info(DOMAIN, TAG, 'Top strip sample result length: %{public}d', result ? result.length : 0);
        this.applyTopStripColors(result);
      }).catch((error: BusinessError) => {
        hilog.debug(DOMAIN, TAG, 'Top strip sampling failed: %{public}d %{public}s', error.code, error.message);
      });
    } catch (error) {
      hilog.debug(DOMAIN, TAG, '%{public}s', 'Unable to sample the top strip.');
    }
  }

  private applyTopStripColors(result: string): void {
    if (!result) {
      return;
    }

    let value: string = result.trim();
    for (let attempt = 0; attempt < 2; attempt++) {
      if (value.startsWith('"') && value.endsWith('"')) {
        try {
          value = JSON.parse(value) as string;
        } catch (error) {
          return;
        }
      } else {
        break;
      }
    }

    if (!value) {
      return;
    }

    const colors: string[] = value.split(',');
    const hexColor: RegExp = /^#[0-9a-fA-F]{6}$/;
    const runs: TopStripColorRun[] = [];
    for (let i = 0; i < colors.length; i++) {
      const color: string = colors[i].trim();
      if (!hexColor.test(color)) {
        continue;
      }
      if (runs.length > 0 && runs[runs.length - 1].color === color) {
        runs[runs.length - 1].weight += 1;
      } else {
        runs.push({ color: color, weight: 1, widthPercent: 0 });
      }
    }

    let totalWeight: number = 0;
    for (let i = 0; i < runs.length; i++) {
      totalWeight += runs[i].weight;
    }
    if (totalWeight > 0) {
      let assignedPercent: number = 0;
      for (let i = 0; i < runs.length; i++) {
        if (i === runs.length - 1) {
          runs[i].widthPercent = Math.max(0, 100 - assignedPercent);
        } else {
          runs[i].widthPercent = runs[i].weight * 100 / totalWeight;
          assignedPercent += runs[i].widthPercent;
        }
      }
      this.topStripRuns = runs;
      hilog.info(DOMAIN, TAG, 'Top strip colors applied: %{public}d runs', runs.length);
    }
  }

  private installChatListWatcher(): void {
    const script: string = `
      (function() {
        if (window.__deepSeekHarmonyChatListWatcherInstalled) {
          return;
        }
        window.__deepSeekHarmonyChatListWatcherInstalled = true;

        var lastVisible = null;
        var timer = 0;

        function isChatListOpen() {
          var backdrop = document.querySelector('._4cbcd96');
          if (!backdrop) {
            return false;
          }
          var sidebar = document.querySelector('.dc04ec1d');
          if (backdrop.classList.contains('_70b689f') ||
              (sidebar && sidebar.classList.contains('a02af2e6'))) {
            return false;
          }
          var style = window.getComputedStyle(backdrop);
          return style.display !== 'none' &&
            style.visibility !== 'hidden' &&
            style.pointerEvents !== 'none' &&
            style.opacity !== '0';
        }

        function notify() {
          var visible = isChatListOpen();
          if (visible === lastVisible) {
            return;
          }
          lastVisible = visible;

          if (window.deepSeekHarmonyTopStrip &&
              window.deepSeekHarmonyTopStrip.setChatListVisible) {
            window.deepSeekHarmonyTopStrip.setChatListVisible(visible);
          }
        }

        function scheduleNotify() {
          if (timer) {
            return;
          }
          timer = window.setTimeout(function() {
            timer = 0;
            notify();
          }, 16);
        }

        if (document.body) {
          var observer = new MutationObserver(scheduleNotify);
          observer.observe(document.body, {
            subtree: true,
            childList: true,
            attributes: true,
            attributeFilter: ['class', 'style']
          });
        }
        notify();
      })();
    `;

    try {
      this.controller.runJavaScript(script).catch(() => {
        // The page is still loading; installation is retried on the next page end.
      });
    } catch (error) {
      hilog.debug(DOMAIN, TAG, '%{public}s', 'Unable to install the chat list watcher.');
    }
  }

  private installAutoFocusGuard(): void {
    const script: string = `
      (function() {
        if (window.__deepSeekHarmonyAutoFocusGuardInstalled) {
          return;
        }
        window.__deepSeekHarmonyAutoFocusGuardInstalled = true;
        window.__deepSeekHarmonySuppressAutoFocus = true;

        function isEditable(element) {
          if (!element || !element.tagName) {
            return false;
          }
          var tag = element.tagName.toLowerCase();
          if (tag === 'textarea') {
            return true;
          }
          if (tag === 'input') {
            var type = (element.type || 'text').toLowerCase();
            return type === 'text' || type === 'search' || type === 'email' ||
              type === 'number' || type === 'password' || type === 'tel' || type === 'url';
          }
          if (element.isContentEditable) {
            return true;
          }
          var role = element.getAttribute && element.getAttribute('role');
          return role === 'textbox' || role === 'searchbox';
        }

        function blurEditable() {
          var active = document.activeElement;
          if (isEditable(active) && active.blur) {
            active.blur();
          }
        }

        function armAutoFocusGuard() {
          window.__deepSeekHarmonySuppressAutoFocus = true;
          blurEditable();
        }

        function disarmAutoFocusGuard() {
          window.__deepSeekHarmonySuppressAutoFocus = false;
        }

        var proto = window.HTMLElement && window.HTMLElement.prototype;
        if (proto && proto.focus) {
          var nativeFocus = proto.focus;
          proto.focus = function() {
            if (window.__deepSeekHarmonySuppressAutoFocus && isEditable(this)) {
              return;
            }
            return nativeFocus.apply(this, arguments);
          };
        }

        document.addEventListener('focusin', function(event) {
          if (window.__deepSeekHarmonySuppressAutoFocus && isEditable(event.target)) {
            if (event.target.blur) {
              event.target.blur();
            }
          }
        }, true);

        function isConversationAnchor(event) {
          if (!event || !event.target) {
            return false;
          }
          var node = event.target;
          var anchor = null;
          var nestedControl = false;
          while (node && node !== document) {
            if (node.tagName === 'BUTTON' ||
                (node.getAttribute && node.getAttribute('role') === 'button')) {
              nestedControl = true;
            }
            if (node.tagName === 'A') {
              anchor = node;
              break;
            }
            node = node.parentElement;
          }
          if (!anchor || !anchor.href || nestedControl) {
            return false;
          }
          if (!new RegExp('/a/[^/?#]+/s/[^/?#]+').test(anchor.href)) {
            return false;
          }
          try {
            var target = new URL(anchor.href, window.location.href);
            return target.pathname !== window.location.pathname;
          } catch (error) {
            return false;
          }
        }

        function handleGesture(event) {
          if (isConversationAnchor(event)) {
            armAutoFocusGuard();
          } else {
            disarmAutoFocusGuard();
          }
        }

        document.addEventListener('pointerdown', handleGesture, true);
        document.addEventListener('touchstart', handleGesture, true);
        document.addEventListener('mousedown', handleGesture, true);
        document.addEventListener('keydown', function() {
          disarmAutoFocusGuard();
        }, true);
        document.addEventListener('click', function(event) {
          if (isConversationAnchor(event)) {
            armAutoFocusGuard();
          }
        }, true);
      })();
    `;

    try {
      this.controller.runJavaScript(script).catch(() => {
        // The page is still loading; installation is retried on the next page end.
      });
    } catch (error) {
      hilog.debug(DOMAIN, TAG, '%{public}s', 'Unable to install the auto-focus guard.');
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        Web({ src: PAGE_URL, controller: this.controller })
        // The desktop UA has no "Mobile" token, so ArkWeb disables the page viewport by default.
        // Explicitly enabling metaViewport keeps the page's viewport meta tag effective.
        .metaViewport(true)
        .javaScriptAccess(true)
        // chat.deepseek.com uses local storage for its web client state.
        .domStorageAccess(true)
        .width('100%')
        .height('100%')
        // Extend only the bottom edge; the root container reserves the status-bar height.
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onControllerAttached(() => {
          this.applyDesktopUserAgent();
        })
        .onNavigationEntryCommitted((details) => {
          if (details.isMainFrame) {
            this.handleMainFrameNavigation();
          }
        })
        .onPageEnd(() => {
          this.installAutoFocusGuard();
          this.handleMainFrameNavigation();
        })
        .onTouch((event) => {
          // Ignore the touch that caused the navigation; a later user tap is intentional focus.
          if (event.type === TouchType.Down && Date.now() - this.autoImeGuardStartedAt > 100) {
            this.autoImeGuardActive = false;
          }
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeightVp })
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
  }
}
