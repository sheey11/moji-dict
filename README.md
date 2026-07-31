本工具由 Codex 开发。

---

# Moji 辞書

一个 MOJi辞書的原生 macOS 日语查询客户端。界面完全由 SwiftUI/macOS 原生控件构成，网络层使用 `URLSession`。

应用图标取自 Apple App Store 上 MOJi辞書的当前 iOS 图标；图标版权属于
MOJi/Krosea，本项目仍是非官方个人客户端。

![Screenshot](https://github.com/sheey11/moji-dict/blob/main/images/screenshot.png)

## 当前功能

- 输入后 180 ms 防抖查询；
- 词条、文法、例句、真题分组与筛选；
- 默认显示词条结果，左栏只保留汉字和假名；
- 使用系统工具栏搜索项，在 macOS 26 上采用统一的 Liquid Glass 外观；
- 振假名只标注汉字片段，无法可靠分段时回退为上下两行；
- 详情采用 macOS《词典》式文章排版，原生显示中文释义、日文释义；
- 双语例句紧随对应释义，关联词悬停时显示下划线并可继续查询；
- 工具栏提供前进/后退导航，并支持 `⌘[`、`⌘]` 快捷键；
- 词条底部可打开对应的 MOJi 官方网页或在系统“词典”中查询；
- 原生邮箱登录，登录状态和令牌加密保存在 macOS 钥匙串中；
- 自动取消过期请求；
- 搜索结果和词条详情只在内存中缓存；
- 不读取浏览器 Cookie、Local Storage、密码或令牌；
- 密码不会保存；退出登录会删除钥匙串中的会话；
- 浏览历史仅用于当前运行期间的前进/后退，不写入磁盘。

## 接口范围

原型使用 MOJi 网页当前的三个接口：

- `GET /app/mojidict/api/v2/search/all`
- `GET /app/mojidict/api/v1/word/detailInfo`
- `POST /app/mojidict/api/v1/word/related`
- `POST /app/mojidict/api/v1/account/unifiedLogin`

这些是未公开、未承诺稳定的私有接口，可能随时改变，也可能受到限流或安全验证影响。本项目仅适合个人研究，不应批量抓取、公开发布或商业分发。

## 开发与运行

```bash
swift run
```

测试：

```bash
swift test
```

打包为 `.app` 和 `.zip`：

```bash
./scripts/package_app.sh
```

## 发布

推送一个与 `Info.plist` 中应用版本一致的 `v*` 标签，GitHub Actions 会自动测试、打包、校验签名，并把版本化的 `.zip` 和 SHA-256 校验文件发布到 GitHub Releases：

```bash
git tag v0.12.0
git push origin v0.12.0
```

如果标签已经存在，也可以在 GitHub 的 Actions 页面手动运行 `Build and Release`，输入对应标签重新构建或更新 Release 附件。普通分支 push 不会创建 Release。

## 已知边界

- 完整原生详情目前只覆盖普通词条；文法、例句和真题先显示搜索摘要。
- 已支持邮箱登录；收藏、笔记和会员内容尚未接入。
- 应用使用临时 `URLSession`，退出后查询缓存自动消失；登录会话由钥匙串恢复。
- 本项目不是 MOJi 官方客户端，与 MOJi 官方无隶属关系。
