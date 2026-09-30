param([string]$GradleCache = (Join-Path $env:USERPROFILE '.gradle\caches\modules-2\files-2.1'))
$ErrorActionPreference = 'Stop'
$stageRoot = Split-Path -Parent $PSScriptRoot
$stageTemporary = [System.IO.Path]::GetFullPath($env:TEMP)
$stageOutput = Join-Path $stageTemporary ('wp17-i3b-jvm-' + [guid]::NewGuid())
$stageLibraries = @(
  'org.jetbrains.kotlin\kotlin-compiler-embeddable\2.0.21',
  'org.jetbrains.kotlin\kotlin-stdlib\2.0.21',
  'org.jetbrains.kotlin\kotlin-script-runtime\2.0.21',
  'org.jetbrains.intellij.deps\trove4j',
  'org.jetbrains\annotations\13.0',
  'org.jetbrains.kotlinx\kotlinx-coroutines-core-jvm\1.6.4'
)
$stageClasspath = foreach ($stageLibrary in $stageLibraries) {
  Get-ChildItem -LiteralPath (Join-Path $GradleCache $stageLibrary) -Recurse -Filter '*.jar' |
    Select-Object -ExpandProperty FullName
}
$stageStdlib = $stageClasspath | Where-Object { $_ -like '*\kotlin-stdlib-2.0.21.jar' } | Select-Object -First 1
New-Item -ItemType Directory -Path $stageOutput | Out-Null
try {
  & java -cp ($stageClasspath -join ';') org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -classpath $stageStdlib -d $stageOutput `
    (Join-Path $stageRoot 'android\app\src\main\kotlin\com\matrixflow\matrixflow_native\ScreenshotPngStage.kt') `
    (Join-Path $PSScriptRoot 'wp17_i3b_android_stream_test.kt')
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & java -cp "$stageOutput;$stageStdlib" com.matrixflow.matrixflow_native.Wp17_i3b_android_stream_testKt
  exit $LASTEXITCODE
} finally {
  $stageResolved = [System.IO.Path]::GetFullPath($stageOutput)
  if ((Split-Path -Parent $stageResolved) -eq $stageTemporary -and
      (Split-Path -Leaf $stageResolved) -like 'wp17-i3b-jvm-*') {
    Remove-Item -LiteralPath $stageResolved -Recurse -Force
  }
}
