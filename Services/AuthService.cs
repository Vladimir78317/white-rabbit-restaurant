using WhiteRabbitRestaurant.Models;

namespace WhiteRabbitRestaurant.Services;

public static class AuthService
{
    public static async Task<UserSession> LoginAsync(string login, string password)
    {
        var data = await Database.ProcedureAsync("dbo.sp_AuthenticateUser", Database.P("@Login", login), Database.P("@Password", password));
        if (data.Rows.Count == 0) throw new InvalidOperationException("Не получены данные пользователя.");
        var row = data.Rows[0];
        return new UserSession(
            Convert.ToInt32(row["UserId"]),
            Convert.ToString(row["Login"]) ?? string.Empty,
            Convert.ToString(row["FullName"]) ?? string.Empty,
            Convert.ToString(row["RoleCode"]) ?? string.Empty,
            Convert.ToString(row["RoleName"]) ?? string.Empty);
    }

    public static async Task<string> RegisterClientAsync(string login, string password, string lastName, string firstName, string phone)
    {
        var data = await Database.ProcedureAsync("dbo.sp_RegisterClient",
            Database.P("@Login", login), Database.P("@Password", password),
            Database.P("@LastName", lastName), Database.P("@FirstName", firstName),
            Database.P("@Phone", phone));
        return data.Rows.Count > 0 ? Convert.ToString(data.Rows[0]["Message"]) ?? "Регистрация выполнена." : "Регистрация выполнена.";
    }
}
