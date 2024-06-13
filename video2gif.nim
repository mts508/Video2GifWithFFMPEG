import winim/[lean, shell]
import strutils
import os
import osproc
import json
import strformat
import winim


const bufferSize = 65536
converter intToDWORD(x: int): DWORD = DWORD x

proc getFileNames(): seq[string] =
  var buffer = newMString(bufferSize)
  var o = OPENFILENAMEA(
      lStructSize: sizeof OPENFILENAMEA,
      lpstrTitle: -$"Elegir archivo mp4 para transformar a gif",
      lpstrFile: &buffer,
      nMaxFile: bufferSize,
      Flags: OFN_EXPLORER or OFN_ALLOWMULTISELECT
  )

  if GetOpenFileNameA(o):
    var ret = $buffer
    ret.setLen(ret.find("\0\0"))
    if ret.find("\0") == -1:
        return @[ret]
    else:
        var strings = ret.split("\0")
        var directory = strings[0]
        strings.delete(0)
        var files: seq[string] = @[]
        for filename in strings:
            files.add(directory / filename )
        return files
  else:
    return @[]

proc getWidth(filename: string): int =
    #ffprobe -v error -select_streams v:0 -show_entries stream=width -of json $input_file
    var process = startProcess("bin/ffprobe.exe", args = @["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width", "-of", "json", filename])
    discard process.waitForExit()
    var (lines, exitCode) = process.readLines()
    var output = lines.join("\n")

    if exitCode != 0:
        echo output
        raise newException(OSError, "ffprobe failed with code " & $exitCode)
    
    var data = parseJson(output)
    var width: JsonNode = data["streams"][0]["width"]

    return width.getInt()

proc generatePalette(input_file, filters, palette: string) =
    # ffmpeg -v warning -i "$input_file" -vf "$filters,palettegen" -y "$palette
    var process = startProcess("bin/ffmpeg", args = @["-v", "warning", "-i", input_file, "-vf", &"{filters},palettegen", "-y", palette])
    discard process.waitForExit()

    var (lines, exitCode) = process.readLines()
    if exitCode != 0:
        echo lines.join("\n")
        raise newException(OSError, "ffmpeg failed with code " & $exitCode)

proc showMessage(title, msg: string) =
    InitCommonControls() # Windows XP needs this
    MessageBox(0, msg, title, 0)

proc convertFile(input_file: string) =
    var output_file = input_file.split(".")[0..^2].join(".") & ".gif"
    var width = getWidth(input_file)
    var temp_dir: string = getTempDir()
    var filters = &"fps=10,scale={width}:-1:flags=lanczos"

    var palette = temp_dir / "palette.png"
    generatePalette(input_file, filters, palette)

    echo output_file
    # ffmpeg -v warning -i "$input_file" -i $palette -lavfi "$filters [x]; [x][1:v] paletteuse" -y "$output_file"
    var process = startProcess("bin/ffmpeg", args = @["-v", "warning", "-i", input_file, "-i", palette, "-lavfi", &"{filters} [x]; [x][1:v] paletteuse", "-y", output_file])
    discard process.waitForExit()

    var (lines, exitCode) = process.readLines()
    if exitCode != 0:
        echo lines.join("\n")
        raise newException(OSError, "ffmpeg failed with code " & $exitCode)
    showMessage("Todo piola", "Archivo convertido correctamente:\n" & output_file)

var files_to_convert = getFileNames()

try:
    for filename in files_to_convert:
        convertFile(filename)
except OSError:
    let msg = getCurrentExceptionMsg()
    showMessage("Error", "Algo fallo: " & msg)