using Microsoft.Data.SqlClient;
using System.Data;

internal sealed class SqlMetadataLoader(string connectionString)
{
    public async Task LoadAsync(
        string payload,
        string environmentName,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var command = new SqlCommand("dbo.LoadPowerBiMetadataScan", connection)
        {
            CommandType = CommandType.StoredProcedure
        };
        command.Parameters.Add("@Payload", SqlDbType.NVarChar, -1).Value = payload;
        command.Parameters.Add("@EnvironmentName", SqlDbType.NVarChar, 50).Value = environmentName;

        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}