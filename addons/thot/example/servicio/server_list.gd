extends Control
@export var port = 0
@export var ip = 0
@export var type = ""
@export var lobby = ""
@export var is_server = false
var network
@export var upnp = true

func _ready() -> void:
	# Creamos una instancia del NetworkManager
	network = Thot
	#add_child(network)
	# Configuramos UPnP (si queremos que esté habilitado)
	if upnp:
		network.enable_upnp(port)
	
	#network.register_upnp_port(port)

	# Intentamos registrar un servidor UDP en el puerto 12345
	if is_server:
		if lobby == "":
			lobby = "webrtc_godot_4.4.dev3"
		var udp_server = network.add_server(self ,type, port, lobby)
		if udp_server:
			$VBoxContainer/Label.text += " " + type + " server"
			print("Servidor :",type , " creado exitosamente en puerto :" , port)
		else:
			print("Error: No se pudo crear el servidor :", type)
			#network.queue_free()
			self.queue_free()


	if !is_server:
		if lobby == "":
			lobby = "webrtc_godot_4.4.dev3"
		network.add_client(self ,type, ip,port,lobby)
		$VBoxContainer/Label.text += " " + type + " cliente"

		
	
'''
	# Mostramos la lista de servidores activos
	#print("Servidores activos:", network.get_servers())
#
	## Mostramos la lista de clientes activos
	#print("Clientes conectados:", network.get_clients())
	
	# Cerramos el servidor UDP
	#network.remove_server("udp" , 12345)
	#network.remove_client("udp", "192.168.1.12", 5003)
'''
# quitamos todo al salir 
func _on_button_pressed() -> void:
	if is_server:
		network.remove_server(type ,port)
		queue_free()
	else:
		network.remove_client(type, ip,port)
		queue_free()
	pass


func _on_enviar_pressed() -> void:
	var smj = $"../../../../../edot_msj".text
	network.send(type,ip , port ,smj)
	prints("funcion de enviar prueba port / type " , port , "  " , type)
	pass # Replace with function body.
