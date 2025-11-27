extends Control


var ip = "127.0.0.1"
var port = 9999
@onready var conteiner = $"../PanelContainer/HBoxContainer/ScrollContainer/VBoxContainer2"




func add_socket(format, dir , n_name):
	var data_exten = load("res://server_list.tscn").instantiate()
	data_exten.format = format
	data_exten.file_dir = dir
	data_exten.nname = n_name
	if $"../CheckButton".button_pressed:
		data_exten.upnp = true
	add_child(data_exten)
	prints("⭐️ DATOS AL NODO INSTANCIADO ⭐️" ,format , "  ", dir  , "  " , n_name)


func _on_server_pressed() -> void:
	var data_exten = load("res://addons/thot/example/server_list.tscn").instantiate()
	data_exten.ip = $HBoxContainer/ip_ws_.text
	data_exten.port = port
	data_exten.type = $LineEdit.text
	data_exten.is_server = true
	if $"../CheckButton".button_pressed:
		data_exten.upnp = true
	conteiner.add_child(data_exten)
	prints("⭐️ DATOS AL NODO INSTANCIADO ⭐️" )
	pass # Replace with function body.


func _on_cliente_pressed() -> void:
	var data_exten = load("res://addons/thot/example/server_list.tscn").instantiate()
	data_exten.ip = $HBoxContainer/ip_ws_.text
	data_exten.port = port
	data_exten.type = $LineEdit.text
	data_exten.is_server = false
	conteiner.add_child(data_exten)
	prints("⭐️ DATOS AL NODO INSTANCIADO ⭐️" )
	pass # Replace with function body.


func _on_button_pressed() -> void:
	pass # Replace with function body.


func _on_check_button_toggled(toggled_on: bool) -> void:
	prints("upnp seting : " ,  toggled_on)
	pass # Replace with function body.
