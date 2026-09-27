# Android 应用身份与升级

Android 使用 `applicationId` 区分应用及其本地数据。当前包名为 `com.matrixflow.app`，对外显示名为「方寸 · Compoise」。包名保留为历史安装身份，以便同一签名下的后续版本识别现有安装和本地数据；品牌更名不要求改变包名。

不要在普通品牌或图标更新中修改 `applicationId`。更换包名会让 Android 把新构建识别为另一款应用，创建独立的数据沙箱；旧任务需要通过应用内 JSON 备份转移。更换发布签名也会阻止原位升级。

正式 Android 发行应使用稳定的发布证书。没有可用发布证书时，CI/发行流程不得把调试签名包作为正式版本分发。签名配置示例见 [`android/key.properties.example`](../android/key.properties.example)。
