using AnimeShopMcp;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var builder = Host.CreateApplicationBuilder(args);

// stdout carries the MCP protocol; anything else written there corrupts it.
builder.Logging.AddConsole(options => options.LogToStandardErrorThreshold = LogLevel.Trace);

int port = int.TryParse(Environment.GetEnvironmentVariable("GAME_BRIDGE_PORT"), out var p) ? p : 47831;
builder.Services.AddSingleton(new BridgeClient(port));
builder.Services.AddSingleton(new GamePaths(Environment.GetEnvironmentVariable("GAME_PATH")));

builder.Services
    .AddMcpServer()
    .WithStdioServerTransport()
    .WithToolsFromAssembly();

await builder.Build().RunAsync();

namespace AnimeShopMcp
{
    // Where the game is installed. Only the log reader needs it, and it is the one setting this server
    // cannot work out for itself, so an unset GAME_PATH is reported rather than guessed at.
    public sealed record GamePaths(string GameDir)
    {
        public bool Known => !string.IsNullOrWhiteSpace(GameDir);

        public string Log(bool previous) =>
            Known ? Path.Combine(GameDir, "MelonLoader", previous ? "Latest.log.prev" : "Latest.log") : null;
    }
}
