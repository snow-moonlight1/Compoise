# Android 应用身份与升级

Android 使用 `applicationId` 区分应用及其本地数据。当前包名是 `com.compoise.app`，命名空间同样是 `com.compoise.app`，入口是 `com.compoise.app.MainActivity`。对外显示名仍是「方寸 · Compoise」。

2026-10-12 发版前把包名从 `com.matrixflow.app` 改了过来。那个旧包名没有发给用户。测试机上如果还装着旧包，它是另一个应用，覆盖安装不会接到新包上，旧任务要用应用内 JSON 备份再导入。

发版之后不要再改 `applicationId`。更换包名会让 Android 把新构建识别为另一款应用，创建独立的数据沙箱。更换发布签名也会阻止原位升级。

正式 Android 发行应使用稳定的发布证书。没有可用发布证书时，CI/发行流程不得把调试签名包作为正式版本分发。签名配置示例见 [`android/key.properties.example`](../android/key.properties.example)。
