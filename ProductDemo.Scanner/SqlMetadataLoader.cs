using Microsoft.Data.SqlClient;
using System.Data;

internal sealed class SqlMetadataLoader(string connectionString)
{
    public async Task LoadAsync(string payload, CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var command = new SqlCommand("dbo.LoadPowerBiMetadataScan", connection)
        {
            CommandType = CommandType.StoredProcedure
        };
        command.Parameters.Add("@Payload", SqlDbType.NVarChar, -1).Value = payload;

        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}