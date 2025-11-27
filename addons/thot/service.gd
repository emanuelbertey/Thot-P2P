#Thot p2p
class_name Service
extends Node

const ConnectionType = {
	UDP = "udp",
	TCP = "tcp",
	WEBSOCKET = "webs",
	WEBRTC = "webr",
	ENET = "enet",
	IROH = "iroh"
}

# Diccionarios para registrar servidores y clientes por tipo de conexión
var servers := {}  # Ahora almacena { puerto: { "type": tipo, "node": instancia } } Registra servidores por tipo (ej. "UDP", "TCP", "ENet")
var clients := {}  # Registra clientes por tipo (ej. "UDP", "TCP")

# Para el upnp seting , configuracion
var upnp = UPNP.new()
var thread = Thread


# Arrays que almacenan nodos activos
var server_nodes := {}  # Guarda las instancias de servidores
var client_nodes := {}  # Guarda las instancias de clientes

# Lista de puertos abiertos
var open_ports := {}

# Estado de UPnP
var upnp_enabled := false
var upnp_ports := {}


func _ready() -> void:


#region regex sin uso

	#var url = "htp://forum.godotengine.org/t/validate-if-a-string-is-a-url/37448/3"
	#var urlRegex = RegEx.new()
	#var compile_result = urlRegex.compile('^(ftp|http|https)://[^ "]+$')
	#if compile_result != OK:
		#print("Error al compilar el patrón RegEx: ", compile_result)
		#return
#
	#var result = urlRegex.search(url)
	#if result:
		#print("URL válida:", result.get_string())
	#else:
		#print("URL inválida.")
#endregion
	
	thread = Thread.new()

#region Agregar o quitar servidor con tipo y puerto
func add_server(node ,type: String, port: int, lobby: String = "webrtc_godot_4.4.dev3") -> bool:
	if !port > 0 and port <= 65535:
		return false
	if type not in ConnectionType.values():
		print("Tipo no válido para un socket:", type)
		return false

	if type not in servers:
		servers[type] = {}  # Inicializar diccionario si es la primera vez

	if port in servers[type]:
		print("Ya existe un servidor de tipo", type, "en el puerto:", port)
		return false

	var server = null

	match type:
		ConnectionType.UDP:
			server = Server_udp.new(port)
		ConnectionType.TCP:
			server = NetworkServer.new("*", port)
			
		ConnectionType.WEBSOCKET:
			server = WebServer.new("*", port)
			
		ConnectionType.IROH:
			server = IrohServer.start()
			multiplayer.multiplayer_peer = server
		
			var connection_string: String = multiplayer.multiplayer_peer.connection_string()
			lobby =  connection_string
			await prints(server.connection_string())
		ConnectionType.WEBRTC:
			
		
			var data_exten = load("res://addons/thot/scenes/main.tscn").instantiate()
			data_exten.lobby = lobby
	
		
			data_exten.is_server = true
			
			node.add_child(data_exten)
			prints("⭐️ node webrtc ⭐️" )
					
			server = data_exten
			server._host()
			server.visible = false
			#server = webrtc.new("*", port ,lobby,true)
			#
			#server.connection_timeout.connect(_off_time)
			#add_child(server)
		ConnectionType.ENET:
			server = Eserver.new("*", port)
			
		var server_type:
			prints("error de tipo server no existe : " ,  server_type)

	if server == null:
		print("Error: No se pudo instanciar el servidor de tipo", type)
		return false

	if  type != "webr" and type != "iroh":
		prints(type)
		server.name = "server"+str(lobby)
		node.add_child(server)

		server.data_received.connect(_data)
		server.client_connected.connect(user_conect)
		server.client_disconnected.connect(user_disconect)



		

	# Guardar el servidor en el diccionario por tipo y puerto
	servers[type][port] = server

	print("Servidor agregado:", type, "en puerto:", port)
	return true


# Eliminar servidor con tipo y puerto
func remove_server( type: String, port: int):
	if type in servers and port in servers[type]:
		var server_node = servers[type][port]
		
		# Liberar el nodo del servidor
		server_node.queue_free()
		
		# Eliminar del registro
		servers[type].erase(port)

		print("Servidor eliminado: ", type, " en puerto: ", port)

		# Si no quedan más servidores de ese tipo, eliminar la clave
		if servers[type].is_empty():
			servers.erase(type)
	else:
		print("No existe un servidor de tipo ", type, "en el puerto: ", port)
#endregion


#region Agregar o quitar cliente con IP, tipo y puerto
func add_client(node ,type: String, ip: String, port: int, lobby: String = "webrtc_godot_4.4.dev3"):
	if !port > 0 and port <= 65535:
		return false
	if type not in ConnectionType.values():
		print("Tipo no válido para un socket: ", type)
		return false
	if type not in clients:
		clients[type] = []
	var client_info = {"ip": ip, "port": port}

	# Verificar si el cliente ya está registrado
	for client in clients[type]:
		if client["ip"] == ip and client["port"] == port:
			print("El cliente ya está registrado: ", ip, ":", port)
			return false

	# Instanciar 
	var client = null

	match type:
		ConnectionType.UDP:
			client = Client_udp.new(ip, port)
		ConnectionType.TCP:
			client = NetworkClient.new(ip, port)
			
		ConnectionType.WEBSOCKET:
			client = WebClient.new(ip, port)
			
		ConnectionType.IROH:
			client = IrohClient.connect(lobby)
			multiplayer.multiplayer_peer = client
			
		ConnectionType.WEBRTC:

			#var runner_scene := preload("res://addons/thot/scenes/main.tscn")
			#var runner = runner_scene.instantiate()
			#runner.lobby = lobby
			#runner.is_server = false
			##var current_scene := get_tree().get_current_scene()
			##if current_scene == null:
				##push_error("No hay escena activa para ejecutar UPNP")
			prints("runer run ")

			#runner.hotok = false
			#runner.visible = false
			#node.add_child(runner)
			#
			#client = runner
			#
			#client = webrtc.new("*", port, lobby, false)
			prints("desde cliente webr : ",  lobby)
		ConnectionType.ENET:
			client = Eclient.new(ip, port)
		var cliente_type:
			prints("no existe ese protocolo " , cliente_type)

	# Verificar si la instancia se creó correctamente
	if client == null:
		print("Error: No se pudo instanciar el cliente de tipo ", type)
		return false

		
		
		
	if !type == "webr" and !type == "iroh":
		node.add_child(client)
		client.data_received.connect(_data)


	

	# Guardar nodo del cliente en el registro con IP y puerto
	if type not in client_nodes:
		client_nodes[type] = []
	client_nodes[type].append({"node": client, "ip": ip, "port": port })

	# Agregar cliente al registro
	clients[type].append(client_info)
	print("Cliente agregado: ", ip, " : ", port, " al tipo ", type , "node " , node)

	return true


# Eliminar cliente por IP y puerto
func remove_client(type: String, ip: String, port: int):
	if type in clients:
		# Buscar en client_nodes
		if type in client_nodes:
			for client_data in client_nodes[type]:
				if client_data["ip"] == ip and client_data["port"] == port:
					var client_node = client_data["node"]  # Obtener referencia del nodo
					if client_node.has_method("stop"):
						prints("cliente stop run")
						client_node.stop()
					client_node.queue_free()  # Liberar nodo

					client_nodes[type].erase(client_data)  # Eliminar del registro
					break
		
		# Eliminar del registro general
		for client in clients[type]:
			if client["ip"] == ip and client["port"] == port:
				clients[type].erase(client)
				print("Cliente eliminado: ", ip, " : ", port , " de tipo: " , type)
				return
	
	print("No se encontró el cliente: ", ip, " : ", port)
#endregion


#region get server and client
# Obtener lista de servidores y clientes
func get_servers() -> Dictionary:
	return servers

func get_clients() -> Dictionary:
	return clients
	
func get_client_node() -> Dictionary:
	return client_nodes



func client_thot(type , port )-> MultiplayerPeer:
	var dic = get_client_node()
	prints("mi dic " , dic)
	var nodo = null
	for entry in dic[type]:
		if entry.has("port") and entry["port"] == port:
			nodo = entry["node"]
			break
	if nodo == null:
		return null
	if type == "iroh":
		var multiplayer_api : MultiplayerAPI
		get_tree().set_multiplayer(multiplayer, self.get_path())
		multiplayer_api = MultiplayerAPI.create_default_interface()
		return nodo
	if type == "webr":
		var multiplayer_api : MultiplayerAPI
		multiplayer_api = MultiplayerAPI.create_default_interface()
		multiplayer.multiplayer_peer = nodo.client.rtc_mp
		return nodo.client.rtc_mp
		
	return nodo.peer
	

func server_thot(type , port )-> MultiplayerPeer:
	var dic = get_servers()
	var nodo = dic[type][port]
	if nodo == null:
		return null
	if type == "iroh":
		var multiplayer_api : MultiplayerAPI
		get_tree().set_multiplayer(multiplayer, self.get_path())
		multiplayer_api = MultiplayerAPI.create_default_interface()

		return nodo
	if type == "webr":
		return nodo.client.rtc_mp
	return nodo.peer
#endregion


#region enviar send 
func send(type , ip , port, pack):
	
	var peer = client_thot(type , 9999 )
	multiplayer.multiplayer_peer = peer
	if type in clients:
		# Buscar en client_nodes
		if type in client_nodes:
			for client_data in client_nodes[type]:
				if client_data["ip"] == ip and client_data["port"] == port:
					var client_node = client_data["node"]  # Obtener referencia del nodo
					if client_node.has_method("send_pack"):
						client_node.send_pack(pack)
						return
					else:
						prints("Error: Network 'send_pack'")

	if type in servers and port in servers[type]:
		var server_node = servers[type][port]

		if server_node.has_method("send_pack"):
			server_node.send_pack(pack)
			return
		else:
			prints("Error: Network 'send_pack'")
	prints("Error: Network service no esta iniciado")
#endregion


#region Registrar UPnP
func enable_upnp(port):
	#if upnp_enabled == false:
		#return
	#thread.start(register_upnp_port.bind(port))
	register_upnp_port(port)
	upnp_enabled = true
	print("UPnP habilitado")
	

func disable_upnp(port):
	if upnp_ports.has(port):
		#print("El puerto UPnP ya está registrado: ", port)
		#upnp.delete_port_mapping(port)
		upnp_enabled = false
	else:
		print("El puerto UPnP no está registrado: ", port)

	upnp_enabled = false
	print("UPnP deshabilitado")

func register_upnp_port(port: int):
	if not Thot.upnp_enabled:
		print("No se puede registrar UPnP, está deshabilitado.")
		return
	
	if Thot.upnp_ports.has(port):
		print("El puerto UPnP ya está registrado: ", upnp_ports[port])
		return
	prints("upnp setup iniciando")
	#upnp = 
	
	var runner_scene := preload("res://addons/thot/tools/upnp/upnp_call.gd")
	var runner := runner_scene.new()

	var current_scene := get_tree().get_current_scene()
	if current_scene == null:
		push_error("No hay escena activa para ejecutar UPNP")
		return
		prints("runer run ")
	runner.port = port
	current_scene.call_deferred("add_child", runner)
	#call_deferred("add_child", runner)
	#print(runner.is_inside_tree())
	#current_scene.add_child(runner)
	print("Nodo auxiliar UPNP agregado al árbol")
	
	
	#node.add_child(UPNP.new())
	#var upnp_seting = node.upnp
	#var err = upnp_seting.discover()
	#if err != OK:
		#push_error(str(err))
		##return
	#if upnp_seting.get_gateway() and upnp_seting.get_gateway().is_valid_gateway():
		#upnp_seting.add_port_mapping(port, port, ProjectSettings.get_setting("application/config/name"), "UDP")
		#upnp_seting.add_port_mapping(port, port, ProjectSettings.get_setting("application/config/name"), "TCP")
		##upnp.add_port_mapping(port, port, ProjectSettings.get_setting("applicationname"), "TCP")
		##if map_result != UPNP.UPNP_RESULT_SUCCESS:
			##push_error("Fallo al mapear el puerto: %s" % map_result)
			##
		#var external_ip = upnp_seting.query_external_address()
		#print("Success! Join Address: %s" % external_ip)
		#Thot.upnp_ports[port] = external_ip
#
	## Si UPnP está habilitado y el puerto no está registrado, se agrega
	##upnp_ports[port] = external_ip
	print("Puerto UPnP registrado: ",Thot.upnp_ports)

func is_upnp_port_open(port: int) -> bool:
	return upnp_ports.get(port, false)
#endregion fin upnp

func _data(id ,data):
	prints("se recivio de cliente ",id ,"estos datos:" ,  data)


func user_conect(id):
	prints( "se conecto id " , id)


func user_disconect(id):
	prints("se deconecto ", id)
	


func _exit_tree():
	thread.wait_to_finish()
