extends SceneTree
## 에셋 묶음(GLB/DAE) 속 모델 이름·크기 출력:  godot --headless --path . --script res://tools/pack_inspect.gd -- res://assets/3d/fantasy/TreesPack.glb
func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var ps: PackedScene = load(path)
		var root: Node = ps.instantiate()
		print("== ", path)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var cur: Node = m
			while cur != null and cur != root:
				if cur is Node3D:
					xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			var ab := xf * m.get_aabb()
			var tris := 0
			for si in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(si)
				tris += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
			print("%-28s size=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f) tris=%d" % [m.name, ab.size.x, ab.size.y, ab.size.z, ab.position.x, ab.position.y, ab.position.z, tris])
		root.free()
	quit()
