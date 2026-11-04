# 游戏时光 · SteamHours

在鸿蒙上查看 Steam 游戏库、游玩时长与成就。

<img src="harmony/AppScope/resources/base/media/app_icon.png" alt="游戏时光图标" width="112" />

本仓库公开的是 **0.3.24 原版**，保留 Steam 网页登录和家庭共享游戏查询功能。应用由TombeHung开发，手机直连 Steam，无需自建服务器。本仓库不包含已玩版。

## 功能

- 查看 Steam 昵称、头像、个人游戏库、累计时长和最近两周时长。
- 登录本人 Steam 账号后，合并家庭可共享游戏，并按 AppID 去重。
- 查询当前账号的游戏成就与解锁进度。
- 按累计时长、两周时长、游戏名称或最近游玩排序，支持搜索和本地缓存。
- 支持日间与夜间模式、主题色、自定义背景、图片取色、模糊与卡片透明度。
- 在支持 UI Design Kit 的 API 26 设备上，顶栏使用 HdsNavigation 官方 IMMERSIVE_GRADIENT_BLUR 与自适应沉浸光感；旧系统保留普通导航回退。
- 提供官方系统材质、状态栏回顶、系统栏沉浸和自动收起底栏；较新 API 有能力检查与降级。
- 提供首次隐私告知、离线演示、撤回同意、清除全部本地数据、关于和反馈。

## 使用

1. 首次启动时阅读隐私政策，选择是否启用联网；拒绝后仍可使用离线演示。
2. 在“游戏账号”填写 SteamID64 或个人主页链接，以及你自己的 [Steam Web API 密钥](https://steamcommunity.com/dev/apikey)。
3. 点击“读取游戏库”。展示范围取决于账号隐私设置及 Steam 实际返回的数据。
4. 如需家庭清单，开启“包含家庭共享”，点击“登录 Steam”，在 Steam 官方网页中登录本人账号，再点击“完成登录”。查询账号应与登录账号一致。
5. 在游戏详情中查看本人成就，在设置中调整外观或管理本地数据。

家庭游戏的时长和成就属于当前查询账号，不会累计其他家庭成员的游玩数据。未返回的时长显示为未知，不等同于零。

## 家庭功能的边界

家庭登录通过 ArkWeb 打开 Steam 官方网站，并读取当前会话返回的授权令牌。家庭查询依赖 Steam 商店会话及 IFamilyGroupsService 相关接口，这些接口可能调整、失效或返回不完整结果。本项目没有获得 Valve 官方背书，也不承诺该实现具有面向所有第三方应用的稳定开放授权。

MIT 许可证只许可本项目的代码，不授予 Steam 接口、账号数据、游戏封面或商标的额外权利。自行部署、分发或上架前，请核实相应平台的使用条件。不要提交密码、API 密钥、会话令牌或带凭据的网络日志。

## 构建

项目使用 ArkTS、ArkUI 和 Stage 模型。目标 SDK 为 HarmonyOS 7 / API 26，最低兼容 API 12。新材质在不支持的系统和设备上会降级。

1. 安装 DevEco Studio，以及项目所需的 HarmonyOS SDK。
2. 在 DevEco Studio 中打开本仓库的 `harmony` 文件夹。
3. 选择 `default` 产品，执行 **Build → Build Hap(s)**。
4. 运行到设备时，在 IDE 中配置你自己的签名。仓库不包含证书、私钥、签名 Profile 或本机 SDK 路径。

如使用命令行，可在 `harmony` 目录使用本机 DevEco Studio 自带的 Node.js 和 Hvigor 执行：

```text
node <DevEco Studio>/tools/hvigor/bin/hvigorw.js --mode module -p product=default assembleHap --no-daemon
```

需要按本机安装设置 `DEVECO_SDK_HOME`、`JAVA_HOME` 和工具路径。未签名构建输出在 `harmony/entry/build/default/outputs/default/`。

当前包名为 `com.tombehung.steamhours`。开发你自己的分发版本时，应使用自己的包名、签名和应用市场登记信息。

## 测试

测试使用 Node.js 内置测试运行器及平台 API 模拟，不需要真实 Steam 凭据。请使用支持 `node:module.stripTypeScriptTypes` 的 Node.js 22.13+。

```sh
npm test
```

此命令运行不依赖 ArkUI 编译产物的检查。完成上面的 `assembleHap` 构建后，再运行完整检查：

```sh
npm run test:full
```

完整检查包含执行实际 ArkUI 编译输出的界面测试，编译产物不随仓库分发。测试覆盖接口数据处理、家庭合并、成就、缓存、外观、隐私撤回和清理竞态；模拟测试不能替代真机和真实 Steam 账号验证。

## 目录

```text
harmony/                 HarmonyOS 工程
  entry/src/main/ets/    页面、平台组件、模型与服务
tests/                   自动化检查和公开素材响应样本
scripts/test.mjs         跨平台测试入口
PRIVACY-POLICY.md        当前原版隐私政策
privacy-policy.html      可离线打开的隐私网页
THIRD_PARTY_NOTICES.md   平台与素材说明
```

## 开源配置与隐私

API 密钥和家庭会话令牌使用设备 Asset Store 的独立别名保存，不提交到普通配置或仓库。联网操作受隐私同意状态控制；撤回或清除会取消在途请求。详见[隐私政策](PRIVACY-POLICY.md)。

使用问题请在本仓库创建 Issue，提供系统版本、应用版本和复现步骤；不要公开凭据或其他个人敏感信息。应用内提供 GitHub 反馈入口与不含账号数据的反馈模板。安全问题请参阅 [SECURITY.md](SECURITY.md)。

## 许可证

采用 [MIT License](LICENSE)。第三方平台、游戏素材及商标的权利归各自权利人所有，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
