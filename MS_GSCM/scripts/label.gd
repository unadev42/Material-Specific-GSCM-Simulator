extends Node

@export var transmitter: Node3D  
@export var receiver: Node3D  
@export var distance_label: Label  

func _process(delta):
	if not transmitter or not receiver or not distance_label:
		return  

	var distance = transmitter.global_transform.origin.distance_to(receiver.global_transform.origin)
	distance_label.text = "TX-RX Distance: " + str(snapped(distance, 0.01)) + " m"
