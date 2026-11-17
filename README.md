# 胖乖洗衣 · iOS

只做**胖乖生活（qiekj）洗衣机**这一件事的 iOS 客户端：扫码 → 选套餐 → 下单 → **扫码支付** → 看订单 / 撤销。

界面沿用扁平深色风格（纯色卡片 + 细描边 + 底部悬浮胶囊导航），四个页签：洗衣 / 订单 / 日志 / 设置。

## 功能范围

| 做 | 不做 |
| --- | --- |
| 手机号 + 短信验证码登录（`/user/reg`） | 洗澡、取水、饮水机 |
| 扫码 / 手填机器码解析设备（`/goods/scan/v2`） | 智慧笑联等第三方小程序跳转 |
| 设备详情与套餐（`/goods/normal/details`、`/goods/normal/skus`） | 支付宝 SDK 集成（改用二维码） |
| 下单（`/trade/create`）+ 取支付串（`/pay/unify/prePay`） | 钱包充值、会员开通 |
| 应用内二维码扫码付款 + 拉起支付宝 | 消息推送、多端同步 |
| 支付结果查询（`/order/pay_status`）、订单列表、撤销（`/order/cancel`） | 插件系统 |

## 协议链路

签名：`SHA256("appSecret=..&channel=..&timestamp=..&token=..&version=..&<path>")`，十六进制小写，放在请求头 `sign`。

```
POST https://userapi.qiekj.com<path>
Authorization: <token>
Version: 1.143.0
channel: android_app
timestamp: <ms>
sign: <sha256>
Content-Type: application/x-www-form-urlencoded;charset=UTF-8
```

洗衣机（`categoryCode=wash`）主链路：

1. `POST /common/sms/sendCode` — `phone`、`template=1`
2. `POST /user/reg` — `channel`、`phone`、`verify` → `data.token`
3. `POST /user/info` — 当前手机号 / 余额 / 会员
4. `POST /goods/latestUsed` — `categoryCode=wash` → 最近用过的机器
5. `POST /goods/scan/v2` — `NQT=<机器码>` → `data.id` 即 goodsId
6. `POST /goods/normal/details` — `goodsId` → `orgId`、名称、网点、客服电话
7. `POST /goods/normal/skus` — `goodsId` → 套餐列表（`skuId`、`price`、`feature`）
8. `POST /trade/create` —
   `promotions=[{"assetId":"0","oldPromotionId":"3482","orgId":"<orgId>","promotionId":"0","promotionType":"4"}]`
   `items=[{"amount":"1","goodsId":"<goodsId>","num":"1","skuId":"<skuId>","soldType":"1"}]`
   → `data.orderId`（就是 orderNo）
9. `POST /pay/unify/prePay` — `orderNo`、`payType=13` → `data.prepayParam`（支付宝 orderString）
10. `POST /order/pay_status` — `orderNo`、`payType` → `data` 布尔
11. `POST /order/list` — `page`、`pageSize`、`orderStatus=""`
12. `POST /order/cancel` — `orderId`

### 扫码支付怎么做的

不集成支付宝 SDK。`prepayParam` 是标准 orderString，App 把它包成官方收银台入口：

```
alipays://platformapi/startapp?appId=20000125&orderSuffix=<urlencode(prepayParam)>
```

- 用 `CIFilter.qrCodeGenerator` 画成二维码，另一台手机用支付宝「扫一扫」即可付款；
- 也可以点「打开支付宝付款」，直接 `UIApplication.open` 拉起；
- 付完点「我付好了」，调 `/order/pay_status` 确认，成功后清掉本地挂单。

### 几个实测坑

- `code 2128`：上一笔未支付订单会挡住新单，`data.incompleteOrderId` 就是那笔，先去订单页处理。
- `code 2` / `401`：token 失效，App 会自动退出登录并提示重登。
- `/goods/scan/v2` 字段名必须是 `NQT`（也接受 `SN`），扫出来的整条链接由 `AppStore.normalizedCode` 解析。
- `trade/create` 一旦成功，订单就真实存在；不付款就点「撤销订单」（`/order/cancel`），不要重复下单。

## 目录

```
pangguai-ios/
├── project.yml                     XcodeGen 工程定义（iOS 16，未签名）
├── Support/Info.plist              由 xcodegen 生成
├── Sources/
│   ├── App/PangguaiApp.swift
│   ├── Core/
│   │   ├── AppStore.swift          登录态、设备、套餐、挂单、订单、日志
│   │   ├── Crypto.swift            SHA256 / 表单编码
│   │   ├── Keychain.swift          token 存放
│   │   ├── Models.swift            用户 / 设备 / 套餐 / 订单 / 挂单
│   │   ├── PGClient.swift          全部接口
│   │   └── PGProtocol.swift        常量、签名、支付宝 scheme、响应包装
│   └── Views/
│       ├── AppShell.swift          底部悬浮胶囊导航
│       ├── FlatTheme.swift         扁平色板与组件
│       ├── LaundryView.swift       洗衣主页
│       ├── LoginSheet.swift        验证码登录
│       ├── ScanSheet.swift         AVFoundation 扫码 + 手填
│       ├── PaySheet.swift          二维码 / 拉起支付宝 / 查支付
│       ├── OrdersView.swift        订单与撤销
│       ├── LogView.swift           请求日志
│       └── SettingsView.swift      账号、支付方式、自动检测、接口信息
└── scripts/                        打包、校验、发布、图标
```

## 构建

### 方式 A：GitHub Actions（推荐）

仓库里的 `.github/workflows/build-unsigned-ipa.yml` 用 `macos-15-intel` 出未签名 ipa：

```powershell
$env:ZF_GITHUB_TOKEN = 'ghp_xxx'
powershell -ExecutionPolicy Bypass -File scripts\publish-github.ps1 -Public
```

推送完成后脚本会自己 dispatch、轮询、下载 `dist/Pangguai-unsigned.ipa`。

### 方式 B：本地 Mac

```bash
brew install xcodegen
bash scripts/build-ipa.sh          # 产出 dist/Pangguai-unsigned.ipa
```

### 安装

未签名 ipa 需要重签后安装：Sideloadly（数据线 + Apple ID）、AltStore、TrollStore（已越狱/巨魔设备直接装）。

打开 App 等 2 秒会自动检测登录状态；没登录会提示去「洗衣 → 登录」。

## 已知限制

- 只实现洗衣机，其它品类接口没有接。
- 支付宝 SDK 未集成，所以「付完自动回跳」不存在，需要手动点「我付好了」。
- iOS 后台不能常驻，守护只在 App 前台时生效。
- App 用了这三个开源项目的协议资料：`Yunanriv-hub/Cumpus`、`Night-stars-1/wash`、`Baito-84170/baotuquan-light`。

## 许可

仅供个人学习研究使用，账号与支付风险自负。
