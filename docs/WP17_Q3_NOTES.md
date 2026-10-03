# WP17-Q3：可复现的 OCR 质量门禁

基线 `459f9a28cefdcac9196825b2d4ac70250dbf3b8d`，分支 `codex/wp17-q3`，工作树 `D:/Dev_project/martix-wp17-q3`。提交身份只在本工作树设为 `wp17-q3-agent <wp17-q3-agent@local.invalid>`。完整提交 SHA 以该工作树的 `git rev-parse HEAD` 为准。未改 main，未派子 Agent，未 push、amend、tag 或发 Release。

本包只新增 `native/ocr/tools/q3_*.py`、`q3_linux.sh` 和本文件。Q1 脚本、R2 golden、生产 native、适配器、模型锁和 pubspec 未改。没有 Dart 测试：评分器不需要产品代码。字体、PNG、模型、日志都在私有目录，不入库。

## 门禁

`q3_cli.py` 提供 `generate`、`validate`、`score`、`compare`，另有只读 `probe-dict`。场景文字、日期、勾选、父子和换行在画像素之前写死。种子 `17217`。坏真值、重复 ID、图片摘要不符、数据集不同、显式实模型时缺模型或摘要不符，都会失败。`--enable-model` 才加载官方库；默认自测不下载模型、不启动设备。

严格 CER 保留空格，去空白 CER 另报。漏行计入 CER；额外识别、空输出、失败图分开计数，失败图不混进 CER。草稿是独立的 `wp17-q3-draft/1`，本轮实模型没有产品草稿，记为未提供。Q1 三十条标题锁在自测里：空格被删掉时严格 CER 为 55/504，去空白为 0/449。工具不把空格补回识别结果。

## 样本与两次实模型

字体是本机 `Noto Sans SC Regular`，文件内名称表写明 SIL Open Font License 1.1，摘要 `a2b93e6c2db05d6bbbf6f27d413ec73269735b7b679019c8a5aa9670ff0ffbf2`，未再分发。七张图、21 条任务，覆盖中英日、宽 1440 与窄 720、深浅色、换行长标题、日期数字、父子、重复标题、勾选和 400 个盐噪声像素。

Windows Pillow 12.3.0 的数据集是 `q3-s17217-fonta2b93e6c2db0-img9b35d1ecaaa4`，图片集摘要 `9b35d1ecaaa4c00a7fe08191cb10ab7569d1df03e3a634107369cc7324aa6c17`。Linux 上 Pillow 10.2.0 与已有的 Pillow 12.3.0 生成了同一套 PNG，数据集 `q3-s17217-fonta2b93e6c2db0-imgaffa132dfb05`，图片集摘要 `affa132dfb051a740465b592684dd083f533e65c94a9d68044e31934e93284c7`。七张图的摘要都不同，换行后的真值字符串相同。`compare` 因此拒绝把两边当成同一对照，退出码 1。

只读复用的库和模型：Windows `wp17q1-private/native-win-after/Release/matrixflow_ocr.dll` 与 `wp17i5-private/deploy-win`；Linux `wp17q1-private/native-linux-after/libmatrixflow_ocr.so` 与 `wp17i6-private/official-deploy`。字典摘要与锁一致：`d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b`。字典没有 U+0020；首行 U+3000 是 CTC 第 1 类，第 0 类是 blank。生产加载器会去掉行尾 ASCII 空格。这次输出里的词间空格是被删掉，不是换成 U+3000。

| 平台 | 严格 CER | 去空白 CER | 漏行 | 额外行 | 空图 | 失败图 | 日期严格 | 日期去空白 |
|---|---|---|---|---|---|---|---|---|
| Windows | 40/381 | 3/344 | 0 | 16 | 0 | 0 | 8/9 | 9/9 |
| Linux | 42/381 | 5/344 | 0 | 15 | 0 | 0 | 8/9 | 9/9 |

Windows 的 3 个去空白错误，是复选框符 `□` 粘在文字行上。Linux 另外把长英文行里的 `offline` 读成 `ofine`。严格日期少的那一条是带空格的 `2026-10-03 09:30`。额外行主要是空串、`□`、`√`，不进 CER。草稿阶段两边都未提供。

私有根：`C:/Users/20214/AppData/Local/wp17q3-private` 与 `/home/ubuntu/wp17q3-private`。证据是两边的 `fixtures/labels.json`、`score/score.json`，以及 Linux 的 `fixtures-pil123` 与 `score-pil123`。

## 命令与未验

Flutter `D:/Dev_SDKs/Flutter_3.32.8` 与 Linux `/home/ubuntu/develop/flutter` 都是 3.32.8 / Dart 3.8.1，revision `edada7c56e`。`flutter pub get --enforce-lockfile` 退出 0，lock 无内容差异。`flutter analyze --no-pub` 退出 0，无问题。`python native/ocr/tools/q3_selftest.py` 退出 0，10 项通过。`python -m unittest discover -s native/ocr/tools -p test_ocr*.py` 退出 0，28 项里 1 项按平台跳过。`bash -n native/ocr/tools/q3_linux.sh` 退出 0。Windows 与 Linux 的 generate、validate、score、probe-dict 均退出 0。

`lib/`、`test/`、`pubspec.yaml`、`pubspec.lock` 和已跟踪的 Windows registrant 相对基线无内容差异。未跑默认 `flutter test`，也未做应用构建；本包不改产品行为。真实授权截图、Android 设备、产品草稿适配器、物理机字形一致性未验。Linux 两套 Pillow 像素相同，仍不能和 Windows 像素并成一次对照。
