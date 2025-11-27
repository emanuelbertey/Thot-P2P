extends Control

@onready var peer: Peerinfo = $Peerinfo


func _ready() -> void:

	var pub =$CodeEdit.text #"s7wmbfk7c17eqw4sgncftsd3p4adoqiajixbia5q6c4ywgtawd3y"#"tkucztxt7xhrb41miqb7xknhijngpgy7tyhete15ycok7naaonsy"
	if pub.length() < 32:
		pub = "tkucztxt7xhrb41miqb7xknhijngpgy7tyhete15ycok7naaonsy"
		
	pass
	#var peer = Peerinfo.new()

func _on_peerinfo_resolv(data: String) -> void:
	prints("desde la señal de godot : " , data)
	$Label.text = txt_linea(str(data))
	pass # Replace with function body.


func _on_button_pressed() -> void:
	var key = [
		199, 133, 251, 69, 66, 206, 61, 213, 151, 163, 166, 14, 142, 46, 94, 231,
		66, 126, 8, 67, 114, 56, 186, 37, 12, 18, 111, 207, 0, 223, 229, 145,
	]
	var packed_key = PackedByteArray()
	for byte in key:
		packed_key.append(byte)
	#var key = "o4dksfbqk85ogzdb5osziw6befigbuxmuxkuxq8434q89uj56uyy"
	var mode = $mode.text #"dht"#relays   dht
	var pub =$CodeEdit.text
	#var relays = PackedStringArray()# vacío si no usás relays
	var relays := PackedStringArray([
	"https://relay.pkarr.org",
	"https://pkarr.pubky.org"
	
])
	if pub.length() < 32:
		pub = peer.public_key(packed_key)
	prints(pub)
	if peer.resolve_key(pub,mode,relays):
		$publicar.text = "echo resolver "
	else:
		prints("error")
		$publicar.text = "error resolver  "
	
	pass # Replace with function body.


func _on_button_2_pressed() -> void:
	var mode = $mode.text #"dht"#relays   dht
	var relays := PackedStringArray([
	"https://relay.pkarr.org",
	"https://pkarr.pubky.org"
	
])
	
	var key = [
		199, 133, 251, 69, 66, 206, 61, 213, 151, 163, 166, 14, 142, 46, 94, 231,
		66, 126, 8, 67, 114, 56, 186, 37, 12, 18, 111, 207, 0, 223, 229, 145,
	]
	var packed_key = PackedByteArray()
	for byte in key:
		packed_key.append(byte)
	
	#if peer.prepare_packet(str($clave.text),str($valor.text),mode , relays,packed_key):
		#$publicar.text = "publicado "
	#else:
		#prints("error")
		#$publicar.text = "error publicado "
	#
	


func txt_linea(linea: String) -> String:
	var regex = RegEx.new()
	regex.compile(r'(\w+)\.[^\s]+\s+IN\s+\d+\s+TXT\s+"([^"]+)"')

	var match = regex.search(linea)
	if match == null:
		return ""

	var nombre = match.get_string(1)    
	var contenido = '"' + match.get_string(2) + '"' 

	return nombre + " " + contenido
