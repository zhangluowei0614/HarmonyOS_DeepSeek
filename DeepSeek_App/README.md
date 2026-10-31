# DeepSeekHarmony

HarmonyOS Stage-model application that opens `https://chat.deepseek.com` in a full-window
ArkWeb `Web` component.

## Configuration

- Bundle name: `com.example.deepseekharmony`
- Module: `entry` (ArkTS, Stage model)
- Device type: `phone` only
- SDK / API: `26.0.0` (`compileSdkVersion`, `compatibleSdkVersion`, `targetSdkVersion`,
  hvigor `modelVersion`, oh-package `modelVersion`)
- Network permission: `ohos.permission.INTERNET`
- Web settings: explicit desktop user agent, `metaViewport(true)`, DOM storage and JavaScript
  enabled
- Layout: only the `Web` component is present; it fills the safe usable area, with no address
  bar, search bar, or other browser controls

## Build

Open the project with DevEco Studio 26.0.0 (API 26 SDK installed), or run:

```powershell
$env:NODE_HOME = 'D:\DevEco Studio\tools\node'
$env:DEVECO_SDK_HOME = 'D:\DevEco Studio\sdk'
& 'D:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p product=default -p buildMode=debug assembleHap --no-daemon
```

The unsigned HAP is produced at
`entry/build/default/outputs/default/entry-default-unsigned.hap` when no signing configuration
is present.
