extends RefCounted
## Один фиксированный шаг = одна игровая минута; 1× = две минуты за секунду.

const SPEEDS: Array[float] = [0.25, 1, 4, 12, 60]
const MINUTES_PER_SECOND := 2.0
var minute := 480
var fraction := 0.0
var speed := 1.0
var paused := false
var threatened := false

func display() -> String:
	var day := floori(float(minute) / 1440.0) + 1
	var hour := floori(float(minute % 1440) / 60.0)
	return "День %d · %02d:%02d" % [day, hour, minute % 60]

func cycle_speed() -> void:
	var allowed: Array = [0.25, 1.0] if threatened else [1.0, 4.0, 12.0, 60.0]
	set_speed(allowed[(allowed.find(speed) + 1) % allowed.size()])

func set_speed(value: float) -> bool:
	if value not in SPEEDS or (threatened and value > 1):
		return false
	speed = value
	return true

## Вызывается до продвижения времени; ускоренные шаги ещё не рассчитаны.
func set_threat(value: bool) -> bool:
	threatened = value
	if value and speed > 1:
		speed = 1.0
		return true
	return false

func scale() -> float:
	return 0.0 if paused else speed

func to_save() -> Dictionary:
	return {"minute": minute, "fraction": fraction, "speed": speed, "paused": paused}
