class_name MechFogView3D
extends Node
## 仍由二维视野权威决定可见性；共用纹理供三维地面和模型材质采样。

const FOG_SHADER: Shader = preload("res://presentation/map_fog_3d.gdshader")
var _revision: int = -1
var _generation: int = -1
var _texture: ImageTexture
var _materials: Dictionary = {}


func material(ground: bool = false) -> ShaderMaterial:
	if not _materials.has(ground):
		if _texture == null:
			_texture = ImageTexture.create_from_image(Image.create_from_data(1, 1, false, Image.FORMAT_R8, PackedByteArray([0])))
		var result := ShaderMaterial.new()
		result.shader = FOG_SHADER
		result.set_shader_parameter("fog_cells", _texture)
		result.set_shader_parameter("ground_grid", ground)
		_materials[ground] = result
	return _materials[ground]


func present(vision: Dictionary, generation: int, _outline: PackedVector2Array) -> void:
	if _revision == vision["revision"] and _generation == generation:
		return
	_revision = vision["revision"]
	_generation = generation
	var dimensions: Vector2i = vision["dimensions"]
	var cells: PackedByteArray = vision["cells"]
	var pixels := PackedByteArray()
	pixels.resize(cells.size())
	for index: int in range(cells.size()):
		pixels[index] = 255 if cells[index] == MechVisionSystem.State.VISIBLE else (128 if cells[index] == MechVisionSystem.State.EXPLORED else 0)
	var image: Image = Image.create_from_data(dimensions.x, dimensions.y, false, Image.FORMAT_R8, pixels)
	if _texture == null:
		material()
	if _texture.get_size() != Vector2(dimensions):
		_texture.set_image(image)
	else:
		_texture.update(image)
	for value: ShaderMaterial in _materials.values():
		value.set_shader_parameter("map_dimensions", Vector2(dimensions))
