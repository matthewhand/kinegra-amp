extends Reference
# One verified original texture per app; no dynamic networking or replacement loop.
const PATH = "res://assets/original/neon-horizon-v1.bin"
const SHA256 = "39234ed3276dd1ec54e5edb0e0e0ff004f1483859ae248720ede4919cbdf8b25"
const MAX_ENCODED = 2097152
const MAX_PIXELS = 1573538

static func load_texture():
    var file = File.new()
    if not file.file_exists(PATH) or file.open(PATH, File.READ) != OK:
        return null
    var n = file.get_len()
    if n <= 24 or n > MAX_ENCODED:
        file.close()
        return null
    var bytes = file.get_buffer(n)
    file.close()
    var digest = HashingContext.new()
    digest.start(HashingContext.HASH_SHA256)
    digest.update(bytes)
    if digest.finish().hex_encode() != SHA256:
        return null
    # Exact hash pins PNG dimensions before allocation; verify again after decode.
    var image = Image.new()
    if image.load_png_from_buffer(bytes) != OK:
        return null
    if image.get_width() != 1774 or image.get_height() != 887 or image.get_width() * image.get_height() > MAX_PIXELS:
        return null
    var texture = ImageTexture.new()
    # No NPOT repeat or mipmap allocation on the GLES2 target.
    texture.create_from_image(image, Texture.FLAG_FILTER)
    return texture
