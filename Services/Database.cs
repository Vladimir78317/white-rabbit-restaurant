using System.Data;
using Microsoft.Data.SqlClient;

namespace WhiteRabbitRestaurant.Services;

public static class Database
{
    // При другом имени сервера задайте WHITE_RABBIT_CONNECTION или измените эту строку.
    public static string ConnectionString => Environment.GetEnvironmentVariable("WHITE_RABBIT_CONNECTION")
        ?? "Server=.;Database=WhiteRabbitRestaurant;Trusted_Connection=True;TrustServerCertificate=True;";

    public static string ConnectionTargetForLog
    {
        get
        {
            try
            {
                var builder = new SqlConnectionStringBuilder(ConnectionString);
                return $"SQL Server={builder.DataSource}; Database={builder.InitialCatalog}";
            }
            catch
            {
                return "SQL Server/Database: не удалось определить";
            }
        }
    }

    public static SqlParameter P(string name, object? value) => new(name, value ?? DBNull.Value);

    public static async Task<DataTable> ProcedureAsync(string procedure, params SqlParameter[] parameters)
    {
        await using var connection = new SqlConnection(ConnectionString);
        await using var command = new SqlCommand(procedure, connection) { CommandType = CommandType.StoredProcedure };
        command.Parameters.AddRange(parameters);
        await connection.OpenAsync();
        await using var reader = await command.ExecuteReaderAsync();
        var table = new DataTable();
        table.Load(reader);
        return table;
    }

    public static async Task<DataTable> QueryAsync(string sql)
    {
        await using var connection = new SqlConnection(ConnectionString);
        await using var command = new SqlCommand(sql, connection);
        await connection.OpenAsync();
        await using var reader = await command.ExecuteReaderAsync();
        var table = new DataTable();
        table.Load(reader);
        return table;
    }
}
