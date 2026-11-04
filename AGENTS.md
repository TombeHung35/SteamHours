# 项目约定

- 这是 SteamHours 0.3.24 原版，保留 Steam 官方网页登录入口和家庭清单查询。不要将其替换为已玩版。
- 保持 ArkTS / ArkUI 代码风格、API 12 兼容与较新接口的能力保护。
- API 密钥与家庭令牌只使用独立 Asset Store 别名，禁止写入源码、普通偏好、日志或测试输出。测试只能使用虚构凭据。
- 联网和远程图片必须遵循 PrivacyAccess 授权代次；撤回后取消操作，旧结果不能回填缓存或界面。
- 时长和成就属于当前查询账号，家庭清单按 AppID 去重。缺失时长为 null，不能伪造零。
- 保留官方材质、顶栏使用 UI Design Kit 的 HdsNavigation、IMMERSIVE_GRADIENT_BLUR 与自适应沉浸光感；禁止用固定矩形 backgroundEffect/backgroundBlurStyle 或自绘遮罩替代官方渐变模糊、底栏无投影与唯一高亮、阻尼动画、安全区绘制和背景独立模糊。
- 修改应用代码后执行相应测试。npm test 不需要 SDK；npm run test:full 需要先在 harmony 目录完成 assembleHap 构建。
- 不提交签名文件、local.properties、IDE 配置、构建目录、依赖缓存、安装包或本机验证日志。
- 不将开源、接口可调用或通过测试描述为 Valve 授权或应用市场审核通过。
