# 第三方平台与素材说明

- 本项目运行时使用 HarmonyOS / OpenHarmony SDK 接口及 DevEco Studio 构建工具。仓库只包含应用源码和工程配置，不包含 SDK、IDE、平台库或其安装包。使用这些工具须遵守其各自条款。
- 工程的 oh-package.json5 当前没有第三方运行时依赖。自动化检查使用 Node.js 标准模块；Node.js 与 HarmonyOS SDK 不属于本项目 MIT 授权的代码。
- Steam、Valve 及游戏名称、封面、图标、成就图片等归各自权利人所有。应用从 Steam 或其 CDN 按需加载这些内容；MIT 不为这些内容或平台接口提供额外许可。
- tests/fixtures/steam-assets-20261021.json 是用于验证素材 URL 解析的公开响应样本，包含 AppID、素材路径及相关元数据，不含用户数据或密钥；不包含对应游戏图片。
- 项目内的油画时钟图标由 AI 图像生成工具为本项目生成，设计来源和提示词见 ICON-PROMPT.md。未使用 Steam 或 Valve 标志。
- 本项目为独立工具，与 Valve、Steam 或华为不存在本仓库所宣称的官方合作、认证或背书关系。
