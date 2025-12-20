extends Control

# File Fast - Pro Version with Batch Folder Downloading
# Features: Virtual directory browsing, recursive downloading, metadata persistence

const CHUNK_SIZE = 32 * 1024
var save_profile_name = "default"
var selected_files_to_send = []
var incoming_offers = {} # { peer_id: Array }
var active_transfers = {}
var _incoming_offer_buffer = {}
var shared_roots = [] # Array of Dict {path, is_dir}
var blacklisted_hashes = [] # Hashes the user wants to keep private
var downloaded_hashes = []
var global_save_path = ""
var _hash_cache = {} # { base_path: { rel_within_base: {h, m, s} } }
var download_speed_limit = 0 # KiB/s
var upload_speed_limit = 0   # KiB/s
var _bytes_in_window = 0
var _bytes_out_window = 0
var _last_stat_time = Time.get_ticks_msec()
var _current_down_speed = 0.0
var _current_up_speed = 0.0
var _total_active_upload_requests = 0
const MAX_GLOBAL_UPLOAD_REQS = 30 # Limite total de envios simultaneos

const MAX_WINDOW = 12 # Parallel chunks 

# (persistent across dirs)
var remote_selection_state = {}

# Browsing State
var local_view_path = ""
var remote_view_path = ""
var current_remote_peer = -1

@onready var status_label = $MainVbox/StatusLabel
@onready var conn_string_display = $MainVbox/TopBar/ConnStringDisplay
@onready var send_list = $MainVbox/HBox/SendSection/Scroll/SendList
@onready var receive_list = $MainVbox/HBox/ReceiveSection/Scroll/ReceiveList
@onready var local_path_label = $MainVbox/HBox/SendSection/PathHeader/PathLabel
@onready var remote_path_label = $MainVbox/HBox/ReceiveSection/PathHeader/PathLabel

var peer_selector # Se asigna dinamicamente
var _syncing = false
var _last_fingerprint = ""

func _ready():
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.server_disconnected.connect(_on_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	
	_load_settings()
	$SettingsPanel.visible = false
	
	$MainVbox/HBox/SendSection/PathHeader/BackBtn.pressed.connect(_on_local_back)
	$MainVbox/HBox/ReceiveSection/PathHeader/BackBtn.pressed.connect(_on_remote_back)
	
	var timer = Timer.new()
	timer.wait_time = 30.0
	timer.timeout.connect(_check_sync_local_changes)
	add_child(timer)
	
	_build_ui_extras()
	_build_settings_ui()
	_connect_settings_ui()
	_check_sync_local_changes()

func _process(_delta):
	var now = Time.get_ticks_msec()
	if now - _last_stat_time >= 1000:
		var diff = (now - _last_stat_time) / 1000.0
		_current_down_speed = _bytes_in_window / diff
		_current_up_speed = _bytes_out_window / diff
		_bytes_in_window = 0
		_bytes_out_window = 0
		_last_stat_time = now
		_update_status_ui()

func _update_status_ui():
	if active_transfers.is_empty():
		status_label.text = "Idle | ▲ %s | ▼ %s" % [_format_speed(_current_up_speed), _format_speed(_current_down_speed)]
	else:
		var total_p = 0.0
		var count = 0
		for k in active_transfers:
			var t = active_transfers[k]
			if t.chunk_hashes.size() > 0:
				total_p += (float(t.got_chunks) / t.chunk_hashes.size())
				count += 1
		var avg = (total_p / max(1, count)) * 100.0
		status_label.text = "Transferring %d items (%.1f%%) | ▲ %s | ▼ %s" % [count, avg, _format_speed(_current_up_speed), _format_speed(_current_down_speed)]


func _check_sync_local_changes():
	if _syncing or shared_roots.is_empty(): return
	
	# Shallow check: total files + sizes + modification times
	var current_fp = ""
	for r in shared_roots:
		current_fp += _get_fingerprint_recursive(r.path) if r.is_dir else _get_file_fp(r.path)
	
	if current_fp == _last_fingerprint: return
	
	_syncing = true
	_last_fingerprint = current_fp
	status_label.text = "Sync: Directory changes detected..."
	
	var new_list = []
	for r in shared_roots:
		var rpath = r.path.rstrip("/")
		if r.is_dir and DirAccess.dir_exists_absolute(rpath):
			var base = rpath.get_base_dir()
			var rel = rpath.get_file()
			if rel == "": # Root case
				base = rpath
			await _scan_to_list(base, rel, new_list)
		elif !r.is_dir and FileAccess.file_exists(rpath):
			await _add_to_list(rpath.get_base_dir(), rpath.get_file(), new_list)
	
	selected_files_to_send = new_list
	_update_send_list()
	if multiplayer.has_multiplayer_peer():
		_on_send_offer_pressed()
	_save_settings()
	
	status_label.text = "Sync: OK. Sharing %d items." % selected_files_to_send.size()
	_syncing = false

func _get_file_fp(p):
	if not FileAccess.file_exists(p): return "NONE"
	return p + str(FileAccess.get_modified_time(p)) + str(FileAccess.open(p, FileAccess.READ).get_length())

func _get_fingerprint_recursive(p):
	var d = DirAccess.open(p)
	var fp = p
	if d:
		d.list_dir_begin()
		var n = d.get_next()
		while n != "":
			if n != "." and n != "..": # Skip special dirs
				if d.current_is_dir(): fp += _get_fingerprint_recursive(p.path_join(n))
				else: fp += _get_file_fp(p.path_join(n))
			n = d.get_next()
	return fp

func _is_blacklisted(h):
	return blacklisted_hashes.has(h)

func _scan_to_list(base, rel, list):
	var full = base.path_join(rel)
	var d = DirAccess.open(full)
	if d:
		d.list_dir_begin()
		var n = d.get_next()
		while n != "":
			if n != "." and n != "..": # Skip special dirs
				if d.current_is_dir(): await _scan_to_list(base, rel.path_join(n), list)
				else: await _add_to_list(base, rel.path_join(n), list)
			n = d.get_next()

func _add_to_list(base, rel, list):
	var p = base.path_join(rel)
	var mtime = FileAccess.get_modified_time(p)
	var f = FileAccess.open(p, FileAccess.READ)
	if not f: return
	var fsize = f.get_length()
	f.close()
	
	var h = ""
	
	var cached_base = _hash_cache.get(base)
	if not (cached_base is Dictionary):
		cached_base = {}
		_hash_cache[base] = cached_base
		
	var entry = cached_base.get(rel)
	if entry is Dictionary and entry.get("m") == mtime and entry.get("s") == fsize:
		h = entry.h
	else:
		h = await _calculate_hash_only_full(p)
		cached_base[rel] = {"h": h, "m": mtime, "s": fsize}
	
	if _is_blacklisted(h): return
	
	list.append({
		"id": (rel + h).md5_text().substr(0, 12),
		"rel_path": rel, 
		"name": p.get_file(), 
		"size": fsize, 
		"hash": h, 
		"format": p.get_extension(),
		"_internal_path": p 
	})

func _get_save_path():
	return "user://ff_save_%s.dat" % save_profile_name

func _save_settings():
	var data = {
		"profile": save_profile_name,
		"save_path": global_save_path,
		"shared_roots": shared_roots,
		"blacklisted": blacklisted_hashes,
		"hashes": downloaded_hashes,
		"hash_cache": _hash_cache,
		"dl_limit": download_speed_limit,
		"ul_limit": upload_speed_limit
	}
	var f = FileAccess.open(_get_save_path(), FileAccess.WRITE)
	if f: f.store_var(data)

func _load_settings():
	var p = _get_save_path()
	if not FileAccess.file_exists(p): return
	var f = FileAccess.open(p, FileAccess.READ)
	var data = f.get_var()
	if not data is Dictionary: return
	
	save_profile_name = data.get("profile", save_profile_name)
	global_save_path = data.get("save_path", "")
	downloaded_hashes = data.get("hashes", [])
	shared_roots = data.get("shared_roots", [])
	blacklisted_hashes = data.get("blacklisted", [])
	_hash_cache = data.get("hash_cache", {})
	download_speed_limit = data.get("dl_limit", 0)
	upload_speed_limit = data.get("ul_limit", 0)
	
	# IMPORTANTE: Limpiar todo antes de cargar el nuevo perfil
	selected_files_to_send.clear()
	incoming_offers.clear()
	active_transfers.clear()
	
	_update_ui_from_settings()
	# Forzar el escaneo fisico de las raíces compartidas
	for root in shared_roots:
		var rpath = root.path.rstrip("/")
		if root.is_dir: await _scan_dir_recursive(rpath.get_base_dir(), rpath.get_file())
		else: await _add_file_to_list(rpath.get_base_dir(), rpath.get_file())
	
	_trigger_immediate_sync() 

func _update_ui_from_settings():
	$SettingsPanel/VBox/PathLabel.text = "Save to: " + (global_save_path if global_save_path != "" else "Not set")
	if $SettingsPanel/VBox.has_node("ProfileInput"):
		$SettingsPanel/VBox/ProfileInput.text = save_profile_name
	if $SettingsPanel/VBox.has_node("DLLimit"):
		$SettingsPanel/VBox/DLLimit.value = download_speed_limit
	if $SettingsPanel/VBox.has_node("ULLimit"):
		$SettingsPanel/VBox/ULLimit.value = upload_speed_limit

# --- UI LOGIC ---

func _on_settings_pressed():
	$SettingsPanel.visible = !$SettingsPanel.visible

func _on_close_settings_pressed():
	$SettingsPanel.visible = false

func _build_settings_ui():
	var vbox = $SettingsPanel.get_node_or_null("VBox")
	if not vbox: return
	
	if not vbox.has_node("ProfileInput"):
		var l = Label.new(); l.text = "Nombre del Perfil (Enter para cargar):"; vbox.add_child(l)
		var pi = LineEdit.new(); pi.name = "ProfileInput"; pi.placeholder_text = "default"; vbox.add_child(pi)
		
	if not vbox.has_node("DLLimit"):
		var l = Label.new(); l.text = "Límite Bajada (KiB/s, 0=inf):"; vbox.add_child(l)
		var dl = SpinBox.new(); dl.name = "DLLimit"; dl.max_value = 100000; vbox.add_child(dl)
		
	if not vbox.has_node("ULLimit"):
		var l = Label.new(); l.text = "Límite Subida (KiB/s, 0=inf):"; vbox.add_child(l)
		var ul = SpinBox.new(); ul.name = "ULLimit"; ul.max_value = 100000; vbox.add_child(ul)

	if not vbox.has_node("ClearShared"):
		var b = Button.new(); b.name = "ClearShared"; b.text = "Limpiar Carpetas Compartidas"; vbox.add_child(b)
		b.pressed.connect(_on_clear_shared_pressed)
		b.add_theme_color_override("font_color", Color(1, 0.4, 0.4))

func _build_ui_extras():
	# Inyectamos el PeerSelector si no existe en la escena
	var receive_section = $MainVbox/HBox/ReceiveSection
	if not receive_section.has_node("PeerSelector"):
		var ps = HFlowContainer.new()
		ps.name = "PeerSelector"
		receive_section.add_child(ps)
		receive_section.move_child(ps, 1) # Justo debajo del header
		peer_selector = ps

func _connect_settings_ui():
	var vbox = $SettingsPanel.get_node_or_null("VBox")
	if not vbox: return
	if vbox.has_node("DLLimit"):
		vbox.get_node("DLLimit").value_changed.connect(func(v): download_speed_limit = v; _save_settings())
	if vbox.has_node("ULLimit"):
		vbox.get_node("ULLimit").value_changed.connect(func(v): upload_speed_limit = v; _save_settings())
	if vbox.has_node("ProfileInput"):
		vbox.get_node("ProfileInput").text_submitted.connect(_on_profile_submitted)

func _on_profile_submitted(new_name):
	save_profile_name = new_name
	_load_settings()
	status_label.text = "Perfil cambiado a: " + new_name
	_trigger_immediate_sync()

# --- CONNECTION ---

func _on_host_pressed():
	var s = IrohServer.start()
	multiplayer.multiplayer_peer = s
	conn_string_display.text = s.connection_string()
	$MainVbox/JoinOverlay.visible = false
	status_label.text = "Hosting..."

func _on_join_pressed():
	var t = $MainVbox/JoinOverlay/VBox/TicketInput.text
	conn_string_display.text = t
	if t.is_empty(): return
	multiplayer.multiplayer_peer = IrohClient.connect(t)
	$MainVbox/JoinOverlay.visible = false
	status_label.text = "Joining..."

func _on_connected():
	status_label.text = "¡Conectado! Perfil: %s" % ("Server" if multiplayer.is_server() else "Peer")
	_on_send_offer_pressed()
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_server_peer_connected)

func _on_server_peer_connected(id):
	# Cuando alguien se conecta al server, le mandamos lo que ya sabemos de otros
	for pid in incoming_offers:
		_relay_offer_to_others(pid, incoming_offers[pid], id)
func _on_disconnected():
	status_label.text = "Disconnected."
	$MainVbox/JoinOverlay.visible = true

func _on_connection_failed():
	status_label.text = "Connection failed."
	$MainVbox/JoinOverlay.visible = true

func _on_peer_connected(id):
	status_label.text = "Peer %d linked." % id
	# Important: Send current offer to the newly connected peer immediately
	_push_offer_to_peer(id)

func _on_clear_history_pressed():
	downloaded_hashes.clear()
	_save_settings()
	_update_receive_list()
	status_label.text = "Download history cleared."

func _on_clear_shared_pressed():
	shared_roots.clear()
	selected_files_to_send.clear()
	_save_settings()
	_trigger_immediate_sync()
	status_label.text = "Shared folders cleared."

# --- FILE GATHERING ---

func _on_add_files_pressed():
	$FileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	$FileDialog.popup_centered()

func _on_add_folder_pressed():
	$FileDialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	$FileDialog.popup_centered()

func _on_file_dialog_selected(p):
	if $FileDialog.file_mode == FileDialog.FILE_MODE_OPEN_DIR:
		var rpath = p.rstrip("/")
		# Avoid duplicates
		for r in shared_roots: if r.path == rpath: return
		shared_roots.append({"path": rpath, "is_dir": true})
		_scan_dir_recursive(rpath.get_base_dir(), rpath.get_file())
	else:
		for raw_path in p:
			var rpath = raw_path.rstrip("/")
			# Avoid duplicates
			var found = false
			for r in shared_roots: if r.path == rpath: found = true; break
			if found: continue
			
			shared_roots.append({"path": rpath, "is_dir": false})
			await _add_file_to_list(rpath.get_base_dir(), rpath.get_file())
	_save_settings()
	_trigger_immediate_sync()

func _scan_dir_recursive(base, rel):
	await _scan_to_list(base, rel, selected_files_to_send)
	_update_send_list()

func _add_file_to_list(base, rel):
	await _add_to_list(base, rel, selected_files_to_send)
	_update_send_list()

func _calculate_hash_only_full(p):
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var f = FileAccess.open(p, FileAccess.READ)
	if not f: return ""
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1024 * 512))
		if f.get_position() % (1024 * 1024 * 5) == 0: await get_tree().process_frame
	return ctx.finish().hex_encode()

# --- UNIFIED DIRECTORY RENDERING ---

func _update_send_list():
	_render_list(send_list, local_path_label, selected_files_to_send, local_view_path, true)

func _update_receive_list():
	_update_peer_buttons()
	if current_remote_peer != -1 and incoming_offers.has(current_remote_peer):
		_render_list(receive_list, remote_path_label, incoming_offers[current_remote_peer], remote_view_path, false)
	else:
		for c in receive_list.get_children(): c.queue_free()
		remote_path_label.text = "No hay archivos (Selecciona un Peer)"

func _update_peer_buttons():
	if not peer_selector: return
	for c in peer_selector.get_children(): c.queue_free()
	
	for pid in incoming_offers:
		var b = Button.new()
		b.text = "Peer %d" % pid
		if pid == 1: b.text = "SERVER (1)"
		b.toggle_mode = true
		b.button_pressed = (pid == current_remote_peer)
		b.pressed.connect(func(): _on_peer_selected(pid))
		peer_selector.add_child(b)

func _on_peer_selected(pid):
	current_remote_peer = pid
	remote_view_path = ""
	_update_receive_list()

func _is_file_complete(path: String, expected_size: int) -> bool:
	#prints("Espetativa :" , expected_size)
	if not FileAccess.file_exists(path): return false
	if expected_size > 0:
		var f = FileAccess.open(path, FileAccess.READ)
		if f:
			var sz = f.get_length()
			f.close()
			#prints("file size : " ,sz)
			if sz == 0: 
				return false
			elif expected_size != sz:
				return false
			
		
	return true

func _render_list(container, label, items, view_path, is_local):
	for c in container.get_children(): c.queue_free()
	label.text = ("Local: /" if is_local else "Remote: /") + view_path
	
	var dirs = {}
	var files = []
	
	for i in range(items.size()):
		var f = items[i]
		var rel = f.rel_path
		
		if view_path == "":
			if rel == "": files.append(i)
			else: dirs[rel.split("/")[0]] = true
		else:
			if rel.begins_with(view_path + "/"):
				var sub = rel.substr(view_path.length() + 1)
				if "/" in sub: dirs[sub.split("/")[0]] = true
				else: files.append(i)
	# Folders
	for dname in dirs:
		var panel = PanelContainer.new()
		var hb = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		panel.add_child(hb)
		
		if not is_local:
			var cb = CheckBox.new()
			cb.set_pressed_no_signal(_is_folder_selected(dname, view_path))
			cb.toggled.connect(_on_remote_folder_toggled.bind(dname, view_path))
			hb.add_child(cb)
			
		var b = Button.new()
		b.text = "📁 " + dname
		b.flat = true; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2)) # Yellow/Gold for folders
		b.pressed.connect(_on_dir_enter.bind(dname, is_local))
		hb.add_child(b)

		if is_local:
			var del = Button.new()
			del.text = " ✕ "
			del.custom_minimum_size = Vector2(30, 0)
			del.add_theme_color_override("font_color", Color(1, 0.3, 0.3)) # Red for delete
			del.pressed.connect(_on_local_delete_folder.bind(dname, view_path))
			hb.add_child(del)

		container.add_child(panel)
		
	# Files
	for idx in files:
		var f = items[idx]
		var panel = PanelContainer.new()
		var hb = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		panel.add_child(hb)
		
		if not is_local:
			var cb = CheckBox.new()
			cb.text = ""
			cb.button_pressed = remote_selection_state.get(current_remote_peer, {}).get(f.rel_path, false)
			cb.toggled.connect(func(v): _on_remote_file_toggled(f.rel_path, v))
			hb.add_child(cb)
			
			var l = Label.new()
			l.text = "📄 %s (%s)" % [f.name, _format_size(f.size)]
			l.size_flags_horizontal = SIZE_EXPAND_FILL
			
			var disk_path = global_save_path.path_join(f.rel_path)
			var already_done = false
			if _is_file_complete(disk_path, f.size):
				# Comprobar si el archivo en disco es el mismo que el ofrecido (por hash)
				if downloaded_hashes.has(f.hash): 
					already_done = true
			
			if already_done:
				l.text += " [DONE]"
				l.modulate = Color(0.4, 0.9, 0.4) 
			hb.add_child(l)
		else:
			var l = Label.new()
			l.text = "📄 " + f.name + " (" + _format_size(f.size) + ")"
			l.size_flags_horizontal = SIZE_EXPAND_FILL
			hb.add_child(l)
			
			var del = Button.new()
			del.text = " ✕ "
			del.custom_minimum_size = Vector2(30, 0)
			del.add_theme_color_override("font_color", Color(1, 0.3, 0.3)) # Red for delete
			del.pressed.connect(_on_local_delete_file.bind(idx))
			hb.add_child(del)
			
			var del2 = Button.new()
			del2.text = " ▶️ "
			del2.custom_minimum_size = Vector2(30, 0)
			del2.add_theme_color_override("font_color", Color(1.0, 0.302, 0.812, 1.0)) # Red for delete
			del2.pressed.connect(_play.bind(idx))
			hb.add_child(del2)
			
		container.add_child(panel)

# --- FOLDER SELECTION LOGIC ---

func _is_folder_selected(dname, view_path) -> bool:
	var full_dir = dname if view_path == "" else view_path + "/" + dname
	var items = incoming_offers.get(current_remote_peer, [])
	var state = remote_selection_state.get(current_remote_peer, {})
	
	var any_found = false
	for i in range(items.size()):
		var f_path = items[i].rel_path
		if f_path.begins_with(full_dir + "/"):
			any_found = true
			if not state.get(f_path, false): return false
	return any_found

func _on_remote_folder_toggled(value, dname, view_path):
	var full_dir = dname if view_path == "" else view_path + "/" + dname
	var items = incoming_offers.get(current_remote_peer, [])
	if not remote_selection_state.has(current_remote_peer): remote_selection_state[current_remote_peer] = {}
	var state = remote_selection_state[current_remote_peer]
	# Select everything inside the folder regardless of history
	# The download button will filter out what's already on disk later
	for i in range(items.size()):
		var f_path = items[i].rel_path
		if f_path.begins_with(full_dir + "/"):
			state[f_path] = value
	_update_receive_list()

# --- DELETION LOGIC ---

func _on_local_delete_folder(dname, vpath):
	var full = dname if vpath == "" else vpath + "/" + dname
	# Instant UI feedback: remove from current display list
	var new_send_list = []
	for f in selected_files_to_send:
		if not f.rel_path.begins_with(full + "/"):
			new_send_list.append(f)
	selected_files_to_send = new_send_list
	
	if vpath == "":
		for i in range(shared_roots.size()):
			if shared_roots[i].is_dir and shared_roots[i].path.get_file() == dname:
				shared_roots.remove_at(i)
				break
	else:
		# Persist removal via blacklist
		for f in selected_files_to_send:
			if f.rel_path.begins_with(full + "/"):
				blacklisted_hashes.append(f.hash)
	
	_trigger_immediate_sync()

func _on_local_delete_file(idx):
	prints("delete " , idx )
	prints(" archivo " ,str(selected_files_to_send[idx]))
	var f = selected_files_to_send[idx]
	blacklisted_hashes.append(f.hash)
	
	for i in range(shared_roots.size()):
		var f_path = f.get("_internal_path", f.get("path", ""))
		if !shared_roots[i].is_dir and shared_roots[i].path == f_path:
			shared_roots.remove_at(i)
			break
			
	selected_files_to_send.remove_at(idx)
	_trigger_immediate_sync()

func _trigger_immediate_sync():
	_last_fingerprint = "" # Force background scan to actually clear internals
	_update_send_list()
	_check_sync_local_changes() # This handles _on_send_offer_pressed and _save_settings

func _on_remote_file_toggled(f_hash, value):
	if not remote_selection_state.has(current_remote_peer): remote_selection_state[current_remote_peer] = {}
	remote_selection_state[current_remote_peer][f_hash] = value
	# Optional: _update_receive_list() to refresh folder checkboxes, 
	# but it might be annoying to re-render mid-selection.

func _on_dir_enter(dname, is_local):
	if is_local:
		local_view_path = dname if local_view_path == "" else local_view_path + "/" + dname
		_update_send_list()
	else:
		remote_view_path = dname if remote_view_path == "" else remote_view_path + "/" + dname
		_update_receive_list()

func _on_local_back():
	if local_view_path == "": return
	var p = local_view_path.split("/"); p.resize(p.size() - 1)
	local_view_path = "/".join(p); _update_send_list()

func _on_remote_back():
	if remote_view_path == "": return
	var p = remote_view_path.split("/"); p.resize(p.size() - 1)
	remote_view_path = "/".join(p); _update_receive_list()

# --- TRANSFER ---

func _on_send_offer_pressed():
	if not multiplayer.has_multiplayer_peer(): return
	for pid in multiplayer.get_peers(): _push_offer_to_peer(pid)
	status_label.text = "Syncing offer with %d peers..." % multiplayer.get_peers().size()

func _push_offer_to_peer(pid):
	rpc_id(pid, "start_offer_sync", -1) # -1 means 'from me'
	_send_offer_batch_async(pid, 0, -1)

func _send_offer_batch_async(pid, start_idx, origin_id):
	if start_idx >= selected_files_to_send.size():
		rpc_id(pid, "finish_offer_sync", origin_id)
		return
		
	var batch = []
	var end_idx = min(start_idx + 10, selected_files_to_send.size())
	for i in range(start_idx, end_idx):
		var m = selected_files_to_send[i].duplicate()
		if not FileAccess.file_exists(m._internal_path): continue
		m.erase("_internal_path") 
		m.erase("chunks")
		batch.append(m)
	
	if not batch.is_empty():
		rpc_id(pid, "append_offer_batch", origin_id, batch)
	
	get_tree().create_timer(0.01).timeout.connect(_send_offer_batch_async.bind(pid, end_idx, origin_id))

func _on_request_sync_pressed():
	for pid in multiplayer.get_peers(): rpc_id(pid, "request_remote_offer")
	status_label.text = "Sync request sent..."

@rpc("any_peer", "reliable", "call_local")
func request_remote_offer():
	var rid = multiplayer.get_remote_sender_id()
	_push_offer_to_peer(rid)


@rpc("any_peer", "reliable", "call_local")
func start_offer_sync(origin_id):
	var sid = origin_id if origin_id != -1 else multiplayer.get_remote_sender_id()
	_incoming_offer_buffer[sid] = []

@rpc("any_peer", "reliable", "call_local")
func append_offer_batch(origin_id, batch):
	var sid = origin_id if origin_id != -1 else multiplayer.get_remote_sender_id()
	if _incoming_offer_buffer.has(sid):
		_incoming_offer_buffer[sid].append_array(batch)

@rpc("any_peer", "reliable", "call_local")
func finish_offer_sync(origin_id):
	var sid = origin_id if origin_id != -1 else multiplayer.get_remote_sender_id()
	if _incoming_offer_buffer.has(sid):
		incoming_offers[sid] = _incoming_offer_buffer[sid]
		
		# Solo ponemos al primer peer como actual si no hay ninguno seleccionado o el actual se fue
		if current_remote_peer == -1 or not incoming_offers.has(current_remote_peer):
			current_remote_peer = sid
		
		# Server Relay: Retransmitir la oferta del cliente a todos los demas
		if multiplayer.is_server() and origin_id == -1:
			_relay_offer_to_others(sid, incoming_offers[sid])

		if not remote_selection_state.has(sid): remote_selection_state[sid] = {}
		_update_receive_list()
		_incoming_offer_buffer.erase(sid)
		status_label.text = "Catálogo de Peer %d actualizado." % sid

func _relay_offer_to_others(sid, offer_list, target_pid = -1):
	var targets = [target_pid] if target_pid != -1 else multiplayer.get_peers()
	for pid in targets:
		if pid != sid and pid != 1:
			rpc_id(pid, "start_offer_sync", sid)
			_relay_batch_async(pid, sid, offer_list, 0)

func _relay_batch_async(pid, origin_id, list, start_idx):
	var end_idx = min(start_idx + 10, list.size())
	if start_idx >= list.size():
		rpc_id(pid, "finish_offer_sync", origin_id)
		return
	var batch = list.slice(start_idx, end_idx)
	rpc_id(pid, "append_offer_batch", origin_id, batch)
	get_tree().create_timer(0.01).timeout.connect(_relay_batch_async.bind(pid, origin_id, list, end_idx))

func _on_download_selected_pressed():
	if global_save_path == "": _on_change_folder_pressed(); return
	var items = incoming_offers.get(current_remote_peer, [])
	var state = remote_selection_state.get(current_remote_peer, {})
	var count = 0
	
	for m in items:
		if state.get(m.rel_path, false):
			var disk_path = global_save_path.path_join(m.rel_path)
			if not _is_file_complete(disk_path, m.size):
				# Iniciamos usando el peer actual, pero el sistema rotara si esta ocupado
				_request_file(current_remote_peer, m)
				count += 1
	
	if count > 0: status_label.text = "Descargando %d archivos..." % count
	else: status_label.text = "Todo lo seleccionado ya existe."

func _request_file(sid, m):
	var full_dest = global_save_path.path_join(m.rel_path)
	prints("request_file ID.Peer sid : " , sid , " data : " , m  )
	for f_sharing in selected_files_to_send:
		if f_sharing.get("_internal_path", "") == full_dest:
			status_label.text = "ERROR: Destino protegido (es un archivo compartido)."
			return

	var target_dir = full_dest.get_base_dir()
	if target_dir != "": DirAccess.make_dir_recursive_absolute(target_dir)
		
	active_transfers[str(sid)+"_"+m.id] = {
		"path": full_dest, 
		"got_chunks": 0, "requested_chunks": 0, "chunk_hashes": [],
		"total": m.size, "hash": m.hash, "id": m.id,
		"owner_id": sid, # El peer que realmente tiene el archivo
		"fa": FileAccess.open(full_dest, FileAccess.WRITE),
		"full_ctx": HashingContext.new()
	}
	active_transfers[str(sid)+"_"+m.id].full_ctx.start(HashingContext.HASH_SHA256)
	
	status_label.text = "Ticket: Pidiendo metadatos..."
	rpc_id(1, "request_file_hashes", m.id, 0, sid) # Pedir vía server

@rpc("any_peer", "reliable", "call_local")
func request_file_hashes(file_id, start_idx, target_sid = -1):
	var rid = multiplayer.get_remote_sender_id()
	# RELAY SERVER: Si el mensaje no es para mi (Server), lo mando al dueño real
	if multiplayer.is_server() and target_sid != -1 and target_sid != 1:
		rpc_id(target_sid, "request_file_hashes", file_id, start_idx, rid)
		return

	if _total_active_upload_requests >= MAX_GLOBAL_UPLOAD_REQS:
		if rid == multiplayer.get_unique_id():
			peer_busy(file_id, target_sid)
		else:
			rpc_id(rid, "peer_busy", file_id, target_sid)
		return

	var m = null
	for f in selected_files_to_send:
		if f.id == file_id: m = f; break
	if not m: return
	
	var f = FileAccess.open(m._internal_path, FileAccess.READ)
	if not f: return
	f.seek(start_idx * CHUNK_SIZE)
	
	var batch = []
	for i in range(400):
		if f.get_position() >= f.get_length(): break
		var buf = f.get_buffer(CHUNK_SIZE)
		var ctx = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(buf)
		batch.append(ctx.finish().hex_encode())
	
	var is_last = f.get_position() >= f.get_length()
	
	# Determinar quién pidió realmente el archivo para saber a quién responder (o vía quién)
	var requester = target_sid if (target_sid != -1 and target_sid != multiplayer.get_unique_id()) else rid
	var next_hop = 1 if not multiplayer.is_server() else requester
	
	if next_hop == multiplayer.get_unique_id():
		receive_hashes_batch(file_id, batch, is_last, multiplayer.get_unique_id())
	else:
		# Si vamos al server para relay, pasamos el ID del requester final
		# Si el server envía directo, pasa su propio ID como origen
		var relay_arg = requester if next_hop == 1 else multiplayer.get_unique_id()
		rpc_id(next_hop, "receive_hashes_batch", file_id, batch, is_last, relay_arg)

@rpc("any_peer", "reliable", "call_local")
func peer_busy(file_id, target_sid = -1):
	var rid = multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and target_sid != -1 and target_sid != 1:
		rpc_id(target_sid, "peer_busy", file_id, rid)
		return
	status_label.text = "Peer ocupado, reintentando..."
	get_tree().create_timer(1.2).timeout.connect(func():
		for k in active_transfers:
			if active_transfers[k].id == file_id:
				var owner = active_transfers[k].owner_id
				rpc_id(1, "request_file_hashes", file_id, 0, owner)
				break
	)

@rpc("any_peer", "reliable", "call_local")
func receive_hashes_batch(file_id, batch, is_last, origin_sid = -1):
	var rid = multiplayer.get_remote_sender_id()
	# RELAY SERVER
	if multiplayer.is_server() and origin_sid != -1 and origin_sid != 1:
		rpc_id(origin_sid, "receive_hashes_batch", file_id, batch, is_last, rid)
		return

	var actual_source = rid
	if origin_sid != -1 and origin_sid != multiplayer.get_unique_id():
		actual_source = origin_sid
	var k = str(actual_source) + "_" + file_id
	if not active_transfers.has(k): return
	var t = active_transfers[k]
	t.chunk_hashes.append_array(batch)
	
	if not is_last:
		rpc_id(1, "request_file_hashes", file_id, t.chunk_hashes.size(), actual_source)
	else:
		# Empezar descarga de trozos
		for i in range(min(MAX_WINDOW, t.chunk_hashes.size())):
			t.requested_chunks += 1
			rpc_id(1, "request_chunk", file_id, i, actual_source)

@rpc("any_peer", "reliable", "call_local")
func request_chunk(file_id, chunk_idx, target_sid = -1):
	var rid = multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and target_sid != -1 and target_sid != 1:
		rpc_id(target_sid, "request_chunk", file_id, chunk_idx, rid)
		return
		
	_total_active_upload_requests += 1
	var m = null
	for f in selected_files_to_send:
		if f.id == file_id: m = f; break
	if not m: _total_active_upload_requests -= 1; return
	
	var f = FileAccess.open(m._internal_path, FileAccess.READ)
	if not f: _total_active_upload_requests -= 1; return
	f.seek(chunk_idx * CHUNK_SIZE)
	var buffer = f.get_buffer(CHUNK_SIZE)
	_bytes_out_window += buffer.size()
	var final_target = target_sid if (target_sid != -1 and target_sid != multiplayer.get_unique_id()) else rid
	var next_hop = 1 if not multiplayer.is_server() else final_target
	
	if next_hop == multiplayer.get_unique_id():
		receive_chunk(file_id, buffer, chunk_idx, multiplayer.get_unique_id())
	else:
		var relay_arg = final_target if next_hop == 1 else multiplayer.get_unique_id()
		rpc_id(next_hop, "receive_chunk", file_id, buffer, chunk_idx, relay_arg)
	_total_active_upload_requests -= 1

@rpc("any_peer", "reliable", "call_local")
func receive_chunk(file_id, data, chunk_idx, origin_sid = -1):
	var rid = multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and origin_sid != -1 and origin_sid != 1:
		rpc_id(origin_sid, "receive_chunk", file_id, data, chunk_idx, rid)
		return

	var actual_source = rid
	if origin_sid != -1 and origin_sid != multiplayer.get_unique_id():
		actual_source = origin_sid
	var k = str(actual_source) + "_" + file_id
	if not active_transfers.has(k): return
	var t = active_transfers[k]
	
	if download_speed_limit > 0 and (_bytes_in_window / 1024.0) > download_speed_limit:
		get_tree().create_timer(0.1).timeout.connect(receive_chunk.bind(file_id, data, chunk_idx, actual_source))
		return

	_bytes_in_window += data.size()
	var chunk_ctx = HashingContext.new()
	chunk_ctx.start(HashingContext.HASH_SHA256); chunk_ctx.update(data)
	if chunk_ctx.finish().hex_encode() != t.chunk_hashes[chunk_idx]:
		status_label.text = "Error en bloque %d. Re-pidiendo..." % chunk_idx
		rpc_id(1, "request_chunk", file_id, chunk_idx, actual_source) 
		return
		
	t.fa.seek(chunk_idx * CHUNK_SIZE)
	t.fa.store_buffer(data)
	t.full_ctx.update(data)
	t.got_chunks += 1
	if t.got_chunks % 10 == 0: _update_status_ui()
	
	if t.got_chunks < t.chunk_hashes.size():
		if t.requested_chunks < t.chunk_hashes.size():
			var next = t.requested_chunks
			t.requested_chunks += 1
			rpc_id(1, "request_chunk", file_id, next, actual_source)
	else:
		t.fa.close()
		_verify_finish(k)

func _verify_finish(k):
	var t = active_transfers[k]
	var final_hash = t.full_ctx.finish().hex_encode()
	if final_hash == t.hash:
		downloaded_hashes.append(final_hash); _save_settings(); _update_receive_list()
		status_label.text = "Download complete: %s" % t.path.get_file()
	else:
		status_label.text = "Error: Hash mismatch!"
	active_transfers.erase(k)

# --- SETTINGS ---
func _on_change_folder_pressed(): 
	$SaveDialog.popup_centered()



func _on_save_dir_selected(d):
	global_save_path = d
	$SettingsPanel/VBox/PathLabel.text = "Save to: " + d
	_save_settings()

func _on_copy_ticket_pressed():
	DisplayServer.clipboard_set(conn_string_display.text)
	status_label.text = "Copied."

func _format_speed(b_s: float) -> String:
	return _format_size(int(b_s)) + "/s"

func _format_size(b: int) -> String:
	if b < 1024:
		return str(b) + " B"
	elif b < 1024 * 1024:
		return "%.1f KB" % (b / 1024.0)
	elif b < 1024 * 1024 * 1024:
		return "%.1f MB" % (b / 1048576.0) # 1024^2
	elif b < 1024 * 1024 * 1024 * 1024:
		return "%.1f GB" % (b / 1073741824.0) # 1024^3
	else:
		return "%.1f TB" % (b / 1099511627776.0) # 1024^4



func _play(idx) -> void:
	var ruta = obtener_path(selected_files_to_send[idx])
	if ruta == "": 
		status_label.text = "Error: No se pudo encontrar la ruta del archivo."
		return

	ruta = ProjectSettings.globalize_path(ruta)
	var os_name = OS.get_name()

	if os_name == "Windows":
		OS.shell_open(ruta)
	elif os_name == "X11" or os_name == "Linux":
		OS.execute("xdg-open", [ruta], [], false)
	elif os_name == "OSX":
		OS.execute("open", [ruta], [], false)
	elif os_name == "Android":
		OS.shell_open(ruta)
	else:
		var resultado = OS.shell_open(ruta)
		if resultado != OK:
			print("No se pudo abrir el archivo: ", ruta)


func obtener_path(archivo: Dictionary) -> String:
	if archivo.has("_internal_path"):
		return archivo["_internal_path"]
	elif archivo.has("path"):
		return archivo["path"]
	else:
		return ""
