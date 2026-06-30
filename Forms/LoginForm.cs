using WhiteRabbitRestaurant.Models;
using WhiteRabbitRestaurant.Services;

namespace WhiteRabbitRestaurant.Forms;

public sealed class LoginForm : Form
{
    private readonly TextBox _login = new() { PlaceholderText = "Логин", Width = 300 };
    private readonly TextBox _password = new() { PlaceholderText = "Пароль", Width = 300, UseSystemPasswordChar = true };
    private readonly Label _status = new() { AutoSize = true, MaximumSize = new Size(300, 0), ForeColor = Color.Firebrick };
    private readonly Button _enter;
    private readonly Button _register;

    public LoginForm()
    {
        Text = "White Rabbit";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(430, 420);
        BackColor = Color.FromArgb(250, 248, 246);

        _enter = CreateButton("Войти", false);
        _register = CreateButton("Зарегистрироваться", true);
        _enter.Click += async (_, _) => await SignInAsync();
        _register.Click += (_, _) => OpenRegistration();

        var card = new Panel { BackColor = Color.White, Size = new Size(360, 330), Location = new Point(35, 44), BorderStyle = BorderStyle.FixedSingle };
        var panel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(30, 28, 30, 22)
        };
        panel.Controls.AddRange(new Control[]
        {
            new Label { Text = "WHITE RABBIT", Font = new Font("Segoe UI", 20, FontStyle.Bold), AutoSize = true, ForeColor = Color.FromArgb(35,35,35) },
            new Label { Text = "Вход в приложение ресторана", AutoSize = true, ForeColor = Color.DimGray, Margin = new Padding(3, 0, 3, 18) },
            _login, new Label { Height = 8 }, _password, new Label { Height = 14 }, _enter, new Label { Height = 8 }, _register,
            new Label { Height = 10 }, new Label { Text = "Новый клиент может зарегистрироваться и оформить заказ через приложение.", AutoSize = true, MaximumSize = new Size(300, 0), ForeColor = Color.DimGray }, _status
        });
        card.Controls.Add(panel);
        Controls.Add(card);
        AcceptButton = _enter;
    }

    private static Button CreateButton(string text, bool secondary)
    {
        var button = new Button
        {
            Text = text,
            Width = 300,
            Height = 38,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            BackColor = secondary ? Color.White : Color.FromArgb(152, 36, 43),
            ForeColor = secondary ? Color.FromArgb(35,35,35) : Color.White,
            Cursor = Cursors.Hand
        };
        button.FlatAppearance.BorderColor = secondary ? Color.Silver : Color.FromArgb(152,36,43);
        return button;
    }

    private async Task SignInAsync()
    {
        try
        {
            if (string.IsNullOrWhiteSpace(_login.Text) || string.IsNullOrWhiteSpace(_password.Text))
                throw new InvalidOperationException("Введите логин и пароль.");
            _enter.Enabled = _register.Enabled = false;
            _status.ForeColor = Color.DimGray;
            _status.Text = "Выполняется вход...";
            UserSession session = await AuthService.LoginAsync(_login.Text.Trim(), _password.Text);
            Hide();
            using var main = new MainForm(session);
            main.ShowDialog(this);
            Show();
            _password.Clear();
            _status.Text = string.Empty;
        }
        catch (Exception exception)
        {
            _status.ForeColor = Color.Firebrick;
            _status.Text = exception.Message;
        }
        finally
        {
            _enter.Enabled = _register.Enabled = true;
        }
    }

    private void OpenRegistration()
    {
        using var form = new RegistrationForm();
        if (form.ShowDialog(this) == DialogResult.OK)
        {
            _status.ForeColor = Color.FromArgb(40, 120, 60);
            _status.Text = "Регистрация завершена. Войдите под новым логином.";
        }
    }
}
