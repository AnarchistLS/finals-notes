# Сборка release-APK для Android.
#
# Зачем отдельный скрипт: проект лежит в папке с кириллицей
# («Документы\Проект по умолчанию»), а Dart AOT-снапшоттер не читает такие
# пути — сборка падает на app.dill. Поэтому исходники зеркалятся в ASCII-путь,
# там собирается APK и возвращается в build\app\outputs\flutter-apk.
#
# Запуск:  powershell -ExecutionPolicy Bypass -File tool\build-apk.ps1
# Опции:   -Work <папка для сборки>   (по умолчанию %LOCALAPPDATA%\finals-notes-build)

param(
  [string]$Work = (Join-Path $env:LOCALAPPDATA "finals-notes-build"),
  # Собрать вариант с выключенным рендерером Impeller — для сравнения на телефоне.
  [switch]$NoImpeller
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$apkRel = "build\app\outputs\flutter-apk\app-release.apk"

# --- Flutter ---
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) {
  $flutter = @(
    "C:\src\flutter\bin\flutter.bat",
    (Join-Path $env:LOCALAPPDATA "flutter\bin\flutter.bat")
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $flutter) {
  throw "Не нашёл flutter. Добавьте его в PATH или поправьте путь в этом скрипте."
}

# --- Android SDK и JDK ---
if (-not $env:ANDROID_HOME) {
  $env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA "Android\Sdk"
}
if (-not $env:JAVA_HOME) {
  $env:JAVA_HOME = Join-Path $env:LOCALAPPDATA "Android\jdk\jdk-21"
}
if (-not (Test-Path $env:ANDROID_HOME)) { throw "Нет Android SDK: $env:ANDROID_HOME" }
if (-not (Test-Path $env:JAVA_HOME)) { throw "Нет JDK: $env:JAVA_HOME" }
$env:PATH = "$env:PATH;$env:ANDROID_HOME\platform-tools"

# --- зеркало исходников в ASCII-путь ---
Write-Host "Синхронизирую исходники: $project -> $Work"
robocopy $project $Work /MIR /XD build .dart_tool .gradle .idea /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy завершился с ошибкой $LASTEXITCODE" }

# --- вариант без Impeller (метаданные читаются движком при старте) ---
if ($NoImpeller) {
  Write-Host "Отключаю Impeller в манифесте сборки"
  $manifest = Join-Path $Work "android\app\src\main\AndroidManifest.xml"
  $xml = Get-Content -Raw -Encoding UTF8 $manifest
  if ($xml -notmatch "EnableImpeller") {
    $meta = '    <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />' + "`n"
    $xml = $xml.Replace("    </application>", $meta + "    </application>")
    [System.IO.File]::WriteAllText($manifest, $xml, (New-Object System.Text.UTF8Encoding($false)))
  }
}

# --- сборка ---
Push-Location $Work
try {
  & $flutter build apk --release
  if ($LASTEXITCODE -ne 0) { throw "Сборка не удалась (код $LASTEXITCODE)" }
}
finally {
  Pop-Location
}

# --- APK обратно в проект ---
$built = Join-Path $Work $apkRel
if (-not (Test-Path $built)) { throw "APK не найден: $built" }

$targetDir = Join-Path $project "build\app\outputs\flutter-apk"
New-Item -ItemType Directory -Force $targetDir | Out-Null
$apkName = if ($NoImpeller) { "app-release-noimpeller.apk" } else { "app-release.apk" }
$target = Join-Path $targetDir $apkName
Copy-Item $built $target -Force

$sizeMb = [math]::Round((Get-Item $target).Length / 1MB, 1)
Write-Host ""
Write-Host "Готово: $target ($sizeMb МБ)"
Write-Host "Установка по кабелю: adb install -r `"$target`""
