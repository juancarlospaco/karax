import browsers, os, osproc, parseopt, strutils, tables, threadpool, times
import static_server

const cssBulma = """
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/bulma/0.9.1/css/bulma.min.css">
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css">
""" ## https://bulma.io/documentation

const cssSpectre = """
  <link rel="stylesheet" href="https://unpkg.com/spectre.css/dist/spectre.min.css"/>
  <link rel="stylesheet" href="https://unpkg.com/spectre.css/dist/spectre-exp.min.css"/>
  <link rel="stylesheet" href="https://unpkg.com/spectre.css/dist/spectre-icons.min.css"/>
""" ## https://picturepan2.github.io/spectre/experimentals.html

const html = """<!DOCTYPE html>
<html>
  <head>
    <meta content="width=device-width, initial-scale=1" name="viewport" />
    <title>$1</title>
    $2
  </head>
  <body id="body" class="site">
    <div id="ROOT"></div>
    <script type="text/javascript" src="/app.js"></script>
    $3
  </body>
</html>
"""

const websocket = """
<script type="text/javascript">
var ws = new WebSocket("ws://localhost:8080/ws");

ws.onopen = function(evt) {
  console.log("Connection open ...");
  ws.send("Hello WebSockets!");
};

ws.onmessage = function(evt) {
  console.log( "Received Message: " + evt.data);
  if (evt.data == "refresh") {
    window.location.href = window.location.href
  }
};

ws.onclose = function(evt) {
  console.log("Connection closed.");
};
</script>
"""

const helpMsg = """karun options file.nim

options:
  --run           Compile and run the Nim file on the web browser.
  -w              Watch for changes on the Nim file.
  --css:file.css  Use "file.css" for stylesheet.
  --css:bulma     Use Bulma CSS for stylesheet.
  --css:spectre   Use Spectre CSS for stylesheet.
  --help          Show this help and quit.
"""

const ignoredPaths = [".git", ".github", "node_modules", "__pycache__", "__pypackages__"]

proc exec(cmd: string) =
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    quit "External command failed:\n" & cmd & "\n" & output, exitCode

proc build(rest: string, selectedCss: string, run: bool, watch: bool) =
  echo("Building...")
  if watch:
    discard os.execShellCmd("nim js --out:app.js " & rest)
  else:
    exec "nim js --out:app.js " & rest
  let script = if run and watch: websocket else: ""
  writeFile("app.html", html % ["app", selectedCss, script])
  if run: openDefaultBrowser("http://localhost:8080")

proc watchBuild(filePath: string, selectedCss: string, rest: string) {.thread.} =
  var files: Table[string, Time] = {"path": getLastModificationTime(".")}.toTable
  while true:
    sleep(300)
    for path in walkDirRec("."):
      if path in ignoredPaths:
        continue
      var (_, _, ext) = splitFile(path)
      if ext in [".scss", ".sass", ".less", ".styl", ".pcss", ".postcss"]:
        continue
      if files.hasKey(path):
        if files[path] != getLastModificationTime(path):
          echo("File changed: " & path)
          build(rest, selectedCss, false, true)
          files[path] = getLastModificationTime(path)
      else:
        if absolutePath(path) in [absolutePath("app.js"), absolutePath("app.html")]:
          continue
        files[path] = getLastModificationTime(path)

proc serve() {.thread.} =
  serveStatic()

proc main =
  var op = initOptParser()
  var rest = op.cmdLineRest
  var file = ""
  var run = false
  var watch = false
  var selectedCss = ""
  while true:
    op.next()
    case op.kind
    of cmdLongOption:
      case op.key
      of "run":
        run = true
        rest = rest.replace("--run ")
      of "css":
        case op.val
        of "bulma", "": selectedCss = cssBulma
        of "spectre": selectedCss = cssSpectre
        else: selectedCss = readFile(op.val)
        rest = rest.substr(rest.find(" "))
      of "help": quit helpMsg, 0
      else: discard
    of cmdShortOption:
      if op.key == "r":
        run = true
        rest = rest.replace("-r ")
      if op.key == "w":
        watch = true
        rest = rest.replace("-w ")
    of cmdArgument: file = op.key
    of cmdEnd: break

  if file.len == 0: quit helpMsg
  if run:
    spawn serve()
  if watch:
    spawn watchBuild(file, selectedCss, rest)
  build(rest, selectedCss, run, watch)
  sync()

main()
