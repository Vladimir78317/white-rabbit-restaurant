using WhiteRabbitRestaurant.Forms;
using WhiteRabbitRestaurant.Services;

namespace WhiteRabbitRestaurant;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, eventArgs) =>
            CrashReporter.Show("Необработанная ошибка интерфейса", eventArgs.Exception);

        AppDomain.CurrentDomain.UnhandledException += (_, eventArgs) =>
        {
            if (eventArgs.ExceptionObject is Exception exception)
                CrashReporter.Log("Необработанная ошибка приложения", exception);
        };

        TaskScheduler.UnobservedTaskException += (_, eventArgs) =>
        {
            CrashReporter.Log("Необработанная ошибка фоновой задачи", eventArgs.Exception);
            eventArgs.SetObserved();
        };

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        try
        {
            Application.Run(new LoginForm());
        }
        catch (Exception exception)
        {
            CrashReporter.Show("Ошибка при запуске приложения", exception);
        }
    }
}
