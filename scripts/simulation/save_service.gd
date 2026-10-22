extends RefCounted
## Один локальный слот. Запись во временный файл, предыдущая версия в .bak.

const DEFAULT_PATH := "user://savegame.json"
const MAX_BYTES := 16777216

static func save_game(state: RefCounted, path: String = DEFAULT_PATH) -> String:
	# Whitespace is a large share of social histories. Compact JSON keeps the
	# existing schema, migration and corruption checks while reducing disk use.
	var text := JSON.stringify(state.to_save(), "", true, true)
	if text.to_utf8_buffer().size()>MAX_BYTES:
		return "Сохранение превышает допустимый размер. Предыдущий слот сохранён."
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Не удалось записать сохранение: " + error_string(FileAccess.get_open_error())
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "Ошибка записи сохранения: " + error_string(write_error)
	var backup := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			var remove_error := DirAccess.remove_absolute(backup)
			if remove_error != OK:
				return "Не удалось обновить резервную копию: " + error_string(remove_error)
		var backup_error := DirAccess.rename_absolute(path, backup)
		if backup_error != OK:
			return "Не удалось создать резервную копию: " + error_string(backup_error)
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		if FileAccess.file_exists(backup) and not FileAccess.file_exists(path):
			DirAccess.rename_absolute(backup, path)
		return "Не удалось завершить сохранение: " + error_string(rename_error)
	return ""

static func load_game(state: RefCounted, path: String = DEFAULT_PATH) -> String:
	if not FileAccess.file_exists(path):
		return "Сохранение пока не создано. Нажмите K."
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Не удалось открыть сохранение: " + error_string(FileAccess.get_open_error())
	if file.get_length() > MAX_BYTES:
		return "Сохранение слишком большое. Текущая игра не изменена."
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		return "Сохранение повреждено. Текущая игра не изменена."
	if not state.apply_save(json.data):
		return "Несовместимые или неверные данные сохранения. Текущая игра не изменена."
	return ""
