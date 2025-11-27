extends Control
@export var udplink := ""
@export  var portudp := 6969
@export var hash := ""
var test = 0
#⛔✅🧩📦🔍❌

var udp := PacketPeerUDP.new()
var transaction_id := 0
var connection_id := 0

func tracker_go():
	#Peer:0:0:0:0:0:ffff:be85:71d5 # PORT 6881 Peer:0:0:0:0:0:ffff:b9d1:c79f # PORT 55000 Peer:0:0:0:0:0:ffff:8ac7:785 # PORT 39965
	
	#prints(ipv6_real("0:0:0:0:0:ffff:be85:71d5"))
	#return
	#var ip := IP.resolve_hostname("tracker.torrust-demo.com", IP.TYPE_IPV4)
	var ip := IP.resolve_hostname(udplink, IP.TYPE_ANY)
	if ip == "":
		print("⛔ No se pudo resolver el hostname ⛔.")
		return
	prints("la ip es " , ip)
	var err := udp.connect_to_host(ip, portudp)
	if err != OK:
		print("⛔ Error al conectar al tracker: ", err)
		return

	transaction_id = randi()
	var buffer := PackedByteArray()
	buffer.append_array(to_bytes(0x41727101980, 8))  # connection_id inicial
	buffer.append_array(to_bytes(0, 4))              # action: connect
	buffer.append_array(to_bytes(transaction_id, 4)) # transaction_id
	prints("mi anuncio : " , buffer)
	var sent := udp.put_packet(buffer)
	if sent != OK:
		print("❌ Error al enviar paquete CONNECT: ", sent)
		return

	await get_tree().create_timer(1.0).timeout
	if udp.get_available_packet_count() > 0:
		var response := udp.get_packet()
		if response.size() >= 16:
			var action := from_bytes(response.slice(0, 4))
			var trans_id := from_bytes(response.slice(4, 8))
			connection_id = from_bytes(response.slice(8, 16))
			if action == 0 and trans_id == transaction_id:
				print("✅ CONNECT OK. Connection ID:", connection_id)
				send_announce()
			else:
				print("❌ CONNECT inválido.")
		else:
			print("❌ Respuesta CONNECT demasiado corta.")
	else:
		test = 1
		print("❌ No se recibió respuesta CONNECT.")

func _process(delta: float) -> void:
	if udp.get_available_packet_count() > 0 and test:
		prints("si conecto " ,udp.get_packet() )
	
	
	
	pass

func send_announce():
	transaction_id = randi()
	#magnet:?xt=urn:btih:18bc69892a5a546143ade969e3858d6b41089b8d
			 #└─────── btih = BitTorrent Info Hash (SHA-1, 20 bytes)
#
#&xt=urn:btmh:1220447cdd453834fed2ee3c2d4e29eea786786a0a5513e53d65e28e61a9dafb03a0
			 #└─────── btmh = BitTorrent Multihash (SHA-256, 32 bytes)
#
	#
	#var info_hash := hex_to_bytes("0123456789abcdef0123456789abcdef01234567")  # 20 bytes
	var info_hash = hex_to_bytes(hash)  # Ubuntu ISO
#18bc69892a5a546143ade969e3858d6b41089b8d   # 20 bytes
#"d2474e86c95b19b8bcfdb92bc12c9d44667cfa36"
	var peer_id = "GODOT-PEER-00000001"
	var downloaded := to_bytes(0, 8)
	var left := to_bytes(1000, 8)
	var uploaded := to_bytes(0, 8)
	var event := to_bytes(0, 4)  # 0: none
	var ip := to_bytes(0, 4)
	var key := to_bytes(randi(), 4)
	var num_want := PackedByteArray([255, 255, 255, 255])
	var port := to_bytes(6881, 2)
	

	var peer_bytes := peer_id.to_utf8_buffer()
# Blindaje: asegurar que tenga exactamente 20 bytes
	if peer_bytes.size() < 20:
		peer_bytes.resize(20)  # rellena con ceros
	elif peer_bytes.size() > 20:
		peer_bytes = peer_bytes.slice(0, 20)  # recorta



	

	var buffer := PackedByteArray()
	buffer.append_array(to_bytes(connection_id, 8))
	buffer.append_array(to_bytes(1, 4))  # action: announce
	buffer.append_array(to_bytes(transaction_id, 4))
	buffer.append_array(info_hash)
	buffer.append_array(peer_bytes)
	#buffer.append_array(peer_id.to_utf8_buffer())
	#buffer.append_array(PackedByteArray(peer_id.to_ascii()))
	buffer.append_array(downloaded)
	buffer.append_array(left)
	buffer.append_array(uploaded)
	buffer.append_array(event)
	buffer.append_array(ip)
	buffer.append_array(key)
	buffer.append_array(num_want)
	buffer.append_array(port)
	prints("envio esto : " , buffer)
	var sent := udp.put_packet(buffer)
	if sent != OK:
		prints("❌ Error al enviar paquete ANNOUNCE: ", sent)
		return

	await get_tree().create_timer(1.0).timeout
	if udp.get_available_packet_count() > 0:
		var response := udp.get_packet()
		prints("responde : " , response)
		if response.size() >= 20:
			var action := from_bytes(response.slice(0, 4))
			var trans_id := from_bytes(response.slice(4, 8))
			var interval := from_bytes(response.slice(8, 12))
			var leechers := from_bytes(response.slice(12, 16))
			var seeders := from_bytes(response.slice(16, 20))
			print("✅ ANNOUNCE OK. Interval:", interval, " Seeders:", seeders, " Leechers:", leechers)
			$ScrollContainer/"info tracker".text += "✅ ANNOUNCE OK. Interval:" + str(interval / 60 ) + " - Leechers: "  + str(leechers) + " seeders : " + str(seeders)
			$ScrollContainer/"info tracker".text += "
			
			"
			var peers := response.slice(20)
			var i := 0
			prints(peers.size() , "tamaño del peer packete")
			$ScrollContainer/"info tracker".text += " tamaño del packete : " + str(peers.size()) + "\n"
			while i < peers.size():
				var remaining := peers.size() - i
				var peer_ip := ""
				var peer_port := 0


		#if remaining >= 18:
					## IPv6: 16 bytes IP + 2 bytes puerto
					#var ip_bytes := peers.slice(i, i + 16)
					#var ip_parts := []
					#for j in range(0, 16, 2):
						#var part := (ip_bytes[j] << 8) | ip_bytes[j + 1]
						#ip_parts.append("%x" % part)
					#peer_ip = ":".join(ip_parts)
					#peer_port = (peers[i + 16] << 8) | peers[i + 17]
					#i += 18
#




				if remaining >= 6:#elif 
					# IPv4: 4 bytes IP + 2 bytes puerto
					peer_ip = "%d.%d.%d.%d" % [peers[i], peers[i+1], peers[i+2], peers[i+3]]
					peer_port = (peers[i+4] << 8) | peers[i+5]
					i += 6
					$"ScrollContainer/info tracker".text += " Peer " + str(peer_ip) + " port : " + str(peer_port)  + "\n "
					print("Peer:", peer_ip, " # PORT ", peer_port)
					prints("es ipv4 en ipv6 " ,ipv6_real( peer_ip))
				#
				else:
					push_warning("Bloque incompleto: %d bytes restantes no válidos" % remaining)
					break
					
					
				#remaining >= 6#elif 
				## IPv4: 4 bytes IP + 2 bytes puerto
				#peer_ip = "%d.%d.%d.%d" % [peers[i], peers[i+1], peers[i+2], peers[i+3]]
				#peer_port = (peers[i+4] << 8) | peers[i+5]
				#i += 6
				#$"info tracker".text += " Peer " + str(peer_ip) + " port : " + str(peer_port)
				print("Peer FINAL:", peer_ip, " # PORT ", peer_port)
				prints("es ipv4 en ipv6 " ,ipv6_real( peer_ip))
			#
			#for i in range(0, peers.size(), 6):
				#var peer_ip := "%d.%d.%d.%d" % [peers[i], peers[i+1], peers[i+2], peers[i+3]]
				#var peer_port := 0#(peers[i+4] << 8) | peers[i+5]
				#print("Peer:", peer_ip, ":", peer_port)

		else:
			print("❌ Respuesta ANNOUNCE demasiado corta.")
	else:
		print("❌ No se recibió respuesta ANNOUNCE.")

func to_bytes(value: int, size: int) -> PackedByteArray:
	var b := PackedByteArray()
	for i in range(size):
		b.append((value >> ((size - 1 - i) * 8)) & 0xFF)
	return b

func from_bytes(bytes: PackedByteArray) -> int:
	var result := 0
	for i in range(bytes.size()):
		result = (result << 8) | bytes[i]
	return result

func hex_to_bytes(hex: String) -> PackedByteArray:
	var b := PackedByteArray()
	for i in range(0, hex.length(), 2):
		b.append(hex.substr(i, 2).hex_to_int())
	return b

func ipv6_real(ipv6: String) -> String:
	prints("🔍 Input:", ipv6)
	
	var parts := ipv6.split(":")
	prints("📦 Partes:", parts)

	if parts.size() < 8:
		prints("⛔ Menos de 8 bloques")
		return "0"

	for i in range(5):
		prints("🔎 Verificando bloque %d: %s" % [i, parts[i]])
		if parts[i] != "0":
			prints("⛔ Bloque %d no es cero" % i)
			return "0"

	print("🔎 Verificando bloque 5 (esperado 'ffff'): %s" % parts[5])
	if parts[5].to_lower() != "ffff":
		prints("⛔ Bloque 5 no es 'ffff'")
		return "0"

	prints("🧮 Bloques hexadecimales: %s, %s" % [parts[6], parts[7]])
	var b1 := parts[6].hex_to_int()
	var b2 := parts[7].hex_to_int()


	prints("🧩 Decodificados: b1 = %d, b2 = %d" % [b1, b2])

	var ipv4 := "%d.%d.%d.%d" % [b1 >> 8, b1 & 0xFF, b2 >> 8, b2 & 0xFF]
	prints("✅ IPv4 resultante:", ipv4)

	return ipv4


func _on_send_pressed() -> void:
	tracker_go()
	pass # Replace with function body.
