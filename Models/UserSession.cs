namespace WhiteRabbitRestaurant.Models;

public sealed record UserSession(int UserId, string Login, string FullName, string RoleCode, string RoleName)
{
    public bool IsClient => RoleCode == "CLIENT";
    public bool IsWaiter => RoleCode == "WAITER";
    public bool IsKitchen => RoleCode == "KITCHEN";
    public bool IsAdmin => RoleCode == "ADMIN";
}
