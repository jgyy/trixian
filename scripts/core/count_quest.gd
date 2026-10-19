class_name CountQuest
extends RefCounted

## A quest that asks for a number of things, as pure rules: accepting, counting and turning in.
## Elder Wen's demon wolves, his hunt for the alpha and Disciple Lin's spirit herbs are all one.
## Kept free of scene nodes so it can be unit tested headlessly.

enum Step { NOT_STARTED, ACTIVE, COMPLETE }

var required := 2
var reward_qi := 150.0
## Who hands the quest out and takes it back, as the objective names them.
var giver := "Elder Wen"
## The objective while the quest is active, before the count, such as "Slay demon wolves".
var task := "Slay demon wolves"
var step := Step.NOT_STARTED
## Everything counts, including what was done before the quest was accepted.
var done := 0


func _init(
	count_required := 2, qi_reward := 150.0, giver_name := "Elder Wen", task_text := ""
) -> void:
	required = count_required
	reward_qi = qi_reward
	giver = giver_name
	if not task_text.is_empty():
		task = task_text


func progress() -> int:
	return mini(done, required)


func record() -> void:
	done += 1


func is_ready_to_turn_in() -> bool:
	return step == Step.ACTIVE and done >= required


## Talking to the giver. Accepts the quest when it has not started, then turns it in straight
## away if the count is already met. Returns the qi reward granted by this talk.
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
			return "Speak with %s" % giver
		Step.ACTIVE:
			if is_ready_to_turn_in():
				return "Return to %s" % giver
			return "%s %d / %d" % [task, progress(), required]
	return "Quest complete"
