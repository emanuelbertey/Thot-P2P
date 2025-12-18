extends Control

# File Fast - Pro Version with Batch Folder Downloading
# Features: Virtual directory browsing, recursive downloading, metadata persistence

const CHUNK_SIZE = 32 * 1024
const SAVE_FILE = "user://file_fast_save.dat"

# Structure: {path, rel_path, name, size, hash, format}
var selected_files_to_send = []
var incoming_offers = {} # { peer_id: Array }
var active_transfers = {}
var shared_roots = [] # Array of Dict {path, is_dir}
var blacklisted_hashes = [] # Hashes the user wants to keep private
var downloaded_hashes = []
var global_save_path = ""
var _hash_cache = {} # { base_path: { rel_within_base: {h, m, s} } }

# Selection State for Remote files (persistent across dirs)
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

func _ready():
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.server_disconnected.connect(_on_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	
	_load_settings()
	$SettingsPanel.visible = false
	
	$MainVbox/HBox/SendSection/PathHeader/BackBtn.pressed.connect(_on_local_back)
	$MainVbox/HBox/ReceiveSection/PathHeader/BackBtn.pressed.connect(_on_remote_back)
	
	# Background sync timer (every 10 seconds)
	var timer = Timer.new()
	timer.wait_time = 30.0
	timer.autostart = true
	timer.timeout.connect(_check_sync_local_changes)
	add_child(timer)

#---------- Force 
	_check_sync_local_changes()

# --- SYNC LOGIC ---




var _syncing = false
var _last_fingerprint = ""


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
		if r.is_dir and DirAccess.dir_exists_absolute(r.path):
			# Use parent as base and folder name as start of relative path
			await _scan_to_list(r.path.get_base_dir(), r.path.get_file(), new_list)
		elif !r.is_dir and FileAccess.file_exists(r.path):
			# Use parent as base and file name as relative path
			await _add_to_list(r.path.get_base_dir(), r.path.get_file(), new_list)
	
	selected_files_to_send = new_list
	_update_send_list()
	_on_send_offer_pressed()
	_save_settings()
	
	status_label.text = "Sync: Offer updated."
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
			if d.current_is_dir(): await _scan_to_list(base, rel.path_join(n), list)
			else: await _add_to_list(base, rel.path_join(n), list)
			n = d.get_next()

func _add_to_list(base, rel, list):
	var p = base.path_join(rel)
	var mtime = FileAccess.get_modified_time(p)
	var f = FileAccess.open(p, FileAccess.READ)
	var fsize = f.get_length()
	f.close()
	var h = ""
	
	# Check cache safely (nested structure)
	var cached_base = _hash_cache.get(base)
	if not (cached_base is Dictionary):
		cached_base = {}
		_hash_cache[base] = cached_base
		
	var entry = cached_base.get(rel)
	if entry is Dictionary and entry.get("m") == mtime and entry.get("s") == fsize:
		h = entry.h
	else:
		h = await _calculate_hash_progressive(p)
		cached_base[rel] = {"h": h, "m": mtime, "s": fsize}
	
	if _is_blacklisted(h): return
	list.append({
		"path": p, "rel_path": rel, "name": p.get_file(), "size": fsize, "hash": h, "format": p.get_extension()
	})

# --- SAVE/LOAD ---

func _save_settings():
	var data = {
		"save_path": global_save_path,
		"shared_roots": shared_roots,
		"blacklisted": blacklisted_hashes,
		"hashes": downloaded_hashes,
		"hash_cache": _hash_cache
	}
	var f = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if f: f.store_var(data)

func _load_settings():
	if not FileAccess.file_exists(SAVE_FILE): return
	var f = FileAccess.open(SAVE_FILE, FileAccess.READ)
	var data = f.get_var()
	if not data is Dictionary: return
	
	global_save_path = data.get("save_path", "")
	downloaded_hashes = data.get("hashes", [])
	shared_roots = data.get("shared_roots", [])
	blacklisted_hashes = data.get("blacklisted", [])
	_hash_cache = data.get("hash_cache", {})
	
	for root in shared_roots:
		if root.is_dir:
			if DirAccess.dir_exists_absolute(root.path):
				await _scan_dir_recursive(root.path, root.path.get_file())
		else:
			if FileAccess.file_exists(root.path):
				await _add_file_to_list(root.path, "")
				
	$SettingsPanel/VBox/PathLabel.text = "Save to: " + (global_save_path if global_save_path != "" else "Not set")

# --- UI LOGIC ---

func _on_settings_pressed():
	$SettingsPanel.visible = !$SettingsPanel.visible

func _on_close_settings_pressed():
	$SettingsPanel.visible = false

# --- CONNECTION ---

func _on_host_pressed():
	var s = IrohServer.start()
	multiplayer.multiplayer_peer = s
	conn_string_display.text = s.connection_string()
	$MainVbox/JoinOverlay.visible = false
	status_label.text = "Hosting..."

func _on_join_pressed():
	var t = $MainVbox/JoinOverlay/VBox/TicketInput.text
	if t.is_empty(): return
	multiplayer.multiplayer_peer = IrohClient.connect(t)
	$MainVbox/JoinOverlay.visible = false
	status_label.text = "Joining..."

func _on_connected():
	_on_send_offer_pressed()
	status_label.text = "Connected!"
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

# --- FILE GATHERING ---

func _on_add_files_pressed():
	$FileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	$FileDialog.popup_centered()

func _on_add_folder_pressed():
	$FileDialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	$FileDialog.popup_centered()

func _on_file_dialog_selected(p):
	if $FileDialog.file_mode == FileDialog.FILE_MODE_OPEN_DIR:
		shared_roots.append({"path": p, "is_dir": true})
		_scan_dir_recursive(p.get_base_dir(), p.get_file())
	else:
		for path in p:
			shared_roots.append({"path": path, "is_dir": false})
			await _add_file_to_list(path.get_base_dir(), path.get_file())
	_save_settings()

func _scan_dir_recursive(base, rel):
	await _scan_to_list(base, rel, selected_files_to_send)
	_update_send_list()

func _add_file_to_list(base, rel):
	await _add_to_list(base, rel, selected_files_to_send)
	_update_send_list()

func _calculate_hash_progressive(p):
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var f = FileAccess.open(p, FileAccess.READ)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1024 * 512))
		await get_tree().process_frame
	return ctx.finish().hex_encode()

# --- UNIFIED DIRECTORY RENDERING ---

func _update_send_list():
	_render_list(send_list, local_path_label, selected_files_to_send, local_view_path, true)

func _update_receive_list():
	if current_remote_peer != -1:
		_render_list(receive_list, remote_path_label, incoming_offers[current_remote_peer], remote_view_path, false)

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
			if FileAccess.file_exists(disk_path):
				l.text += " (Done)"
				l.modulate = Color(0.5, 1.0, 0.5) # Light green for items present on disk
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
		if !shared_roots[i].is_dir and shared_roots[i].path == f.path:
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
	for pid in multiplayer.get_peers(): _push_offer_to_peer(pid)
	status_label.text = "Syncing offer with %d peers..." % multiplayer.get_peers().size()

func _push_offer_to_peer(pid):
	rpc_id(pid, "start_offer_sync")
	var batch = []
	for i in range(selected_files_to_send.size()):
		var m = selected_files_to_send[i].duplicate()
		if m.has("path"): m.erase("path") # Privacy & Memory: hide absolute local paths
		batch.append(m)
		if batch.size() >= 40:
			rpc_id(pid, "append_offer_batch", batch)
			batch = []
			await get_tree().create_timer(0.01).timeout
	if batch.size() > 0:
		rpc_id(pid, "append_offer_batch", batch)
	rpc_id(pid, "finish_offer_sync")

func _on_request_sync_pressed():
	for pid in multiplayer.get_peers(): rpc_id(pid, "request_remote_offer")
	status_label.text = "Sync request sent..."

@rpc("any_peer", "reliable")
func request_remote_offer():
	var rid = multiplayer.get_remote_sender_id()
	_push_offer_to_peer(rid)

var _incoming_offer_buffer = {}

@rpc("any_peer", "reliable")
func start_offer_sync():
	var sid = multiplayer.get_remote_sender_id()
	_incoming_offer_buffer[sid] = []

@rpc("any_peer", "reliable")
func append_offer_batch(batch):
	var sid = multiplayer.get_remote_sender_id()
	if _incoming_offer_buffer.has(sid):
		_incoming_offer_buffer[sid].append_array(batch)

@rpc("any_peer", "reliable")
func finish_offer_sync():
	var sid = multiplayer.get_remote_sender_id()
	if _incoming_offer_buffer.has(sid):
		incoming_offers[sid] = _incoming_offer_buffer[sid]
		current_remote_peer = sid
		# preserve selection state for existing paths
		if not remote_selection_state.has(sid): remote_selection_state[sid] = {}
		_update_receive_list()
		_incoming_offer_buffer.erase(sid)
		status_label.text = "New offer received from %d" % sid

func _on_download_selected_pressed():
	if global_save_path == "": _on_change_folder_pressed(); return
	var items = incoming_offers.get(current_remote_peer, [])
	var state = remote_selection_state.get(current_remote_peer, {})
	var count = 0
	
	for m in items:
		if state.get(m.rel_path, false):
			var disk_path = global_save_path.path_join(m.rel_path)
			if not FileAccess.file_exists(disk_path):
				_request_file(current_remote_peer, m)
				count += 1
	
	if count > 0: status_label.text = "Downloading %d items..." % count
	else: status_label.text = "All selected items are already on disk."

func _request_file(sid, m):
	var full_dest = global_save_path.path_join(m.rel_path)
	var target_dir = full_dest.get_base_dir()
	if target_dir != "": # Only make dir if it's not the root of global_save_path
		DirAccess.make_dir_recursive_absolute(target_dir)
	var path = full_dest
	if FileAccess.file_exists(path): path = full_dest.get_base_dir().path_join(str(Time.get_ticks_msec()) + "_" + m.name)
	active_transfers[str(sid)+"_"+m.hash] = {
		"path": path, "got": 0, "total": m.size, "hash": m.hash, "fa": FileAccess.open(path, FileAccess.WRITE)
	}
	rpc_id(sid, "accept_offer", m.hash)

@rpc("any_peer", "reliable")
func accept_offer(file_hash):
	var rid = multiplayer.get_remote_sender_id()
	var m = null
	for f in selected_files_to_send:
		if f.hash == file_hash:
			m = f
			break
	
	if not m:
		status_label.text = "Error: Peer requested unknown file."
		return

	var f = FileAccess.open(m.path, FileAccess.READ)
	if not f: return
	
	while f.get_position() < f.get_length():
		rpc_id(rid, "receive_chunk", file_hash, f.get_buffer(CHUNK_SIZE))
		if f.get_position() % (CHUNK_SIZE * 10) == 0: await get_tree().process_frame

@rpc("any_peer", "reliable")
func receive_chunk(file_hash, data):
	var k = str(multiplayer.get_remote_sender_id()) + "_" + file_hash
	if not active_transfers.has(k): return
	var t = active_transfers[k]
	t.fa.store_buffer(data)
	t.got += data.size()
	if t.got >= t.total:
		t.fa.close(); _verify_finish(k)

func _verify_finish(k):
	var t = active_transfers[k]
	var h = await _calculate_hash_progressive(t.path)
	if h == t.hash:
		downloaded_hashes.append(h); _save_settings(); _update_receive_list()
	active_transfers.erase(k)
	status_label.text = "Batch Progress: %d active" % active_transfers.size()

# --- SETTINGS ---
func _on_change_folder_pressed(): $SaveDialog.popup_centered()
func _on_save_dir_selected(d):
	global_save_path = d
	$SettingsPanel/VBox/PathLabel.text = "Save to: " + d
	_save_settings()

func _on_copy_ticket_pressed():
	DisplayServer.clipboard_set(conn_string_display.text)
	status_label.text = "Copied."

#func _format_size(b):
	#if b < 1024: return str(b)+"B"
	#return "%.1fMB" % (b/1048576.0)
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
	var os_name = OS.get_name()

	if os_name == "Windows":
		#OS.execute("cmd", ["/c", "start", ruta], [], false)
		OS.shell_open(ruta)

	elif os_name == "X11" or os_name == "Linux":
		OS.execute("xdg-open", [ruta], [], false)

	elif os_name == "OSX":
		OS.execute("open", [ruta], [], false)

	else:
		var resultado = OS.shell_open(ruta)
		if resultado != OK:
			print("No se pudo abrir el archivo: ", ruta)


func obtener_path(archivo: Dictionary) -> String:
	if archivo.has("path"):
		return archivo["path"]
	else:
		return ""
