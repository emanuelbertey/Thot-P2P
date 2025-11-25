extends Control




func _on_button_pressed_service() -> void:
	var data_exten = load("res://addons/thot/example/prueba_service.tscn").instantiate()

	self.add_child(data_exten)
	$GridContainer.queue_free()
	$TextureRect.queue_free()
	prints("⭐️ DATOS AL NODO INSTANCIADO ⭐️" )




func _on_button_pressed_fps() -> void:
	var data_exten = load("res://addons/thot/example/example FPS/world.tscn").instantiate()

	self.add_child(data_exten)
	$GridContainer.queue_free()
	$TextureRect.queue_free()
	prints("⭐️ DATOS AL NODO INSTANCIADO ⭐️" )

	pass # Replace with function body.


func _on_chat_pressed() -> void:
	var data_exten = load("res://addons/thot/example/examples IROH/chat_app/main.tscn").instantiate()

	self.add_child(data_exten)
	$GridContainer.queue_free()
	$TextureRect.queue_free()
	prints("⭐️ DATOS AL NODO INSTANCIADO ⭐️" )

	pass # Replace with function body.
