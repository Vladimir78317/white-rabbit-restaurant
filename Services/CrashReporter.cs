using System.Text;

namespace WhiteRabbitRestaurant.Services;

internal static class CrashReporter
{
    private static readonly string LogFilePath =
        Path.Combine(AppContext.BaseDirectory, "white-rabbit-error.log");

    public static void Log(string scope, Exception exception)
    {
        try
        {
            var message = new StringBuilder()
                .AppendLine(new string('=', 78))
                .AppendLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"))
                .AppendLine(scope)
                .AppendLine(Database.ConnectionTargetForLog)
                .AppendLine(exception.ToString())
                .AppendLine()
                .ToString();

            File.AppendAllText(LogFilePath, message, Encoding.UTF8);
        }
        catch
        {
            // Ошибка логирования не должна завершать приложение.
        }
    }

    public static void Show(string scope, Exception exception)
    {
        Log(scope, exception);

        var text = $"{scope}.\n\n{exception.Message}\n\n" +
                   "Подробности сохранены в файле white-rabbit-error.log рядом с программой.";

        MessageBox.Show(text, "White Rabbit — ошибка", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }
}
