# Непрерывные проверки Godot

Файл [`.github/workflows/godot-ci.yml`](../.github/workflows/godot-ci.yml) запускается на `push`, `pull_request` и вручную через **Actions → Godot CI → Run workflow**. Job работает на Windows, загружает [официальный Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/), проверяет его версию и вызывает существующий `tests/run_checks.ps1`. Скрипт выполняет headless-импорт проекта, smoke и все регрессионные тесты. При ошибке журналы `.godot/verify05_*.log` доступны как артефакт `godot-test-logs` в запущенном workflow.

Локально тот же набор запускается так:

```powershell
./tests/run_checks.ps1 -GodotPath 'C:\путь\к\Godot_v4.7.2-stable_win64_console.exe'
```

Проверки используют отдельные файлы в `.godot/` и не должны записывать пользовательский `user://savegame.json`. CI не экспортирует игру, не публикует сборку и не меняет игровой проект. Графические снимки и ручное прохождение этим headless-набором не заменяются.

Workflow начнёт выполняться на GitHub после того, как файл и сам проект будут добавлены в репозиторий. Наличие локального workflow само по себе не запускает GitHub Actions.
