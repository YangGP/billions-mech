class_name MechFogView
extends Node2D
## 单张投影纹理，仅在权威可见性变化时重建。

var _revision: int = -1
var _generation: int = -1
var _texture: ImageTexture
var _polygon := PackedVector2Array()
var _uvs := PackedVector2Array()


## 依据视野快照重建迷雾纹理；修订号未变时直接跳过。
func present(vision: Dictionary, generation: int, outline: PackedVector2Array) -> void:
	if _revision == vision["revision"] and _generation == generation:
		return
	_revision = vision["revision"]
	_generation = generation
	var dimensions: Vector2i = vision["dimensions"]
	var cells: PackedByteArray = vision["cells"]
	var pixels := PackedByteArray()
	pixels.resize(cells.size() * 4)
	for index: int in range(cells.size()):
		pixels[index * 4] = 3
		pixels[index * 4 + 1] = 6
		pixels[index * 4 + 2] = 9
		pixels[index * 4 + 3] = 0 if cells[index] == MechVisionSystem.State.VISIBLE else (150 if cells[index] == MechVisionSystem.State.EXPLORED else 255)
	var image: Image = Image.create_from_data(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8, pixels)
	if _texture == null or _texture.get_size() != Vector2(dimensions):
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)
	_polygon.clear()
	_uvs.clear()
	# 按真实地图多边形裁剪，同时覆盖不完整的边界格。
	for point: Vector2 in outline:
		_polygon.append(MechIsoGeometry.project(point))
		_uvs.append(point / Vector2(dimensions))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func _draw() -> void:
	if _texture != null:
		draw_polygon(_polygon, PackedColorArray([Color.WHITE]), _uvs, _texture)
