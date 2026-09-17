# Android 包名与旧版数据

审查基线 `3a711c8` 上的 `applicationId` 是 `com.matrixflow.app`。更早的工程值是 `com.matrixflow.matrixflow_native`。Android 把这两个 ID 当成**不同的应用**，各自有独立的数据沙箱。新 APK 安装成功不能证明旧版任务会原位保留。

## 不要做的事

- 不要先卸载旧版再装新版。卸载会删掉旧沙箱里的本地任务和密钥。
- 不要把“构建成功”写成“升级迁移完成”。
- 在用户选定最终包名和签名证书之前，不要再改 `applicationId`。

## 可选路线（需用户决定）

1. **继续使用 `com.matrixflow.app`（当前代码）**  
   旧版 `com.matrixflow.matrixflow_native` 与新版可同时安装。用户在旧版导出 JSON 备份，在新版用覆盖或合并导入。两边签名可以不同，因为不是同一应用的更新。
2. **改回 `com.matrixflow.matrixflow_native`**  
   只有在新包尚未对外分发、且要用旧签名做原位升级时才有意义。一旦 `com.matrixflow.app` 已经发给真实用户，再改回去会把那批用户变成另一套沙箱。

## 当前实现采取的态度

代码保持 `applicationId = "com.matrixflow.app"`，不替用户改回旧 ID。设置页的导入导出仍是把旧数据带进新包的唯一支持路径。本仓库没有跨 `applicationId` 的系统级迁移。

正式发布必须使用独立发布证书；CI 在缺少签名凭据时失败，不会用 debug 证书冒充发行包。
