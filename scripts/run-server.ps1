# Launches the Anime Shop MCP server for Claude Code.
#
# Two things this works around.
#
# Claude Code keeps the server running for a whole session, which locks the executable it started, and
# building into that path then fails -- while a new build is exactly what a new tool needs. So the
# session runs a copy: this refreshes the copy at start-up, while nothing holds it, and runs that.
#
# A plugin arrives as source, so the first run may have nothing built at all. When that is the case,
# and the .NET SDK is here, this builds it once rather than leaving the person with a dead server.

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$project = Join-Path $root 'Server'
$built = Join-Path $project 'bin\Release\net10.0'
$live = Join-Path $project 'bin\live'
$builtDll = Join-Path $built 'AnimeShopMcp.dll'
$liveDll = Join-Path $live 'AnimeShopMcp.dll'

# Everything on stdout belongs to the MCP protocol, so progress and problems go to stderr.
function Note($message) { [Console]::Error.WriteLine("[anime-shop-mcp] $message") }

if (-not (Test-Path $builtDll) -and -not (Test-Path $liveDll)) {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Note 'Nothing is built yet and the .NET SDK is not on PATH. Install .NET 10, then run: dotnet build Server -c Release'
        exit 1
    }
    Note 'First run: building the server, which takes a moment.'
    & dotnet build $project -c Release --nologo 2>&1 | ForEach-Object { Note $_ }
    if ($LASTEXITCODE -ne 0) {
        Note 'The build failed. Run "dotnet build Server -c Release" yourself to see why.'
        exit 1
    }
}

# Only when the normal build is the newer one: a build sent straight into the live folder -- the way to
# refresh it while a session still holds bin/Release -- must not be overwritten by a stale bin/Release.
$builtIsNewer = (Test-Path $builtDll) -and
    (-not (Test-Path $liveDll) -or
     (Get-Item $builtDll).LastWriteTimeUtc -gt (Get-Item $liveDll).LastWriteTimeUtc)

if ($builtIsNewer) {
    try {
        New-Item -ItemType Directory -Force -Path $live | Out-Null
        Copy-Item -Path (Join-Path $built '*') -Destination $live -Recurse -Force
    }
    catch {
        Note "Could not refresh the live copy, running the old one: $_"
    }
}

$exe = Join-Path $live 'AnimeShopMcp.exe'
if (-not (Test-Path $exe)) {
    Note 'No server build found. Run: dotnet build Server -c Release'
    exit 1
}

& $exe @args
exit $LASTEXITCODE
