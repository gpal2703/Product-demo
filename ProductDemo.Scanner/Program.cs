using Microsoft.Identity.Client;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

var tenantId = RequiredEnvironmentVariable("PBI_TENANT_ID");
var clientId = RequiredEnvironmentVariable("PBI_CLIENT_ID");
var clientSecret = RequiredEnvironmentVariable("PBI_CLIENT_SECRET");
var workspaceId = RequiredEnvironmentVariable("PBI_WORKSPACE_ID");

var app = ConfidentialClientApplicationBuilder
    .Create(clientId)
    .WithClientSecret(clientSecret)
    .WithAuthority($"https://login.microsoftonline.com/{tenantId}")
    .Build();

var token = await app
    .AcquireTokenForClient(
        new[] { "https://analysis.windows.net/powerbi/api/.default" })
    .ExecuteAsync();

using var http = new HttpClient
{
    BaseAddress = new Uri("https://api.powerbi.com/v1.0/myorg/")
};

http.DefaultRequestHeaders.Authorization =
    new AuthenticationHeaderValue("Bearer", token.AccessToken);

var requestBody = JsonSerializer.Serialize(new
{
    workspaces = new[] { workspaceId }
});

using var startResponse = await http.PostAsync(
    "admin/workspaces/getInfo?datasetSchema=true&datasetExpressions=true&lineage=true",
    new StringContent(requestBody, Encoding.UTF8, "application/json"));

var startJson = await ReadSuccessAsync(startResponse);
using var startDocument = JsonDocument.Parse(startJson);
var scanId = startDocument.RootElement.GetProperty("id").GetString()
    ?? throw new InvalidOperationException("Power BI did not return a scan ID.");

var succeeded = false;

for (var attempt = 0; attempt < 40; attempt++)
{
    await Task.Delay(TimeSpan.FromSeconds(30));

    using var statusResponse =
        await http.GetAsync($"admin/workspaces/scanStatus/{scanId}");

    var statusJson = await ReadSuccessAsync(statusResponse);
    using var statusDocument = JsonDocument.Parse(statusJson);
    var status = statusDocument.RootElement.GetProperty("status").GetString();

    if (status == "Succeeded")
    {
        succeeded = true;
        break;
    }

    if (status == "Failed")
    {
        throw new InvalidOperationException($"The Power BI scan failed: {statusJson}");
    }
}

if (!succeeded)
{
    throw new TimeoutException("The scan did not finish within 20 minutes.");
}

using var resultResponse =
    await http.GetAsync($"admin/workspaces/scanResult/{scanId}");

var resultJson = await ReadSuccessAsync(resultResponse);
await File.WriteAllTextAsync("scan-result.json", resultJson);

Console.WriteLine("Scan complete. Results saved to scan-result.json.");

var sqlConnectionString = Environment.GetEnvironmentVariable("SQLMI_CONNECTION_STRING");
if (string.IsNullOrWhiteSpace(sqlConnectionString))
{
    Console.WriteLine("SQL MI load skipped. Set SQLMI_CONNECTION_STRING to enable it.");
}
else
{
    await new SqlMetadataLoader(sqlConnectionString).LoadAsync(resultJson);
    Console.WriteLine("Metadata loaded to SQL MI.");
}

static string RequiredEnvironmentVariable(string name) =>
    Environment.GetEnvironmentVariable(name)
    ?? throw new InvalidOperationException($"Set the {name} environment variable.");

static async Task<string> ReadSuccessAsync(HttpResponseMessage response)
{
    var body = await response.Content.ReadAsStringAsync();

    if (!response.IsSuccessStatusCode)
    {
        throw new HttpRequestException(
            $"Power BI returned {(int)response.StatusCode}: {body}");
    }

    return body;
}