class_name WolfQuest
extends RefCounted

## Elder Wen's demon wolf quest as pure rules: accepting, counting kills and turning in.
## Kept free of scene nodes so it can be unit tested headlessly.

enum Step { NOT_STARTED, ACTIVE, COMPLETE }

var required := 2
var reward_qi := 150.0
var step := Step.NOT_STARTED
## Every wolf slain counts, including wolves killed before the quest was accepted.
var slain := 0


func _init(wolves_required := 2, qi_reward := 150.0) -> void:
	required = wolves_required
	reward_qi = qi_reward


func progress() -> int:
	return mini(slain, required)


func record_kill() -> void:
	slain += 1


func is_ready_to_turn_in() -> bool:
	return step == Step.ACTIVE and slain >= required


## Talking to Elder Wen. Accepts the quest when it has not started, then turns it in straight
## away if the wolves were already slain. Returns the qi reward granted by this talk.
func talk() -> float:
	if step == Step.NOT_STARTED:
		step = Step.ACTIVE
	if is_ready_to_turn_in():
		step = Step.COMPLETE
		return reward_qi
	return 0.0


func objective_text() -> String:
	match step:
		Step.NOT_STARTED:
			return "Speak with Elder Wen"
		Step.ACTIVE:
			if is_ready_to_turn_in():
				return "Return to Elder Wen"
			return "Slay demon wolves %d / %d" % [progress(), required]
	return "Quest complete"
