extends Resource
class_name ConceptData

@export var id: String = ""
@export var display_name: String = ""
@export_enum("trigger", "skill", "modifier") var concept_type: String = "trigger"
@export var description: String = ""
@export var element_tags: Array[String] = []
@export var params: Dictionary = {}
